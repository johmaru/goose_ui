// Event routing, hit testing, widget state machines, Signal/Slot connections,
// keyboard navigation, LineEdit editing, and Qt-style application event loop.
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import theme;
import widget;
import tree;
import log;
import layout;
import painter;

// --- Signal Queue & Declarative Connection Execution ------------------------

fn push_signal(app: App&, sig: Signal) {
    if app.log.ui_events && (app.log.file.is_valid() || app.log.also_stderr) {
        app.log_signal(sig);
    }
    app.signals.push(sig);
}

fn next_signal(app: App&, out: Signal&) -> bool {
    if app.signal_head >= app.signals.len {
        if app.signals.len > 0 {
            app.signals.clear();
            app.signal_head = 0;
        }
        out = Signal.None;
        return false;
    }
    out = app.signals[app.signal_head];
    app.signal_head += 1;
    if app.signal_head >= app.signals.len {
        app.signals.clear();
        app.signal_head = 0;
    }
    return true;
}

fn signal_kind_code(k: SignalKind) -> i32 {
    return match k {
        OnClick => 0,
        OnToggle => 1,
        OnValueChange => 2,
        OnTextChange => 3,
        OnTextSubmit => 4,
        OnSelectionChange => 5,
        OnTabChange => 6,
    };
}

recursive fn run_connections(app: App&, sender: WidgetId, kind_code: i32, bval: bool, fval: f64, ival: i32) {
    if app.connection_depth >= 8 { return; }
    app.connection_depth += 1;
    defer { app.connection_depth -= 1; }

    // Snapshot count so connections added inside handlers don't loop infinitely.
    let n = app.connections.len;
    for i in n {
        if i >= app.connections.len { break; }
        if !app.connections[i].alive { continue; }
        if !eq(app.connections[i].sender, sender) { continue; }
        if signal_kind_code(app.connections[i].signal) != kind_code { continue; }

        let recv = app.connections[i].receiver;
        let param = app.connections[i].param_f64;
        match app.connections[i].slot {
            SetVisible => { app.set_visible(recv, bval); },
            SetVisibleInverted => { app.set_visible(recv, !bval); },
            SetEnabled => { app.set_enabled(recv, bval); },
            SetEnabledInverted => { app.set_enabled(recv, !bval); },
            SetChecked => { app.set_checked(recv, bval); },
            ToggleChecked => { app.set_checked(recv, !app.is_checked(recv)); },
            SetValue => { app.set_value(recv, fval); },
            SetValueLabel => {
                if app.valid_widget(recv) {
                    var buf: u8[>..] = [];
                    let iv = (if fval >= 0.0 { fval + 0.5 } else { fval - 0.5 }) as! i64;
                    format(buf, iv);
                    app.set_text(recv, buf);
                }
            },
            SyncText => {
                if app.valid_widget(sender) && app.valid_widget(recv) {
                    var buf: u8[>..] = [];
                    buf.append(app.str_view(app.widgets[sender.index].text));
                    app.set_text(recv, buf);
                }
            },
            SetCurrentTab => { app.set_current_tab(recv, ival); },
            ClearText => { app.set_text(recv, ""); },
            IncrementValue => {
                if app.valid_widget(recv) {
                    let prev_v = app.widgets[recv.index].value;
                    app.set_value(recv, prev_v + param);
                    let nv = app.widgets[recv.index].value;
                    if nv != prev_v {
                        let rwin = app.widgets[recv.index].window;
                        app.run_connections(recv, 2, nv != 0.0, nv, nv as! i32);
                        app.push_signal(Signal.ValueChanged { widget: recv, window: rwin, value: nv });
                    }
                }
            },
            CloseWindow => {
                if app.valid_widget(sender) {
                    app.close_window(app.widgets[sender.index].window);
                }
            },
            ToggleTheme => { app.toggle_theme(); },
        }
    }
}

fn emit_clicked(app: App&, id: WidgetId, win: WindowId) {
    app.run_connections(id, 0, true, 1.0, 0);
    app.push_signal(Signal.Clicked { widget: id, window: win });
}

fn emit_toggled(app: App&, id: WidgetId, win: WindowId, checked: bool) {
    app.run_connections(id, 1, checked, if checked { 1.0 } else { 0.0 }, if checked { 1 } else { 0 });
    app.push_signal(Signal.Toggled { widget: id, window: win, checked: checked });
}

fn emit_value_changed(app: App&, id: WidgetId, win: WindowId, val: f64) {
    app.run_connections(id, 2, val != 0.0, val, val as! i32);
    app.push_signal(Signal.ValueChanged { widget: id, window: win, value: val });
}

fn emit_text_changed(app: App&, id: WidgetId, win: WindowId) {
    app.run_connections(id, 3, app.text(id).len > 0, 0.0, app.text(id).len as! i32);
    app.push_signal(Signal.TextChanged { widget: id, window: win });
}

fn emit_text_submitted(app: App&, id: WidgetId, win: WindowId) {
    app.run_connections(id, 4, true, 0.0, 0);
    app.push_signal(Signal.TextSubmitted { widget: id, window: win });
}

fn emit_selection_changed(app: App&, id: WidgetId, win: WindowId, idx: i32) {
    app.run_connections(id, 5, idx >= 0, idx, idx);
    app.push_signal(Signal.SelectionChanged { widget: id, window: win, index: idx });
}

fn emit_tab_changed(app: App&, id: WidgetId, win: WindowId, idx: i32) {
    app.run_connections(id, 6, idx >= 0, idx, idx);
    app.push_signal(Signal.TabChanged { widget: id, window: win, index: idx });
}

// --- Hit Testing ------------------------------------------------------------

fn splitter_handle_rect(app: const App&, id: WidgetId) -> RectF {
    guard app.valid_widget(id) else { return RectF {}; }
    let r = app.widgets[id.index].rect;
    let bar = app.widgets[id.index].splitter_size;
    let ratio = app.widgets[id.index].split_ratio;
    return match app.widgets[id.index].orientation {
        Horizontal => {
            let avail = if r.w > bar { r.w - bar } else { 0.0 };
            RectF { x: r.x + avail * ratio - 2.0, y: r.y, w: bar + 4.0, h: r.h }
        },
        Vertical => {
            let avail = if r.h > bar { r.h - bar } else { 0.0 };
            RectF { x: r.x, y: r.y + avail * ratio - 2.0, w: r.w, h: bar + 4.0 }
        },
    };
}

recursive fn hit_test_widget(app: const App&, id: WidgetId, px: f32, py: f32) -> WidgetId {
    guard app.valid_widget(id) else { return WIDGET_NONE; }
    if !app.widgets[id.index].visible { return WIDGET_NONE; }
    let r = app.widgets[id.index].rect;
    if !contains(r, px, py) { return WIDGET_NONE; }

    // Splitter handle takes priority over children.
    match app.widgets[id.index].kind {
        Splitter => {
            if contains(splitter_handle_rect(app, id), px, py) {
                return id;
            }
        },
        TabWidget => {
            // Click in tab header bar hits the TabWidget itself.
            if py < r.y + app.widgets[id.index].tab_bar_height {
                return id;
            }
        },
        _ => {},
    }

    // Walk children in reverse order (topmost painted last).
    var ch = app.widgets[id.index].last_child;
    while app.valid_widget(ch) {
        let hit = hit_test_widget(app, ch, px, py);
        if app.valid_widget(hit) {
            return hit;
        }
        ch = app.widgets[ch.index].prev_sibling;
    }

    return id;
}

fn hit_test(app: const App&, win: WindowId, px: f32, py: f32) -> WidgetId {
    guard app.valid_window(win) else { return WIDGET_NONE; }
    let root_id = app.windows[win.index].root_widget;
    return hit_test_widget(app, root_id, px, py);
}

// --- Focus Management (Tab / Shift+Tab traversal) ---------------------------

fn set_focus(app: App&, win: WindowId, id: WidgetId) {
    guard app.valid_window(win) else { return; }
    let prev = app.windows[win.index].focused;
    if eq(prev, id) { return; }

    if app.valid_widget(prev) {
        app.push_signal(Signal.FocusChanged { widget: prev, window: win, focused: false });
    }
    if app.valid_widget(id) && app.widgets[id.index].visible && app.widgets[id.index].enabled && app.widgets[id.index].focusable {
        app.windows[win.index].focused = id;
        match app.widgets[id.index].kind {
            LineEdit => { ensure_line_edit_caret_visible(app, id); },
            _ => {},
        }
        app.push_signal(Signal.FocusChanged { widget: id, window: win, focused: true });
    } else {
        app.windows[win.index].focused = WIDGET_NONE;
    }
    app.mark_dirty(win);
}

recursive fn collect_focusable(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }
    if !app.widgets[id.index].visible || !app.widgets[id.index].enabled { return; }
    let r = app.widgets[id.index].rect;
    if r.w <= 0.0 || r.h <= 0.0 { return; }

    if app.widgets[id.index].focusable {
        app.focus_order.push(id);
    }
    var ch = app.widgets[id.index].first_child;
    while app.valid_widget(ch) {
        collect_focusable(app, ch);
        ch = app.widgets[ch.index].next_sibling;
    }
}

fn cycle_focus(app: App&, win: WindowId, reverse: bool) {
    guard app.valid_window(win) else { return; }
    app.focus_order.clear();
    let root_id = app.windows[win.index].root_widget;
    collect_focusable(app, root_id);
    let n = app.focus_order.len;
    if n == 0 { return; }

    let cur = app.windows[win.index].focused;
    var cur_idx: i64 = -1;
    for i in n {
        if eq(app.focus_order[i], cur) {
            cur_idx = i;
            break;
        }
    }

    var next_idx: i64 = 0;
    if cur_idx < 0 {
        next_idx = if reverse { n - 1 } else { 0 };
    } else if reverse {
        next_idx = (cur_idx - 1) % n;
    } else {
        next_idx = (cur_idx + 1) % n;
    }
    let target = app.focus_order[next_idx];
    app.set_focus(win, target);
}

// --- Cursor Update ----------------------------------------------------------

fn update_cursor(app: App&, win: WindowId, hit: WidgetId) {
    guard app.valid_window(win) && !app.windows[win.index].headless else { return; }
    var shape = CursorShape.Arrow;
    if app.valid_widget(hit) && app.widgets[hit.index].enabled {
        shape = match app.widgets[hit.index].kind {
            Splitter => match app.widgets[hit.index].orientation {
                Horizontal => CursorShape.SizeWE,
                Vertical => CursorShape.SizeNS,
            },
            _ => app.widgets[hit.index].cursor,
        };
    }
    let idc = match shape {
        Arrow => win32::IDC_ARROW,
        Hand => win32::IDC_HAND,
        IBeam => win32::IDC_IBEAM,
        SizeWE => win32::IDC_SIZEWE,
        SizeNS => win32::IDC_SIZENS,
    };
    win32::set_system_cursor(idc);
    app.active_cursor = shape;
}

// --- LineEdit Text Editing Helpers ------------------------------------------

fn line_edit_delete_selection(app: App&, id: WidgetId) -> bool {
    guard app.valid_widget(id) else { return false; }
    let c = app.widgets[id.index].caret;
    let a = app.widgets[id.index].sel_anchor;
    if c == a { return false; }

    let s0 = if c < a { c } else { a };
    let s1 = if c > a { c } else { a };
    let n = app.widgets[id.index].text.len;
    let lo = if s0 < 0 { 0 } else if s0 > n { n } else { s0 };
    let hi = if s1 < 0 { 0 } else if s1 > n { n } else { s1 };
    if lo >= hi {
        app.widgets[id.index].sel_anchor = lo;
        app.widgets[id.index].caret = lo;
        return false;
    }

    var tmp: u8[>..] = [];
    {
        let cur = app.str_view(app.widgets[id.index].text);
        if lo > 0 { tmp.append(cur[..lo]); }
        if hi < n { tmp.append(cur[hi..]); }
    }
    str_set(app.str_pool, app.widgets[id.index].text, tmp, 64);
    app.widgets[id.index].caret = lo;
    app.widgets[id.index].sel_anchor = lo;
    ensure_line_edit_caret_visible(app, id);
    return true;
}

fn line_edit_insert_bytes(app: App&, id: WidgetId, bytes: const u8[:]) -> bool {
    guard app.valid_widget(id) && !app.widgets[id.index].read_only else { return false; }
    if bytes.len == 0 { return false; }
    line_edit_delete_selection(app, id);

    let n = app.widgets[id.index].text.len;
    let pos = clamp_f32(app.widgets[id.index].caret, 0.0, n) as! i32;
    var tmp: u8[>..] = [];
    {
        let cur = app.str_view(app.widgets[id.index].text);
        if pos > 0 { tmp.append(cur[..pos]); }
        tmp.append(bytes);
        if pos < n { tmp.append(cur[pos..]); }
    }
    str_set(app.str_pool, app.widgets[id.index].text, tmp, 64);
    let new_pos = pos + (bytes.len as! i32);
    app.widgets[id.index].caret = new_pos;
    app.widgets[id.index].sel_anchor = new_pos;
    ensure_line_edit_caret_visible(app, id);
    return true;
}

fn line_edit_selected_text(app: const App&, id: WidgetId, out: u8[>..]&) -> bool {
    guard app.valid_widget(id) else { return false; }
    let c = app.widgets[id.index].caret;
    let a = app.widgets[id.index].sel_anchor;
    if c == a { return false; }
    let s0 = if c < a { c } else { a };
    let s1 = if c > a { c } else { a };
    let n = app.widgets[id.index].text.len;
    let lo = if s0 < 0 { 0 } else if s0 > n { n } else { s0 };
    let hi = if s1 < 0 { 0 } else if s1 > n { n } else { s1 };
    if lo >= hi { return false; }
    let cur = app.str_view(app.widgets[id.index].text);
    out.append(cur[lo..hi]);
    return true;
}

// --- Slider Value From Pointer Helper ---------------------------------------

fn slider_set_from_pos(app: App&, id: WidgetId, win: WindowId, px: f32, py: f32) {
    guard app.valid_widget(id) else { return; }
    let r = app.widgets[id.index].rect;
    let thumb_r: f32 = 8.0;
    let frac = match app.widgets[id.index].orientation {
        Horizontal => {
            let tw = if r.w > thumb_r * 2.0 { r.w - thumb_r * 2.0 } else { 1.0 };
            clamp_f32((px - (r.x + thumb_r)) / tw, 0.0, 1.0)
        },
        Vertical => {
            let th = if r.h > thumb_r * 2.0 { r.h - thumb_r * 2.0 } else { 1.0 };
            1.0 - clamp_f32((py - (r.y + thumb_r)) / th, 0.0, 1.0)
        },
    };
    let min_v = app.widgets[id.index].min_value;
    let max_v = app.widgets[id.index].max_value;
    let step = app.widgets[id.index].step;
    var raw = min_v + (max_v - min_v) * frac;
    if step > 0.0 {
        let steps = ((raw - min_v) / step) + 0.5;
        let snapped = (steps as! i64) * step + min_v;
        raw = clamp_f64(snapped, min_v, max_v);
    }
    if raw != app.widgets[id.index].value {
        app.widgets[id.index].value = raw;
        app.mark_dirty(win);
        app.emit_value_changed(id, win, raw);
    }
}

// --- Scroll ancestor helper -------------------------------------------------

fn find_scroll_ancestor(app: const App&, start: WidgetId) -> WidgetId {
    var cur = start;
    while app.valid_widget(cur) {
        match app.widgets[cur.index].kind {
            ListView, ScrollArea => { return cur; },
            _ => {},
        }
        cur = app.widgets[cur.index].parent;
    }
    return WIDGET_NONE;
}

// --- Modifier Key Reader ----------------------------------------------------

fn current_key_mods(headless: bool) -> u32 {
    if headless { return 0; }
    var mods: u32 = 0;
    if win32::GetAsyncKeyState(win32::VK_SHIFT as! i32) < 0 { mods |= KMOD_SHIFT; }
    if win32::GetAsyncKeyState(win32::VK_CONTROL as! i32) < 0 { mods |= KMOD_CTRL; }
    if win32::GetAsyncKeyState(win32::VK_MENU as! i32) < 0 { mods |= KMOD_ALT; }
    return mods;
}

// --- Tooltip Timer & List/Combo Scroll Helpers ------------------------------

fn schedule_tooltip_timer(app: App&, win: WindowId, hit: WidgetId) {
    cancel_tooltip_timer(app, win);
    guard app.valid_window(win) && app.valid_widget(hit) else { return; }
    if app.widgets[hit.index].tooltip.len > 0 && !app.windows[win.index].mouse_down {
        if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
            app.windows[win.index].hwnd.set_timer(INTERNAL_TOOLTIP_TIMER_ID, 460);
            app.windows[win.index].tooltip_timer_active = true;
        }
    }
}

fn ensure_list_item_visible(app: App&, id: WidgetId, idx: i32) {
    guard app.valid_widget(id) && idx >= 0 else { return; }
    let ih = app.widgets[id.index].item_height;
    let r = app.widgets[id.index].rect;
    let view_h = if r.h > 8.0 { r.h - 8.0 } else { 0.0 };
    if view_h <= 0.0 || app.widgets[id.index].scroll_max_y <= 0.0 { return; }
    let item_top = idx * ih;
    let item_bot = item_top + ih;
    var sy = app.widgets[id.index].scroll_y;
    if item_top < sy {
        sy = item_top;
    } else if item_bot > sy + view_h {
        sy = item_bot - view_h;
    }
    app.widgets[id.index].scroll_y = clamp_f32(sy, 0.0, app.widgets[id.index].scroll_max_y);
}

fn ensure_combo_item_visible(app: App&, win: WindowId, combo: WidgetId, idx: i32) {
    let cnt = app.item_count(combo);
    let max_sc = if cnt > 8 { cnt - 8 } else { 0 };
    var sc = app.windows[win.index].open_combo_scroll;
    if idx >= 0 {
        if idx < sc { sc = idx; }
        if idx >= sc + 8 { sc = idx - 7; }
    }
    if sc < 0 { sc = 0; }
    if sc > max_sc { sc = max_sc; }
    app.windows[win.index].open_combo_scroll = sc;
}

// --- Synthetic & OS Event Handlers ------------------------------------------

fn handle_mouse_move(app: App&, win: WindowId, px: f32, py: f32) {
    guard app.valid_window(win) else { return; }
    app.update_layout(win);
    app.windows[win.index].mouse_x = px;
    app.windows[win.index].mouse_y = py;

    // 1. Handle active capture (dragging slider, splitter, text selection, or canvas)
    let cap = app.windows[win.index].captured;
    if app.valid_widget(cap) && app.windows[win.index].mouse_down {
        match app.widgets[cap.index].kind {
            Slider => {
                slider_set_from_pos(app, cap, win, px, py);
                return;
            },
            Splitter => {
                let r = app.widgets[cap.index].rect;
                let bar = app.widgets[cap.index].splitter_size;
                let ratio = match app.widgets[cap.index].orientation {
                    Horizontal => {
                        let avail = if r.w > bar { r.w - bar } else { 1.0 };
                        clamp_f32((px - r.x - bar * 0.5) / avail, 0.12, 0.88)
                    },
                    Vertical => {
                        let avail = if r.h > bar { r.h - bar } else { 1.0 };
                        clamp_f32((py - r.y - bar * 0.5) / avail, 0.12, 0.88)
                    },
                };
                app.widgets[cap.index].split_ratio = ratio;
                app.mark_layout_dirty(win);
                return;
            },
            LineEdit => {
                let r = app.widgets[cap.index].rect;
                let vis_start = utf8_snap_boundary(app.str_view(app.widgets[cap.index].text), app.widgets[cap.index].text_scroll_byte);
                let rel_x = px - (r.x + 9.0);
                var pos: i32 = 0;
                if rel_x < 0.0 && vis_start > 0 {
                    pos = utf8_prev_char(app.str_view(app.widgets[cap.index].text), vis_start);
                } else {
                    pos = caret_byte_from_x_line_edit(app, win.index, cap, vis_start, rel_x);
                }
                if pos != app.widgets[cap.index].caret {
                    app.widgets[cap.index].caret = pos;
                    ensure_line_edit_caret_visible(app, cap);
                    app.mark_dirty(win);
                }
                return;
            },
            Canvas => {
                let r = app.widgets[cap.index].rect;
                app.push_signal(Signal.CanvasMouseMove { widget: cap, window: win, x: px - r.x, y: py - r.y });
                return;
            },
            _ => {},
        }
    }

    // 2. Open ComboBox dropdown hover
    let combo = app.windows[win.index].open_combo;
    if app.valid_widget(combo) {
        let pr = combo_popup_rect(app, combo);
        var new_hov: i32 = -1;
        if contains(pr, px, py) {
            let rel_y = py - (pr.y + 4.0);
            if rel_y >= 0.0 {
                let vis_row = (rel_y / 28.0) as! i32;
                let row = vis_row + app.windows[win.index].open_combo_scroll;
                let cnt = app.item_count(combo);
                if vis_row >= 0 && vis_row < 8 && row >= 0 && row < cnt { new_hov = row; }
            }
        }
        if new_hov != app.windows[win.index].open_combo_hover {
            app.windows[win.index].open_combo_hover = new_hov;
            app.mark_dirty(win);
        }
        return;
    }

    // 3. Normal hover tracking
    let hit = app.hit_test(win, px, py);
    let prev = app.windows[win.index].hovered;
    if !eq(hit, prev) {
        app.windows[win.index].hovered = hit;
        app.windows[win.index].hover_since_ms = win32::tick_count_ms();
        schedule_tooltip_timer(app, win, hit);
        app.mark_dirty(win);
    } else if app.windows[win.index].tooltip_visible {
        // Keep tooltip tracking cursor smoothly while visible.
        app.mark_dirty(win);
    }
    app.update_cursor(win, hit);

    if app.valid_widget(hit) {
        match app.widgets[hit.index].kind {
            ListView => {
                let r = app.widgets[hit.index].rect;
                let ih = app.widgets[hit.index].item_height;
                let rel_y = py - (r.y + 4.0) + app.widgets[hit.index].scroll_y;
                var nh: i32 = -1;
                if py >= r.y + 4.0 && py < r.y + r.h - 4.0 && rel_y >= 0.0 {
                    let idx = (rel_y / ih) as! i32;
                    let cnt = app.item_count(hit);
                    if idx >= 0 && idx < cnt { nh = idx; }
                }
                if nh != app.widgets[hit.index].hovered_item {
                    app.widgets[hit.index].hovered_item = nh;
                    app.mark_dirty(win);
                }
            },
            SpinBox, TabWidget => {
                app.mark_dirty(win);
            },
            Canvas => {
                let r = app.widgets[hit.index].rect;
                app.push_signal(Signal.CanvasMouseMove { widget: hit, window: win, x: px - r.x, y: py - r.y });
            },
            _ => {},
        }
    }
}

fn handle_mouse_down(app: App&, win: WindowId, px: f32, py: f32, button: i32) {
    guard app.valid_window(win) else { return; }
    app.update_layout(win);
    app.windows[win.index].mouse_x = px;
    app.windows[win.index].mouse_y = py;
    cancel_tooltip_timer(app, win);
    if button == MOUSE_LEFT {
        app.windows[win.index].mouse_down = true;
    }

    // 1. Check open ComboBox dropdown first
    let combo = app.windows[win.index].open_combo;
    if app.valid_widget(combo) {
        let pr = combo_popup_rect(app, combo);
        if button == MOUSE_LEFT && contains(pr, px, py) {
            let rel_y = py - (pr.y + 4.0);
            if rel_y >= 0.0 {
                let vis_row = (rel_y / 28.0) as! i32;
                let row = vis_row + app.windows[win.index].open_combo_scroll;
                let cnt = app.item_count(combo);
                if vis_row >= 0 && vis_row < 8 && row >= 0 && row < cnt {
                    let changed = app.widgets[combo.index].selected_index != row;
                    app.widgets[combo.index].selected_index = row;
                    app.windows[win.index].open_combo = WIDGET_NONE;
                    app.windows[win.index].open_combo_hover = -1;
                    app.windows[win.index].open_combo_scroll = 0;
                    app.mark_dirty(win);
                    if changed {
                        app.emit_selection_changed(combo, win, row);
                    }
                    return;
                }
            }
            return;
        }
        // Clicked outside popup: close it
        let clicked_same_combo = contains(app.widgets[combo.index].rect, px, py);
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.mark_dirty(win);
        if clicked_same_combo { return; }
    }

    let hit = app.hit_test(win, px, py);
    guard app.valid_widget(hit) else {
        app.set_focus(win, WIDGET_NONE);
        return;
    }

    if !app.widgets[hit.index].enabled { return; }

    // Update focus
    if app.widgets[hit.index].focusable {
        app.set_focus(win, hit);
    } else {
        app.set_focus(win, WIDGET_NONE);
    }

    // Compute clicked ListView row ahead of double-click detection so adjacent rows don't alias.
    var clicked_list_idx: i32 = -1;
    match app.widgets[hit.index].kind {
        ListView => {
            let r = app.widgets[hit.index].rect;
            let ih = app.widgets[hit.index].item_height;
            let rel_y = py - (r.y + 4.0) + app.widgets[hit.index].scroll_y;
            if py >= r.y + 4.0 && py < r.y + r.h - 4.0 && rel_y >= 0.0 {
                let idx = (rel_y / ih) as! i32;
                if idx >= 0 && idx < app.item_count(hit) {
                    clicked_list_idx = idx;
                }
            }
        },
        _ => {},
    }

    // Double-click detection (reset state after firing so triple-click doesn't re-trigger)
    let now = win32::tick_count_ms();
    var is_dbl = false;
    if button == MOUSE_LEFT && eq(app.windows[win.index].last_click_widget, hit) {
        let dt = now - app.windows[win.index].last_click_ms;
        let dx = px - app.windows[win.index].last_click_x;
        let dy = py - app.windows[win.index].last_click_y;
        let same_item = clicked_list_idx == app.windows[win.index].last_click_item;
        if dt <= 420 && dx * dx + dy * dy <= 36.0 && same_item {
            is_dbl = true;
        }
    }
    if button == MOUSE_LEFT {
        if is_dbl {
            app.windows[win.index].last_click_widget = WIDGET_NONE;
            app.windows[win.index].last_click_item = -1;
            app.push_signal(Signal.DoubleClicked { widget: hit, window: win });
        } else {
            app.windows[win.index].last_click_ms = now;
            app.windows[win.index].last_click_x = px;
            app.windows[win.index].last_click_y = py;
            app.windows[win.index].last_click_widget = hit;
            app.windows[win.index].last_click_item = clicked_list_idx;
        }
    }

    // Canvas receives all mouse buttons
    match app.widgets[hit.index].kind {
        Canvas => {
            let r = app.widgets[hit.index].rect;
            app.windows[win.index].captured = hit;
            if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
            app.push_signal(Signal.CanvasMouseDown { widget: hit, window: win, x: px - r.x, y: py - r.y, button: button });
            return;
        },
        _ => {},
    }

    if button != MOUSE_LEFT { return; }

    app.windows[win.index].pressed = hit;
    app.mark_dirty(win);

    match app.widgets[hit.index].kind {
        Button, CheckBox, RadioButton, ToggleSwitch => {
            app.windows[win.index].captured = hit;
            if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
        },
        Slider => {
            app.windows[win.index].captured = hit;
            if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
            slider_set_from_pos(app, hit, win, px, py);
        },
        Splitter => {
            app.windows[win.index].captured = hit;
            if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
        },
        LineEdit => {
            let r = app.widgets[hit.index].rect;
            if is_dbl {
                // Double-click selects all text
                app.widgets[hit.index].sel_anchor = 0;
                app.widgets[hit.index].caret = app.widgets[hit.index].text.len;
                ensure_line_edit_caret_visible(app, hit);
            } else {
                let vis_start = utf8_snap_boundary(app.str_view(app.widgets[hit.index].text), app.widgets[hit.index].text_scroll_byte);
                let pos = caret_byte_from_x_line_edit(app, win.index, hit, vis_start, px - (r.x + 9.0));
                app.widgets[hit.index].caret = pos;
                let mods = current_key_mods(app.windows[win.index].headless);
                if (mods & KMOD_SHIFT) == 0 {
                    app.widgets[hit.index].sel_anchor = pos;
                }
                ensure_line_edit_caret_visible(app, hit);
                app.windows[win.index].captured = hit;
                if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
            }
            app.mark_dirty(win);
        },
        SpinBox => {
            app.windows[win.index].captured = hit;
            if !app.windows[win.index].headless { app.windows[win.index].hwnd.set_capture(); }
            let r = app.widgets[hit.index].rect;
            let btn_w: f32 = 26.0;
            let minus_x = r.x + r.w - btn_w * 2.0;
            let plus_x = r.x + r.w - btn_w;
            var delta: f64 = 0.0;
            if px >= minus_x && px < plus_x {
                delta = -app.widgets[hit.index].step;
            } else if px >= plus_x && px < r.x + r.w {
                delta = app.widgets[hit.index].step;
            }
            if delta != 0.0 {
                let nv = clamp_f64(app.widgets[hit.index].value + delta, app.widgets[hit.index].min_value, app.widgets[hit.index].max_value);
                if nv != app.widgets[hit.index].value {
                    app.widgets[hit.index].value = nv;
                    app.emit_value_changed(hit, win, nv);
                }
            }
        },
        ComboBox => {
            if app.item_count(hit) > 0 {
                let sel = app.widgets[hit.index].selected_index;
                app.windows[win.index].open_combo = hit;
                app.windows[win.index].open_combo_hover = sel;
                app.windows[win.index].open_combo_scroll = 0;
                ensure_combo_item_visible(app, win, hit, sel);
                app.mark_dirty(win);
            }
        },
        ListView => {
            if clicked_list_idx >= 0 {
                let changed = app.widgets[hit.index].selected_index != clicked_list_idx;
                app.widgets[hit.index].selected_index = clicked_list_idx;
                app.mark_dirty(win);
                if changed {
                    app.emit_selection_changed(hit, win, clicked_list_idx);
                }
                if is_dbl {
                    app.push_signal(Signal.ItemActivated { widget: hit, window: win, index: clicked_list_idx });
                }
            }
        },
        TabWidget => {
            let cnt = app.item_count(hit);
            for idx: i32 in 0..cnt {
                let tr = tab_header_rect(app, hit, idx);
                if contains(tr, px, py) {
                    let prev = app.widgets[hit.index].selected_index;
                    if prev != idx {
                        app.widgets[hit.index].selected_index = idx;
                        clear_inactive_page_refs(app, hit, prev, idx);
                        app.mark_layout_dirty(win);
                        app.emit_tab_changed(hit, win, idx);
                    }
                    break;
                }
            }
        },
        _ => {},
    }
}

fn activate_button_like(app: App&, id: WidgetId, win: WindowId) {
    guard app.valid_widget(id) && app.widgets[id.index].enabled else { return; }
    match app.widgets[id.index].kind {
        Button => {
            if app.widgets[id.index].checkable {
                let nv = !app.widgets[id.index].checked;
                app.widgets[id.index].checked = nv;
                app.emit_toggled(id, win, nv);
            }
            app.emit_clicked(id, win);
        },
        CheckBox, ToggleSwitch => {
            let nv = !app.widgets[id.index].checked;
            app.widgets[id.index].checked = nv;
            app.emit_toggled(id, win, nv);
            app.emit_clicked(id, win);
        },
        RadioButton => {
            if !app.widgets[id.index].checked {
                // Uncheck and notify previously checked sibling radio buttons first.
                let p = app.widgets[id.index].parent;
                if app.valid_widget(p) {
                    var sib = app.widgets[p.index].first_child;
                    while app.valid_widget(sib) {
                        let next_sib = app.widgets[sib.index].next_sibling;
                        if !eq(sib, id) && app.widgets[sib.index].checked {
                            match app.widgets[sib.index].kind {
                                RadioButton => {
                                    app.widgets[sib.index].checked = false;
                                    app.emit_toggled(sib, win, false);
                                },
                                _ => {},
                            }
                        }
                        sib = next_sib;
                    }
                }
                app.widgets[id.index].checked = true;
                app.emit_toggled(id, win, true);
            }
            app.emit_clicked(id, win);
        },
        _ => {},
    }
    app.mark_dirty(win);
}

fn handle_mouse_up(app: App&, win: WindowId, px: f32, py: f32, button: i32) {
    guard app.valid_window(win) else { return; }
    app.windows[win.index].mouse_x = px;
    app.windows[win.index].mouse_y = py;

    var emitted_canvas_up = false;
    let cap = app.windows[win.index].captured;
    if app.valid_widget(cap) {
        let cap_is_canvas = match app.widgets[cap.index].kind { Canvas => true, _ => false };
        if cap_is_canvas {
            let r = app.widgets[cap.index].rect;
            app.push_signal(Signal.CanvasMouseUp { widget: cap, window: win, x: px - r.x, y: py - r.y, button: button });
            emitted_canvas_up = true;
        }
        if button == MOUSE_LEFT || cap_is_canvas {
            app.windows[win.index].captured = WIDGET_NONE;
            if !app.windows[win.index].headless { win32::release_capture(); }
        }
    }

    if !emitted_canvas_up && button != MOUSE_LEFT {
        let hit_c = app.hit_test(win, px, py);
        if app.valid_widget(hit_c) {
            match app.widgets[hit_c.index].kind {
                Canvas => {
                    let r = app.widgets[hit_c.index].rect;
                    app.push_signal(Signal.CanvasMouseUp { widget: hit_c, window: win, x: px - r.x, y: py - r.y, button: button });
                },
                _ => {},
            }
        }
    }

    if button != MOUSE_LEFT { return; }
    app.windows[win.index].mouse_down = false;

    let pressed = app.windows[win.index].pressed;
    app.windows[win.index].pressed = WIDGET_NONE;
    app.mark_dirty(win);

    guard app.valid_widget(pressed) else { return; }
    let hit = app.hit_test(win, px, py);
    if eq(hit, pressed) {
        activate_button_like(app, pressed, win);
    }
}

fn handle_mouse_wheel(app: App&, win: WindowId, px: f32, py: f32, delta: i32) {
    guard app.valid_window(win) else { return; }
    app.update_layout(win);

    // Scroll open ComboBox dropdown when it has > 8 items.
    let combo = app.windows[win.index].open_combo;
    if app.valid_widget(combo) {
        let pr = combo_popup_rect(app, combo);
        let cnt = app.item_count(combo);
        if contains(pr, px, py) && cnt > 8 {
            let max_sc = cnt - 8;
            let step: i32 = if delta > 0 { -1 } else { 1 };
            var ns = app.windows[win.index].open_combo_scroll + step;
            if ns < 0 { ns = 0; }
            if ns > max_sc { ns = max_sc; }
            if ns != app.windows[win.index].open_combo_scroll {
                app.windows[win.index].open_combo_scroll = ns;
                app.mark_dirty(win);
            }
            return;
        }
    }

    let hit = app.hit_test(win, px, py);
    guard app.valid_widget(hit) else { return; }

    match app.widgets[hit.index].kind {
        Canvas => {
            let r = app.widgets[hit.index].rect;
            app.push_signal(Signal.CanvasWheel { widget: hit, window: win, x: px - r.x, y: py - r.y, delta: delta });
            return;
        },
        Slider, SpinBox => {
            if app.widgets[hit.index].enabled {
                let dir = if delta > 0 { 1.0 } else { -1.0 };
                let nv = clamp_f64(
                    app.widgets[hit.index].value + dir * app.widgets[hit.index].step,
                    app.widgets[hit.index].min_value,
                    app.widgets[hit.index].max_value
                );
                if nv != app.widgets[hit.index].value {
                    app.widgets[hit.index].value = nv;
                    app.mark_dirty(win);
                    app.emit_value_changed(hit, win, nv);
                }
            }
            return;
        },
        _ => {},
    }

    var cur = find_scroll_ancestor(app, hit);
    while app.valid_widget(cur) {
        if app.widgets[cur.index].scroll_max_y > 0.0 {
            let step: f32 = if delta > 0 { -42.0 } else { 42.0 };
            let ny = clamp_f32(app.widgets[cur.index].scroll_y + step, 0.0, app.widgets[cur.index].scroll_max_y);
            if ny != app.widgets[cur.index].scroll_y {
                app.widgets[cur.index].scroll_y = ny;
                match app.widgets[cur.index].kind {
                    ScrollArea => { app.mark_layout_dirty(win); },
                    _ => { app.mark_dirty(win); },
                }
                return;
            }
        }
        cur = find_scroll_ancestor(app, app.widgets[cur.index].parent);
    }
}

fn handle_key_down(app: App&, win: WindowId, key: u32, mods: u32) {
    guard app.valid_window(win) else { return; }
    cancel_tooltip_timer(app, win);

    // Escape closes open ComboBox popup first.
    if key == win32::VK_ESCAPE && app.valid_widget(app.windows[win.index].open_combo) {
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.mark_dirty(win);
        return;
    }

    // Tab / Shift+Tab focus traversal
    if key == win32::VK_TAB {
        app.cycle_focus(win, (mods & KMOD_SHIFT) != 0);
        return;
    }

    let foc = app.windows[win.index].focused;
    app.push_signal(Signal.KeyPressed { window: win, widget: foc, key: key, mods: mods });
    guard app.valid_widget(foc) && app.widgets[foc.index].enabled else { return; }

    let shift = (mods & KMOD_SHIFT) != 0;
    let ctrl = (mods & KMOD_CTRL) != 0;

    match app.widgets[foc.index].kind {
        Button, CheckBox, RadioButton, ToggleSwitch => {
            if key == win32::VK_SPACE || key == win32::VK_RETURN {
                activate_button_like(app, foc, win);
            }
        },
        LineEdit => {
            let n = app.widgets[foc.index].text.len;
            if key == win32::VK_LEFT {
                let np = utf8_prev_char(app.str_view(app.widgets[foc.index].text), app.widgets[foc.index].caret);
                app.widgets[foc.index].caret = np;
                if !shift { app.widgets[foc.index].sel_anchor = np; }
                ensure_line_edit_caret_visible(app, foc);
                app.mark_dirty(win);
            } else if key == win32::VK_RIGHT {
                let np = utf8_next_char(app.str_view(app.widgets[foc.index].text), app.widgets[foc.index].caret);
                app.widgets[foc.index].caret = np;
                if !shift { app.widgets[foc.index].sel_anchor = np; }
                ensure_line_edit_caret_visible(app, foc);
                app.mark_dirty(win);
            } else if key == 0x24 { // VK_HOME
                app.widgets[foc.index].caret = 0;
                if !shift { app.widgets[foc.index].sel_anchor = 0; }
                ensure_line_edit_caret_visible(app, foc);
                app.mark_dirty(win);
            } else if key == 0x23 { // VK_END
                app.widgets[foc.index].caret = n;
                if !shift { app.widgets[foc.index].sel_anchor = n; }
                ensure_line_edit_caret_visible(app, foc);
                app.mark_dirty(win);
            } else if key == win32::VK_BACK {
                if !app.widgets[foc.index].read_only {
                    var changed = line_edit_delete_selection(app, foc);
                    if !changed && app.widgets[foc.index].caret > 0 {
                        let prev = utf8_prev_char(app.str_view(app.widgets[foc.index].text), app.widgets[foc.index].caret);
                        app.widgets[foc.index].sel_anchor = prev;
                        changed = line_edit_delete_selection(app, foc);
                    }
                    if changed {
                        app.mark_dirty(win);
                        app.emit_text_changed(foc, win);
                    }
                }
            } else if key == win32::VK_DELETE {
                if !app.widgets[foc.index].read_only {
                    var changed = line_edit_delete_selection(app, foc);
                    if !changed && app.widgets[foc.index].caret < n {
                        let next = utf8_next_char(app.str_view(app.widgets[foc.index].text), app.widgets[foc.index].caret);
                        app.widgets[foc.index].sel_anchor = next;
                        changed = line_edit_delete_selection(app, foc);
                    }
                    if changed {
                        app.mark_dirty(win);
                        app.emit_text_changed(foc, win);
                    }
                }
            } else if key == win32::VK_RETURN {
                app.emit_text_submitted(foc, win);
            } else if ctrl && key == 'A' {
                app.widgets[foc.index].sel_anchor = 0;
                app.widgets[foc.index].caret = n;
                ensure_line_edit_caret_visible(app, foc);
                app.mark_dirty(win);
            } else if ctrl && key == 'C' {
                if !app.widgets[foc.index].password_mode && !app.windows[win.index].headless {
                    var sel: u8[>..] = [];
                    if line_edit_selected_text(app, foc, sel) {
                        win32::clipboard_set_text(sel);
                    }
                }
            } else if ctrl && key == 'X' {
                if !app.widgets[foc.index].password_mode && !app.widgets[foc.index].read_only {
                    var sel: u8[>..] = [];
                    if line_edit_selected_text(app, foc, sel) {
                        if !app.windows[win.index].headless {
                            win32::clipboard_set_text(sel);
                        }
                        if line_edit_delete_selection(app, foc) {
                            app.mark_dirty(win);
                            app.emit_text_changed(foc, win);
                        }
                    }
                }
            } else if ctrl && key == 'V' {
                if !app.widgets[foc.index].read_only && !app.windows[win.index].headless {
                    let clip = win32::clipboard_get_text();
                    // Strip CR/LF for single-line input
                    var clean: u8[>..] = [];
                    for i in clip.len {
                        let b = clip[i];
                        if b != '\r' && b != '\n' { clean.push(b); }
                    }
                    if line_edit_insert_bytes(app, foc, clean) {
                        app.mark_dirty(win);
                        app.emit_text_changed(foc, win);
                    }
                }
            }
        },
        Slider, SpinBox => {
            var delta: f64 = 0.0;
            if key == win32::VK_RIGHT || key == win32::VK_UP { delta = app.widgets[foc.index].step; }
            else if key == win32::VK_LEFT || key == win32::VK_DOWN { delta = -app.widgets[foc.index].step; }
            if delta != 0.0 {
                let nv = clamp_f64(app.widgets[foc.index].value + delta, app.widgets[foc.index].min_value, app.widgets[foc.index].max_value);
                if nv != app.widgets[foc.index].value {
                    app.widgets[foc.index].value = nv;
                    app.mark_dirty(win);
                    app.emit_value_changed(foc, win, nv);
                }
            }
        },
        ListView, ComboBox => {
            let cnt = app.item_count(foc);
            if cnt > 0 {
                let is_lv = match app.widgets[foc.index].kind { ListView => true, _ => false };
                var cur = app.widgets[foc.index].selected_index;
                if key == win32::VK_DOWN {
                    let ni = if cur + 1 < cnt { cur + 1 } else { cnt - 1 };
                    if ni != cur {
                        app.widgets[foc.index].selected_index = ni;
                        if is_lv {
                            ensure_list_item_visible(app, foc, ni);
                        } else if eq(app.windows[win.index].open_combo, foc) {
                            app.windows[win.index].open_combo_hover = ni;
                            ensure_combo_item_visible(app, win, foc, ni);
                        }
                        app.mark_dirty(win);
                        app.emit_selection_changed(foc, win, ni);
                    }
                } else if key == win32::VK_UP {
                    let ni = if cur > 0 { cur - 1 } else { 0 };
                    if ni != cur {
                        app.widgets[foc.index].selected_index = ni;
                        if is_lv {
                            ensure_list_item_visible(app, foc, ni);
                        } else if eq(app.windows[win.index].open_combo, foc) {
                            app.windows[win.index].open_combo_hover = ni;
                            ensure_combo_item_visible(app, win, foc, ni);
                        }
                        app.mark_dirty(win);
                        app.emit_selection_changed(foc, win, ni);
                    }
                } else if key == win32::VK_RETURN || (!is_lv && key == win32::VK_SPACE) {
                    if is_lv {
                        if cur >= 0 {
                            app.push_signal(Signal.ItemActivated { widget: foc, window: win, index: cur });
                        }
                    } else {
                        if eq(app.windows[win.index].open_combo, foc) {
                            app.windows[win.index].open_combo = WIDGET_NONE;
                            app.windows[win.index].open_combo_hover = -1;
                            app.windows[win.index].open_combo_scroll = 0;
                        } else {
                            app.windows[win.index].open_combo = foc;
                            app.windows[win.index].open_combo_hover = cur;
                            app.windows[win.index].open_combo_scroll = 0;
                            ensure_combo_item_visible(app, win, foc, cur);
                        }
                        app.mark_dirty(win);
                    }
                }
            }
        },
        _ => {},
    }
}

fn handle_char(app: App&, win: WindowId, codepoint: u32) {
    guard app.valid_window(win) else { return; }
    let foc = app.windows[win.index].focused;
    guard app.valid_widget(foc) && app.widgets[foc.index].enabled else { return; }

    match app.widgets[foc.index].kind {
        LineEdit => {
            if app.widgets[foc.index].read_only { return; }
            // Ignore control characters (handled in WM_KEYDOWN).
            if codepoint < 0x20 || codepoint == 0x7F { return; }

            var full_cp: i64 = codepoint;
            // Handle UTF-16 surrogate pairs from Windows WM_CHAR.
            if codepoint >= 0xD800 && codepoint <= 0xDBFF {
                app.windows[win.index].pending_surrogate = codepoint;
                return;
            } else if codepoint >= 0xDC00 && codepoint <= 0xDFFF {
                let hi = app.windows[win.index].pending_surrogate;
                app.windows[win.index].pending_surrogate = 0;
                if hi >= 0xD800 && hi <= 0xDBFF {
                    full_cp = 0x10000 + (((hi - 0xD800) as i64) << 10) + (codepoint - 0xDC00);
                } else {
                    return;
                }
            } else {
                app.windows[win.index].pending_surrogate = 0;
            }

            var utf8_buf: u8[>..] = [];
            push_utf8(utf8_buf, full_cp);
            if line_edit_insert_bytes(app, foc, utf8_buf) {
                app.mark_dirty(win);
                app.emit_text_changed(foc, win);
            }
        },
        _ => {},
    }
}

// --- Win32 Event Dispatcher -------------------------------------------------

fn dispatch_win32_event(app: App&, ev: const win32::Event&) {
    if ev.msg == win32::WM_QUIT {
        app.running = false;
        return;
    }

    if ev.msg == win32::WM_DESTROY {
        if app.quit_on_last_window_closed && app.active_window_count() == 0 {
            win32::post_quit_message(0);
        }
        return;
    }

    let win = app.find_window_by_hwnd(ev.hwnd);
    guard app.valid_window(win) else { return; }

    if ev.msg == win32::WM_CLOSE {
        app.push_signal(Signal.WindowClosed { window: win });
        if app.windows[win.index].auto_close {
            app.close_window(win);
        }
    } else if ev.msg == win32::WM_SIZE {
        if ev.width > 0 && ev.height > 0 {
            app.windows[win.index].width = ev.width;
            app.windows[win.index].height = ev.height;
            if app.windows[win.index].d2d.is_valid() {
                app.windows[win.index].d2d.resize(ev.width, ev.height);
            } else if app.windows[win.index].gl2d.is_valid() {
                app.windows[win.index].gl2d.resize(ev.width, ev.height);
            }
            app.windows[win.index].open_combo = WIDGET_NONE;
            app.windows[win.index].open_combo_hover = -1;
            app.windows[win.index].open_combo_scroll = 0;
            cancel_tooltip_timer(app, win);
            app.windows[win.index].layout_dirty = true;
            app.windows[win.index].dirty = true;
            app.push_signal(Signal.WindowResized { window: win, width: ev.width, height: ev.height });
        }
    } else if ev.msg == win32::WM_PAINT {
        app.windows[win.index].dirty = true;
    } else if ev.msg == win32::WM_DPICHANGED {
        app.windows[win.index].dpi = ev.x as! u32;
        if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
            let rc = app.windows[win.index].hwnd.client_rect();
            let cw = rc.width();
            let ch = rc.height();
            if cw > 0 && ch > 0 {
                let size_changed = cw != app.windows[win.index].width || ch != app.windows[win.index].height;
                app.windows[win.index].width = cw;
                app.windows[win.index].height = ch;
                if app.windows[win.index].d2d.is_valid() {
                    app.windows[win.index].d2d.resize(cw, ch);
                } else if app.windows[win.index].gl2d.is_valid() {
                    app.windows[win.index].gl2d.resize(cw, ch);
                }
                if size_changed {
                    app.push_signal(Signal.WindowResized { window: win, width: cw, height: ch });
                }
            }
        }
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.windows[win.index].layout_dirty = true;
        app.windows[win.index].dirty = true;
    } else if ev.msg == win32::WM_MOUSEMOVE {
        handle_mouse_move(app, win, ev.x, ev.y);
    } else if ev.msg == win32::WM_LBUTTONDOWN {
        handle_mouse_down(app, win, ev.x, ev.y, MOUSE_LEFT);
    } else if ev.msg == win32::WM_LBUTTONUP {
        handle_mouse_up(app, win, ev.x, ev.y, MOUSE_LEFT);
    } else if ev.msg == win32::WM_RBUTTONDOWN {
        handle_mouse_down(app, win, ev.x, ev.y, MOUSE_RIGHT);
    } else if ev.msg == win32::WM_RBUTTONUP {
        handle_mouse_up(app, win, ev.x, ev.y, MOUSE_RIGHT);
    } else if ev.msg == win32::WM_MBUTTONDOWN {
        handle_mouse_down(app, win, ev.x, ev.y, MOUSE_MIDDLE);
    } else if ev.msg == win32::WM_MBUTTONUP {
        handle_mouse_up(app, win, ev.x, ev.y, MOUSE_MIDDLE);
    } else if ev.msg == win32::WM_MOUSEWHEEL {
        handle_mouse_wheel(app, win, ev.x, ev.y, ev.wheel_delta);
    } else if ev.msg == win32::WM_KEYDOWN {
        let mods = current_key_mods(false);
        handle_key_down(app, win, ev.key, mods);
    } else if ev.msg == win32::WM_CHAR {
        handle_char(app, win, ev.codepoint);
    } else if ev.msg == win32::WM_COMMAND {
        app.push_signal(Signal.ActionTriggered { window: win, action_id: ev.command_id });
    } else if ev.msg == win32::WM_TIMER {
        let tid = ev.wparam;
        if tid == INTERNAL_TOOLTIP_TIMER_ID {
            if app.windows[win.index].tooltip_timer_active {
                if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
                    app.windows[win.index].hwnd.kill_timer(INTERNAL_TOOLTIP_TIMER_ID);
                }
                app.windows[win.index].tooltip_timer_active = false;
            }
            let hov = app.windows[win.index].hovered;
            if app.valid_widget(hov) && !app.windows[win.index].mouse_down && !app.valid_widget(app.windows[win.index].open_combo) && app.widgets[hov.index].tooltip.len > 0 {
                app.windows[win.index].tooltip_visible = true;
                app.mark_dirty(win);
            }
            return;
        }
        for i in app.timers.len {
            if app.timers[i].alive && app.timers[i].timer_id == tid {
                if app.timers[i].single_shot {
                    app.windows[win.index].hwnd.kill_timer(tid);
                    app.timers[i].alive = false;
                }
                break;
            }
        }
        app.push_signal(Signal.TimerFired { window: win, timer_id: tid });
    } else if ev.msg == win32::WM_DROPFILES {
        app.push_signal(Signal.FilesDropped { window: win, count: ev.command_id as! i32 });
    } else if ev.msg == win32::WM_KILLFOCUS {
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.windows[win.index].pressed = WIDGET_NONE;
        app.windows[win.index].mouse_down = false;
        if app.valid_widget(app.windows[win.index].captured) {
            app.windows[win.index].captured = WIDGET_NONE;
            if !app.windows[win.index].headless { win32::release_capture(); }
        }
        cancel_tooltip_timer(app, win);
        app.mark_dirty(win);
    }
}

// --- Application Event Loop (QApplication::exec) ----------------------------

fn pump_events(app: App&, blocking: bool = true) -> bool {
    var ev = win32::Event {};
    if blocking {
        if !win32::wait_event(ev) {
            app.running = false;
            return false;
        }
        dispatch_win32_event(app, ev);
    }
    while app.running && win32::poll_event(ev) {
        dispatch_win32_event(app, ev);
    }
    return app.running;
}

// Blocking Qt-style event loop. Renders dirty windows, waits for OS events with
// 0% idle CPU, dispatches declarative connections, and delivers Signals to F.
fn exec<F>(app: App&) {
    app.running = app.active_window_count() > 0;
    app.render_all();

    while app.running {
        app.pump_events(true);
        var sig = Signal.None;
        while app.next_signal(sig) {
            F(sig);
        }
        if app.running {
            app.render_all();
        }
    }
    app.destroy_all();
}

// Same as `exec`, plus a custom Canvas painting function `OnPaint(widget_id, painter)`.
// Call as `app.exec_with_canvas(paint_canvas) { sig => ... };`.
fn exec_with_canvas<OnPaint, OnSignal>(app: App&) {
    app.running = app.active_window_count() > 0;
    app.render_all_with() { cid, p => OnPaint(cid, p); };

    while app.running {
        app.pump_events(true);
        var sig = Signal.None;
        while app.next_signal(sig) {
            OnSignal(sig);
        }
        if app.running {
            app.render_all_with() { cid, p => OnPaint(cid, p); };
        }
    }
    app.destroy_all();
}

// --- Synthetic Event Injection (for Headless Automated Tests) ---------------

fn inject_mouse_move(app: App&, win: WindowId, x: f32, y: f32) {
    handle_mouse_move(app, win, x, y);
}

fn inject_click(app: App&, win: WindowId, x: f32, y: f32) {
    handle_mouse_move(app, win, x, y);
    handle_mouse_down(app, win, x, y, MOUSE_LEFT);
    handle_mouse_up(app, win, x, y, MOUSE_LEFT);
}

fn inject_mouse_down(app: App&, win: WindowId, x: f32, y: f32, button: i32 = MOUSE_LEFT) {
    handle_mouse_down(app, win, x, y, button);
}

fn inject_mouse_up(app: App&, win: WindowId, x: f32, y: f32, button: i32 = MOUSE_LEFT) {
    handle_mouse_up(app, win, x, y, button);
}

fn inject_mouse_wheel(app: App&, win: WindowId, x: f32, y: f32, delta: i32) {
    handle_mouse_wheel(app, win, x, y, delta);
}

fn inject_key(app: App&, win: WindowId, key: u32, mods: u32 = 0) {
    handle_key_down(app, win, key, mods);
}

fn inject_char(app: App&, win: WindowId, codepoint: u32) {
    handle_char(app, win, codepoint);
}

fn inject_text(app: App&, win: WindowId, utf8: const u8[:]) {
    each_utf8(utf8) { cp =>
        handle_char(app, win, cp as! u32);
    };
}
