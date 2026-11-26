// Qt-inspired two-pass layout engine (measure size_hint -> arrange geometry).
// Supports VBox, HBox, Grid, Form, Stack, Splitter, ScrollArea, TabWidget,
// GroupBox, Frame, Panel, and docked StatusBar.
namespace goose_ui;

import std;
import types;
import theme;
import widget;
import tree;
import webview;

fn is_expanding(p: SizePolicy) -> bool {
    return match p { Expanding => true, _ => false };
}

fn child_stretch_h(w: const Widget&) -> f32 {
    if w.fixed_w >= 0.0 { return 0.0; }
    if w.stretch > 0.0 { return w.stretch; }
    return if is_expanding(w.policy_h) { 1.0 } else { 0.0 };
}

fn child_stretch_v(w: const Widget&) -> f32 {
    if w.fixed_h >= 0.0 { return 0.0; }
    if w.stretch > 0.0 { return w.stretch; }
    return if is_expanding(w.policy_v) { 1.0 } else { 0.0 };
}

recursive fn container_wants_expand_v(app: const App&, id: WidgetId) -> bool {
    guard app.valid_widget(id) && app.widgets[id.index].visible else { return false; }
    if app.widgets[id.index].fixed_h >= 0.0 { return false; }
    if is_expanding(app.widgets[id.index].policy_v) { return true; }
    match app.widgets[id.index].kind {
        Panel, Frame, GroupBox => {
            let is_vbox = match app.widgets[id.index].layout { VBox => true, _ => false };
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    if is_vbox && app.widgets[ch.index].fixed_h < 0.0 && app.widgets[ch.index].stretch > 0.0 {
                        return true;
                    }
                    if container_wants_expand_v(app, ch) {
                        return true;
                    }
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            return false;
        },
        _ => { return false; },
    }
}

fn effective_padding(app: const App&, id: WidgetId) -> Margins {
    var pd = app.widgets[id.index].padding;
    match app.widgets[id.index].kind {
        GroupBox => {
            if app.widgets[id.index].text.len > 0 {
                pd.top += 20.0;
            }
        },
        _ => {},
    }
    return pd;
}

recursive fn clear_layout_subtree(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].rect = RectF {};
    app.widgets[id.index].content_rect = RectF {};
    var ch = app.widgets[id.index].first_child;
    while app.valid_widget(ch) {
        clear_layout_subtree(app, ch);
        ch = app.widgets[ch.index].next_sibling;
    }
}

fn clamp_size(s: SizeF, w: const Widget&) -> SizeF {
    var rw = if w.fixed_w >= 0.0 { w.fixed_w } else { clamp_f32(s.w, w.min_size.w, w.max_size.w) };
    var rh = if w.fixed_h >= 0.0 { w.fixed_h } else { clamp_f32(s.h, w.min_size.h, w.max_size.h) };
    if rw < 0.0 { rw = 0.0; }
    if rh < 0.0 { rh = 0.0; }
    return SizeF { w: rw, h: rh };
}

// --- Pass 1: Measure intrinsic size hints bottom-up -------------------------

recursive fn measure_widget(app: App&, id: WidgetId) -> SizeF {
    guard app.valid_widget(id) else { return SizeF {}; }
    if !app.widgets[id.index].visible {
        app.widgets[id.index].size_hint = SizeF {};
        return SizeF {};
    }

    let kind = app.widgets[id.index].kind;
    let layout = app.widgets[id.index].layout;
    let ctrl_h = app.theme.control_height;
    var hint = SizeF {};

    match kind {
        Spacer => {
            hint = SizeF { w: 4.0, h: 4.0 };
        },
        Separator => {
            hint = match app.widgets[id.index].orientation {
                Horizontal => SizeF { w: 40.0, h: 9.0 },
                Vertical => SizeF { w: 9.0, h: 40.0 },
            };
        },
        Label => {
            let role = app.widgets[id.index].font_role;
            let fsz = font_size_for_role(app.theme, role);
            let tw = measure_text_width_role(app.str_view(app.widgets[id.index].text), app.theme, role);
            hint = SizeF { w: tw + 4.0, h: fsz * 1.45 + 2.0 };
        },
        Button => {
            let role = app.widgets[id.index].font_role;
            let tw = measure_text_width_role(app.str_view(app.widgets[id.index].text), app.theme, role);
            hint = SizeF { w: if tw + 28.0 > 72.0 { tw + 28.0 } else { 72.0 }, h: ctrl_h };
        },
        CheckBox, RadioButton => {
            let role = app.widgets[id.index].font_role;
            let tw = measure_text_width_role(app.str_view(app.widgets[id.index].text), app.theme, role);
            hint = SizeF { w: 26.0 + tw + 6.0, h: 26.0 };
        },
        ToggleSwitch => {
            let role = app.widgets[id.index].font_role;
            let tw = measure_text_width_role(app.str_view(app.widgets[id.index].text), app.theme, role);
            hint = SizeF { w: 46.0 + tw + 8.0, h: 28.0 };
        },
        LineEdit => {
            hint = SizeF { w: 180.0, h: ctrl_h };
        },
        Slider => {
            hint = match app.widgets[id.index].orientation {
                Horizontal => SizeF { w: 160.0, h: 26.0 },
                Vertical => SizeF { w: 26.0, h: 140.0 },
            };
        },
        SpinBox => {
            hint = SizeF { w: 120.0, h: ctrl_h };
        },
        ProgressBar => {
            hint = SizeF { w: 160.0, h: 22.0 };
        },
        ComboBox => {
            hint = SizeF { w: 160.0, h: ctrl_h };
        },
        ListView => {
            let n = app.item_count(id);
            let ih = app.widgets[id.index].item_height;
            let h = clamp_f32(n * ih + 8.0, 100.0, 260.0);
            hint = SizeF { w: 200.0, h: h };
        },
        StatusBar => {
            hint = SizeF { w: 200.0, h: 26.0 };
        },
        Canvas => {
            hint = SizeF { w: 240.0, h: 180.0 };
        },
        WebView => {
            hint = SizeF { w: 320.0, h: 240.0 };
        },
        TabWidget => {
            var max_w: f32 = 220.0;
            var max_h: f32 = 120.0;
            var bar_w: f32 = 12.0;
            var tab_cnt: i32 = 0;
            for i in app.list_items.len {
                if app.list_items[i].alive && eq(app.list_items[i].owner, id) {
                    let tw = measure_text_width_role(app.str_view(app.list_items[i].text), app.theme, FontRole.BodyBold);
                    let w = if tw + 28.0 > 76.0 { tw + 28.0 } else { 76.0 };
                    if tab_cnt > 0 { bar_w += 4.0; }
                    bar_w += w;
                    tab_cnt += 1;
                    let page = app.list_items[i].page;
                    if app.valid_widget(page) {
                        let cs = measure_widget(app, page);
                        if cs.w > max_w { max_w = cs.w; }
                        if cs.h > max_h { max_h = cs.h; }
                    }
                }
            }
            if bar_w > max_w { max_w = bar_w; }
            hint = SizeF { w: max_w + 2.0, h: app.widgets[id.index].tab_bar_height + max_h + 2.0 };
        },
        Splitter => {
            var sum_w: f32 = 0.0;
            var sum_h: f32 = 0.0;
            var max_w: f32 = 0.0;
            var max_h: f32 = 0.0;
            var ch = app.widgets[id.index].first_child;
            var idx: i32 = 0;
            while app.valid_widget(ch) && idx < 2 {
                let cs = measure_widget(app, ch);
                sum_w += cs.w;
                sum_h += cs.h;
                if cs.w > max_w { max_w = cs.w; }
                if cs.h > max_h { max_h = cs.h; }
                ch = app.widgets[ch.index].next_sibling;
                idx += 1;
            }
            hint = match app.widgets[id.index].orientation {
                Horizontal => SizeF { w: sum_w + app.widgets[id.index].splitter_size, h: max_h },
                Vertical => SizeF { w: max_w, h: sum_h + app.widgets[id.index].splitter_size },
            };
        },
        ScrollArea => {
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                measure_widget(app, ch);
                ch = app.widgets[ch.index].next_sibling;
            }
            hint = SizeF { w: 220.0, h: 180.0 };
        },
        Panel, Frame, GroupBox => {
            let pd = effective_padding(app, id);
            let sp = app.widgets[id.index].spacing;
            let inner = measure_container_children(app, id, layout, sp);
            hint = SizeF {
                w: inner.w + pd.left + pd.right,
                h: inner.h + pd.top + pd.bottom,
            };
        },
    }

    let final_hint = clamp_size(hint, app.widgets[id.index]);
    app.widgets[id.index].size_hint = final_hint;
    return final_hint;
}

recursive fn measure_container_children(app: App&, id: WidgetId, layout: LayoutKind, sp: f32) -> SizeF {
    var vis_count: i32 = 0;
    var ch = app.widgets[id.index].first_child;

    match layout {
        VBox => {
            var max_w: f32 = 0.0;
            var sum_h: f32 = 0.0;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let cs = measure_widget(app, ch);
                    if cs.w > max_w { max_w = cs.w; }
                    if vis_count > 0 { sum_h += sp; }
                    sum_h += cs.h;
                    vis_count += 1;
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            return SizeF { w: max_w, h: sum_h };
        },
        HBox => {
            var sum_w: f32 = 0.0;
            var max_h: f32 = 0.0;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let cs = measure_widget(app, ch);
                    if vis_count > 0 { sum_w += sp; }
                    sum_w += cs.w;
                    if cs.h > max_h { max_h = cs.h; }
                    vis_count += 1;
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            return SizeF { w: sum_w, h: max_h };
        },
        Grid => {
            let cols = if app.widgets[id.index].grid_cols > 0 { app.widgets[id.index].grid_cols } else { 1 };
            var max_cell_w: f32 = 0.0;
            var total_h: f32 = 0.0;
            var row_h: f32 = 0.0;
            var col: i32 = 0;
            var rows: i32 = 0;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let cs = measure_widget(app, ch);
                    if cs.w > max_cell_w { max_cell_w = cs.w; }
                    if cs.h > row_h { row_h = cs.h; }
                    vis_count += 1;
                    col += 1;
                    if col == cols {
                        if rows > 0 { total_h += sp; }
                        total_h += row_h;
                        rows += 1;
                        col = 0;
                        row_h = 0.0;
                    }
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            if vis_count == 0 { return SizeF {}; }
            if col > 0 {
                if rows > 0 { total_h += sp; }
                total_h += row_h;
            }
            return SizeF { w: cols * max_cell_w + (cols - 1) * sp, h: total_h };
        },
        Form => {
            let lw = app.widgets[id.index].form_label_width;
            var max_field_w: f32 = 120.0;
            var total_h: f32 = 0.0;
            var rows: i32 = 0;
            while app.valid_widget(ch) {
                // Skip invisible widgets
                while app.valid_widget(ch) && !app.widgets[ch.index].visible {
                    ch = app.widgets[ch.index].next_sibling;
                }
                if !app.valid_widget(ch) { break; }
                let s1 = measure_widget(app, ch);
                var field = app.widgets[ch.index].next_sibling;
                while app.valid_widget(field) && !app.widgets[field.index].visible {
                    field = app.widgets[field.index].next_sibling;
                }
                var rh = s1.h;
                if app.valid_widget(field) {
                    let s2 = measure_widget(app, field);
                    if s2.w > max_field_w { max_field_w = s2.w; }
                    if s2.h > rh { rh = s2.h; }
                    ch = app.widgets[field.index].next_sibling;
                } else {
                    ch = WIDGET_NONE;
                }
                if rows > 0 { total_h += sp; }
                total_h += rh;
                rows += 1;
            }
            if rows == 0 { return SizeF {}; }
            return SizeF { w: lw + sp + max_field_w, h: total_h };
        },
        Stack, None => {
            var max_w: f32 = 0.0;
            var max_h: f32 = 0.0;
            let is_none = match layout { None => true, _ => false };
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let cs = measure_widget(app, ch);
                    var cw = cs.w;
                    var ch_h = cs.h;
                    if is_none && (app.widgets[ch.index].has_abs_bounds || app.widgets[ch.index].anchor != 0) {
                        let ar = app.widgets[ch.index].abs_rect;
                        if ar.x + ar.w > cw { cw = ar.x + ar.w; }
                        if ar.y + ar.h > ch_h { ch_h = ar.y + ar.h; }
                    }
                    if cw > max_w { max_w = cw; }
                    if ch_h > max_h { max_h = ch_h; }
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            return SizeF { w: max_w, h: max_h };
        },
    }
}

// --- Pass 2: Arrange final bounding rectangles top-down ---------------------

fn align_span(origin: f32, avail: f32, pref: f32, al: Align, expanding: bool) -> f32, f32 {
    if expanding {
        return origin, avail;
    }
    let sz = if pref < avail { pref } else { avail };
    match al {
        Stretch => { return origin, avail; },
        Start => { return origin, sz; },
        Center => { return origin + (avail - sz) * 0.5, sz; },
        End => { return origin + (avail - sz), sz; },
    }
}

fn align_span_clamped(origin: f32, avail: f32, pref: f32, al: Align, expanding: bool, min_s: f32, max_s: f32, fixed_s: f32) -> f32, f32 {
    var sz: f32 = 0.0;
    if fixed_s >= 0.0 {
        sz = fixed_s;
    } else if expanding {
        sz = clamp_f32(avail, min_s, max_s);
    } else {
        let base = match al {
            Stretch => avail,
            _ => if pref < avail { pref } else { avail },
        };
        sz = clamp_f32(base, min_s, max_s);
    }
    if sz < 0.0 { sz = 0.0; }
    match al {
        Start, Stretch => { return origin, sz; },
        Center => { return origin + (avail - sz) * 0.5, sz; },
        End => { return origin + (avail - sz), sz; },
    }
}

recursive fn layout_widget(app: App&, id: WidgetId, bounds: RectF) {
    guard app.valid_widget(id) else { return; }
    if !app.widgets[id.index].visible {
        clear_layout_subtree(app, id);
        return;
    }

    app.widgets[id.index].rect = bounds;
    let kind = app.widgets[id.index].kind;
    let inner = inset(bounds, effective_padding(app, id));
    app.widgets[id.index].content_rect = inner;

    match kind {
        TabWidget => {
            let tbh = app.widgets[id.index].tab_bar_height;
            let page_rc = RectF {
                x: bounds.x + 1.0,
                y: bounds.y + tbh,
                w: if bounds.w > 2.0 { bounds.w - 2.0 } else { 0.0 },
                h: if bounds.h > tbh + 1.0 { bounds.h - tbh - 1.0 } else { 0.0 },
            };
            app.widgets[id.index].content_rect = page_rc;
            let sel = app.widgets[id.index].selected_index;
            // Clear all child subtrees first so non-tab or inactive pages never retain stale rects.
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                clear_layout_subtree(app, ch);
                ch = app.widgets[ch.index].next_sibling;
            }
            var idx: i32 = 0;
            for i in app.list_items.len {
                if app.list_items[i].alive && eq(app.list_items[i].owner, id) {
                    let page = app.list_items[i].page;
                    if idx == sel && app.valid_widget(page) {
                        layout_widget(app, page, page_rc);
                    }
                    idx += 1;
                }
            }
        },
        Splitter => {
            let bar = app.widgets[id.index].splitter_size;
            let ratio = app.widgets[id.index].split_ratio;
            let c0 = app.widgets[id.index].first_child;
            let c1 = if app.valid_widget(c0) { app.widgets[c0.index].next_sibling } else { WIDGET_NONE };
            match app.widgets[id.index].orientation {
                Horizontal => {
                    let avail = if bounds.w > bar { bounds.w - bar } else { 0.0 };
                    let w0 = avail * ratio;
                    let w1 = avail - w0;
                    if app.valid_widget(c0) {
                        layout_widget(app, c0, RectF { x: bounds.x, y: bounds.y, w: w0, h: bounds.h });
                    }
                    if app.valid_widget(c1) {
                        layout_widget(app, c1, RectF { x: bounds.x + w0 + bar, y: bounds.y, w: w1, h: bounds.h });
                    }
                },
                Vertical => {
                    let avail = if bounds.h > bar { bounds.h - bar } else { 0.0 };
                    let h0 = avail * ratio;
                    let h1 = avail - h0;
                    if app.valid_widget(c0) {
                        layout_widget(app, c0, RectF { x: bounds.x, y: bounds.y, w: bounds.w, h: h0 });
                    }
                    if app.valid_widget(c1) {
                        layout_widget(app, c1, RectF { x: bounds.x, y: bounds.y + h0 + bar, w: bounds.w, h: h1 });
                    }
                },
            }
        },
        ScrollArea => {
            let sb_w: f32 = 10.0;
            let pd = app.widgets[id.index].padding;
            let sp = app.widgets[id.index].spacing;
            let view_w = if bounds.w > pd.left + pd.right + sb_w { bounds.w - pd.left - pd.right - sb_w } else { 0.0 };
            let view_h = if bounds.h > pd.top + pd.bottom { bounds.h - pd.top - pd.bottom } else { 0.0 };

            // Compute total content height first.
            var total_h: f32 = 0.0;
            var vis: i32 = 0;
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    if vis > 0 { total_h += sp; }
                    total_h += app.widgets[ch.index].size_hint.h;
                    vis += 1;
                }
                ch = app.widgets[ch.index].next_sibling;
            }

            let max_scroll = if total_h > view_h { total_h - view_h } else { 0.0 };
            app.widgets[id.index].scroll_max_y = max_scroll;
            app.widgets[id.index].scroll_y = clamp_f32(app.widgets[id.index].scroll_y, 0.0, max_scroll);

            var cy = bounds.y + pd.top - app.widgets[id.index].scroll_y;
            ch = app.widgets[id.index].first_child;
            vis = 0;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    if vis > 0 { cy += sp; }
                    let ch_h = app.widgets[ch.index].size_hint.h;
                    let min_w = if app.widgets[ch.index].min_size.w < view_w { app.widgets[ch.index].min_size.w } else { view_w };
                    let cx, cw = align_span_clamped(
                        bounds.x + pd.left,
                        view_w,
                        app.widgets[ch.index].size_hint.w,
                        app.widgets[ch.index].align_h,
                        is_expanding(app.widgets[ch.index].policy_h) && app.widgets[ch.index].fixed_w < 0.0,
                        min_w,
                        app.widgets[ch.index].max_size.w,
                        app.widgets[ch.index].fixed_w
                    );
                    layout_widget(app, ch, RectF { x: cx, y: cy, w: cw, h: ch_h });
                    cy += ch_h;
                    vis += 1;
                }
                ch = app.widgets[ch.index].next_sibling;
            }
        },
        ListView => {
            let n = app.item_count(id);
            let total_h = n * app.widgets[id.index].item_height + 8.0;
            let max_s = if total_h > bounds.h { total_h - bounds.h } else { 0.0 };
            app.widgets[id.index].scroll_max_y = max_s;
            app.widgets[id.index].scroll_y = clamp_f32(app.widgets[id.index].scroll_y, 0.0, max_s);
        },
        Panel, Frame, GroupBox => {
            layout_container_children(app, id, inner);
        },
        _ => {},
    }
}

recursive fn layout_container_children(app: App&, id: WidgetId, inner: RectF) {
    let layout = app.widgets[id.index].layout;
    let sp = app.widgets[id.index].spacing;

    match layout {
        VBox => {
            var vis_count: i32 = 0;
            var fixed_sum: f32 = 0.0;
            var stretch_sum: f32 = 0.0;
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    vis_count += 1;
                    let st = child_stretch_v(app.widgets[ch.index]);
                    if st > 0.0 {
                        stretch_sum += st;
                    } else {
                        fixed_sum += app.widgets[ch.index].size_hint.h;
                    }
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            if vis_count == 0 { return; }

            let total_sp = (vis_count - 1) * sp;
            let rem = inner.h - fixed_sum - total_sp;
            let extra = if rem > 0.0 { rem } else { 0.0 };

            var cy = inner.y;
            ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let st = child_stretch_v(app.widgets[ch.index]);
                    var ch_h = if st > 0.0 && stretch_sum > 0.0 {
                        extra * (st / stretch_sum)
                    } else {
                        app.widgets[ch.index].size_hint.h
                    };
                    if app.widgets[ch.index].fixed_h >= 0.0 {
                        ch_h = app.widgets[ch.index].fixed_h;
                    } else {
                        ch_h = clamp_f32(ch_h, app.widgets[ch.index].min_size.h, app.widgets[ch.index].max_size.h);
                    }

                    let cx, cw = align_span_clamped(
                        inner.x,
                        inner.w,
                        app.widgets[ch.index].size_hint.w,
                        app.widgets[ch.index].align_h,
                        is_expanding(app.widgets[ch.index].policy_h) && app.widgets[ch.index].fixed_w < 0.0,
                        app.widgets[ch.index].min_size.w,
                        app.widgets[ch.index].max_size.w,
                        app.widgets[ch.index].fixed_w
                    );
                    layout_widget(app, ch, RectF { x: cx, y: cy, w: cw, h: ch_h });
                    cy += ch_h + sp;
                } else {
                    clear_layout_subtree(app, ch);
                }
                ch = app.widgets[ch.index].next_sibling;
            }
        },
        HBox => {
            var vis_count: i32 = 0;
            var fixed_sum: f32 = 0.0;
            var stretch_sum: f32 = 0.0;
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    vis_count += 1;
                    let st = child_stretch_h(app.widgets[ch.index]);
                    if st > 0.0 {
                        stretch_sum += st;
                    } else {
                        fixed_sum += app.widgets[ch.index].size_hint.w;
                    }
                }
                ch = app.widgets[ch.index].next_sibling;
            }
            if vis_count == 0 { return; }

            let total_sp = (vis_count - 1) * sp;
            let rem = inner.w - fixed_sum - total_sp;
            let extra = if rem > 0.0 { rem } else { 0.0 };

            var cx = inner.x;
            ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let st = child_stretch_h(app.widgets[ch.index]);
                    var ch_w = if st > 0.0 && stretch_sum > 0.0 {
                        extra * (st / stretch_sum)
                    } else {
                        app.widgets[ch.index].size_hint.w
                    };
                    if app.widgets[ch.index].fixed_w >= 0.0 {
                        ch_w = app.widgets[ch.index].fixed_w;
                    } else {
                        ch_w = clamp_f32(ch_w, app.widgets[ch.index].min_size.w, app.widgets[ch.index].max_size.w);
                    }

                    // In HBox, fixed controls center vertically while expanding containers fill cross-axis height.
                    let exp_v = app.widgets[ch.index].fixed_h < 0.0 &&
                        (is_expanding(app.widgets[ch.index].policy_v) || container_wants_expand_v(app, ch));
                    let cross_align = if !exp_v {
                        match app.widgets[ch.index].align_v {
                            Stretch => Align.Center,
                            _ => app.widgets[ch.index].align_v,
                        }
                    } else {
                        app.widgets[ch.index].align_v
                    };
                    let cy, ch_h = align_span_clamped(
                        inner.y,
                        inner.h,
                        app.widgets[ch.index].size_hint.h,
                        cross_align,
                        exp_v,
                        app.widgets[ch.index].min_size.h,
                        app.widgets[ch.index].max_size.h,
                        app.widgets[ch.index].fixed_h
                    );
                    layout_widget(app, ch, RectF { x: cx, y: cy, w: ch_w, h: ch_h });
                    cx += ch_w + sp;
                } else {
                    clear_layout_subtree(app, ch);
                }
                ch = app.widgets[ch.index].next_sibling;
            }
        },
        Grid => {
            let cols = if app.widgets[id.index].grid_cols > 0 { app.widgets[id.index].grid_cols } else { 1 };
            let cell_w = if inner.w > (cols - 1) * sp { (inner.w - (cols - 1) * sp) / cols } else { 0.0 };
            var cy = inner.y;
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                // Measure one row of `cols` visible children.
                var row_start = ch;
                var row_h: f32 = 0.0;
                var c: i32 = 0;
                while app.valid_widget(ch) && c < cols {
                    if app.widgets[ch.index].visible {
                        let h = app.widgets[ch.index].size_hint.h;
                        if h > row_h { row_h = h; }
                        c += 1;
                    }
                    ch = app.widgets[ch.index].next_sibling;
                }
                if c == 0 { break; }

                // Place the row.
                var cur = row_start;
                var placed: i32 = 0;
                while app.valid_widget(cur) && placed < c {
                    if app.widgets[cur.index].visible {
                        let cx = inner.x + placed * (cell_w + sp);
                        let wy, wh = align_span(
                            cy,
                            row_h,
                            app.widgets[cur.index].size_hint.h,
                            Align.Center,
                            is_expanding(app.widgets[cur.index].policy_v)
                        );
                        layout_widget(app, cur, RectF { x: cx, y: wy, w: cell_w, h: wh });
                        placed += 1;
                    }
                    cur = app.widgets[cur.index].next_sibling;
                }
                cy += row_h + sp;
            }
        },
        Form => {
            let lw = app.widgets[id.index].form_label_width;
            let fw = if inner.w > lw + sp { inner.w - lw - sp } else { 0.0 };
            var cy = inner.y;
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                while app.valid_widget(ch) && !app.widgets[ch.index].visible {
                    ch = app.widgets[ch.index].next_sibling;
                }
                if !app.valid_widget(ch) { break; }
                let label_id = ch;
                var field_id = app.widgets[ch.index].next_sibling;
                while app.valid_widget(field_id) && !app.widgets[field_id.index].visible {
                    field_id = app.widgets[field_id.index].next_sibling;
                }

                var row_h = app.widgets[label_id.index].size_hint.h;
                if app.valid_widget(field_id) {
                    let fh = app.widgets[field_id.index].size_hint.h;
                    if fh > row_h { row_h = fh; }
                }

                let ly, lh = align_span(cy, row_h, app.widgets[label_id.index].size_hint.h, Align.Center, false);
                layout_widget(app, label_id, RectF { x: inner.x, y: ly, w: lw, h: lh });

                if app.valid_widget(field_id) {
                    let fy, fh = align_span(
                        cy,
                        row_h,
                        app.widgets[field_id.index].size_hint.h,
                        Align.Center,
                        is_expanding(app.widgets[field_id.index].policy_v)
                    );
                    layout_widget(app, field_id, RectF { x: inner.x + lw + sp, y: fy, w: fw, h: fh });
                    ch = app.widgets[field_id.index].next_sibling;
                } else {
                    ch = WIDGET_NONE;
                }
                cy += row_h + sp;
            }
        },
        Stack => {
            let sel = app.widgets[id.index].selected_index;
            var ch = app.widgets[id.index].first_child;
            var idx: i32 = 0;
            while app.valid_widget(ch) {
                if idx == sel && app.widgets[ch.index].visible {
                    layout_widget(app, ch, inner);
                } else {
                    clear_layout_subtree(app, ch);
                }
                ch = app.widgets[ch.index].next_sibling;
                idx += 1;
            }
        },
        None => {
            var ch = app.widgets[id.index].first_child;
            while app.valid_widget(ch) {
                if app.widgets[ch.index].visible {
                    let has_abs = app.widgets[ch.index].has_abs_bounds || app.widgets[ch.index].anchor != 0;
                    if has_abs {
                        let anc = app.widgets[ch.index].anchor;
                        let ar = app.widgets[ch.index].abs_rect;
                        // Lazily capture the parent's initial inner size when ref_w / ref_h were omitted.
                        if app.widgets[ch.index].abs_ref.w <= 0.0 && inner.w > 0.0 {
                            app.widgets[ch.index].abs_ref.w = inner.w;
                        }
                        if app.widgets[ch.index].abs_ref.h <= 0.0 && inner.h > 0.0 {
                            app.widgets[ch.index].abs_ref.h = inner.h;
                        }
                        let ref_s = app.widgets[ch.index].abs_ref;
                        let dx = if ref_s.w > 0.0 { inner.w - ref_s.w } else { 0.0 };
                        let dy = if ref_s.h > 0.0 { inner.h - ref_s.h } else { 0.0 };

                        let has_l = (anc & ANCHOR_LEFT) != 0;
                        let has_r = (anc & ANCHOR_RIGHT) != 0;
                        let has_t = (anc & ANCHOR_TOP) != 0;
                        let has_b = (anc & ANCHOR_BOTTOM) != 0;

                        var cx = inner.x + ar.x;
                        var cw = ar.w;
                        if has_l && has_r {
                            cw = if ar.w + dx > 0.0 { ar.w + dx } else { 0.0 };
                        } else if has_r && !has_l {
                            cx = inner.x + ar.x + dx;
                        }

                        var cy = inner.y + ar.y;
                        var ch_h = ar.h;
                        if has_t && has_b {
                            ch_h = if ar.h + dy > 0.0 { ar.h + dy } else { 0.0 };
                        } else if has_b && !has_t {
                            cy = inner.y + ar.y + dy;
                        }

                        layout_widget(app, ch, RectF { x: cx, y: cy, w: cw, h: ch_h });
                    } else {
                        let sh = app.widgets[ch.index].size_hint;
                        layout_widget(app, ch, RectF { x: inner.x, y: inner.y, w: sh.w, h: sh.h });
                    }
                } else {
                    clear_layout_subtree(app, ch);
                }
                ch = app.widgets[ch.index].next_sibling;
            }
        },
    }
}

// Recomputes layout for a window if dirty (or forced).
fn update_layout(app: App&, win: WindowId, force: bool = false) {
    guard app.valid_window(win) else { return; }
    if !force && !app.windows[win.index].layout_dirty { return; }

    let w = app.windows[win.index].width as f32;
    let h = app.windows[win.index].height as f32;
    var sb_h: f32 = 0.0;

    let sb = app.windows[win.index].status_bar;
    if app.valid_widget(sb) {
        if app.widgets[sb.index].visible {
            sb_h = if app.widgets[sb.index].fixed_h > 0.0 { app.widgets[sb.index].fixed_h } else { 26.0 };
            measure_widget(app, sb);
            layout_widget(app, sb, RectF { x: 0.0, y: if h > sb_h { h - sb_h } else { 0.0 }, w: w, h: sb_h });
        } else {
            clear_layout_subtree(app, sb);
        }
    }

    let root_id = app.windows[win.index].root_widget;
    if app.valid_widget(root_id) {
        measure_widget(app, root_id);
        let root_h = if h > sb_h { h - sb_h } else { 0.0 };
        layout_widget(app, root_id, RectF { x: 0.0, y: 0.0, w: w, h: root_h });
    }

    let foc = app.windows[win.index].focused;
    if app.valid_widget(foc) {
        match app.widgets[foc.index].kind {
            LineEdit => { ensure_line_edit_caret_visible(app, foc); },
            _ => {},
        }
    }

    app.sync_window_webviews(win);

    app.windows[win.index].layout_dirty = false;
    app.windows[win.index].dirty = true;
}
