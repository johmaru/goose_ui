// Dual-backend QPainter-style renderer:
//   - RenderBackend.Direct2D: GPU-accelerated Direct2D + DirectWrite
//   - RenderBackend.Software: Ultra-light double-buffered GDI + ClearType (0 GPU RAM)
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import theme;
import widget;
import tree;
import layout;
import webview;

// Win32 GDI clipping & text flags not exposed in win32-goose's constants.
let DT_NOPREFIX: u32 = 0x00000800;

extern "gdi32" {
    fn SaveDC(hdc: u64) -> i32;
    fn IntersectClipRect(hdc: u64, left: i32, top: i32, right: i32, bottom: i32) -> i32;
    fn RestoreDC(hdc: u64, saved_dc: i32) -> i32;
}

// --- QPainter-style 2D Vector & Text Painter --------------------------------

struct Painter {
    backend: RenderBackend = RenderBackend.Direct2D,
    d2d: win32::D2dTarget = win32::D2dTarget {},
    fonts: FontSet = FontSet {},
    gl2d: win32::Gl2dTarget = win32::Gl2dTarget {},
    gl2d_fonts: Gl2dFontSet = Gl2dFontSet {},
    hdc: win32::Hdc = win32::Hdc {},
    gdi_fonts: GdiFontSet = GdiFontSet {},
    metric_dc: win32::Hdc = win32::Hdc {},
    metric_fonts: GdiFontSet = GdiFontSet {},
    ox: f32 = 0.0,
    oy: f32 = 0.0,
    theme: Theme = Theme {},
    width: f32 = 0.0,
    height: f32 = 0.0,
}

fn select_gdi_font(fonts: const GdiFontSet&, role: FontRole) -> win32::Hfont {
    return match role {
        Body => fonts.body,
        BodyBold => fonts.body_bold,
        Heading => fonts.heading,
        Subheading => fonts.subheading,
        Caption => fonts.caption,
        Mono => fonts.mono,
    };
}

fn align_to_d2d_h(a: Align) -> i32 {
    return match a {
        Start, Stretch => win32::D2D_ALIGN_LEADING,
        Center => win32::D2D_ALIGN_CENTER,
        End => win32::D2D_ALIGN_TRAILING,
    };
}

fn align_to_d2d_v(a: Align) -> i32 {
    return match a {
        Start => win32::D2D_VALIGN_NEAR,
        Center, Stretch => win32::D2D_VALIGN_CENTER,
        End => win32::D2D_VALIGN_FAR,
    };
}

fn select_gl2d_font(fonts: const Gl2dFontSet&, role: FontRole) -> win32::Gl2dFont {
    return match role {
        Body => fonts.body,
        BodyBold => fonts.body_bold,
        Heading => fonts.heading,
        Subheading => fonts.subheading,
        Caption => fonts.caption,
        Mono => fonts.mono,
    };
}

fn align_to_gl2d_h(a: Align) -> i32 {
    return match a {
        Start, Stretch => win32::GL2D_ALIGN_START,
        Center => win32::GL2D_ALIGN_CENTER,
        End => win32::GL2D_ALIGN_END,
    };
}

fn align_to_gl2d_v(a: Align) -> i32 {
    return match a {
        Start => win32::GL2D_ALIGN_START,
        Center, Stretch => win32::GL2D_ALIGN_CENTER,
        End => win32::GL2D_ALIGN_END,
    };
}

// Composite translucent colors onto the theme surface for GDI software rendering.
fn gdi_colorref(p: const Painter&, c: Color) -> u32 {
    if c.a >= 0.99 { return to_colorref(c); }
    let blended = lerp_color(p.theme.surface_bg, c, c.a);
    return to_colorref(blended);
}

fn round_i32(v: f32) -> i32 {
    return (if v >= 0.0 { v + 0.5 } else { v - 0.5 }) as! i32;
}

fn fill_rect(p: const Painter&, x: f32, y: f32, w: f32, h: f32, c: Color) {
    guard w > 0.0 && h > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.fill_rect(x, y, w, h, to_d2d(c)); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let rc = win32::Rect {
                left: round_i32(p.ox + x),
                top: round_i32(p.oy + y),
                right: round_i32(p.ox + x + w),
                bottom: round_i32(p.oy + y + h),
            };
            p.hdc.fill_rect(rc, gdi_colorref(p, c));
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.fill_rect(p.ox + x, p.oy + y, w, h, to_d2d(c)); }
        },
    }
}

fn draw_rect(p: const Painter&, x: f32, y: f32, w: f32, h: f32, c: Color, stroke: f32 = 1.0) {
    guard w > 0.0 && h > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.draw_rect(x, y, w, h, to_d2d(c), stroke); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let pw = if stroke >= 1.5 { round_i32(stroke) } else { 1 };
            let pen = win32::create_pen(win32::PS_SOLID, pw, gdi_colorref(p, c));
            guard pen.is_valid() else { return; }
            let old_p = p.hdc.select_pen(pen);
            let old_b = p.hdc.select_object(win32::stock_object(win32::NULL_BRUSH));
            p.hdc.rectangle(round_i32(p.ox + x), round_i32(p.oy + y), round_i32(p.ox + x + w), round_i32(p.oy + y + h));
            p.hdc.select_object(old_b);
            p.hdc.select_object(old_p);
            pen.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.draw_rect(p.ox + x, p.oy + y, w, h, to_d2d(c), stroke); }
        },
    }
}

fn fill_rounded_rect(p: const Painter&, x: f32, y: f32, w: f32, h: f32, r: f32, c: Color) {
    guard w > 0.0 && h > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.fill_rounded_rect(x, y, w, h, r, r, to_d2d(c)); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let col = gdi_colorref(p, c);
            let brush = win32::create_solid_brush(col);
            guard brush.is_valid() else { return; }
            let old_b = p.hdc.select_brush(brush);
            let old_p = p.hdc.select_object(win32::stock_object(win32::NULL_PEN));
            let d = round_i32(r * 2.0);
            p.hdc.round_rect(round_i32(p.ox + x), round_i32(p.oy + y), round_i32(p.ox + x + w) + 1, round_i32(p.oy + y + h) + 1, d, d);
            p.hdc.select_object(old_p);
            p.hdc.select_object(old_b);
            brush.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.fill_rounded_rect(p.ox + x, p.oy + y, w, h, r, to_d2d(c)); }
        },
    }
}

fn draw_rounded_rect(p: const Painter&, x: f32, y: f32, w: f32, h: f32, r: f32, c: Color, stroke: f32 = 1.0) {
    guard w > 0.0 && h > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.draw_rounded_rect(x, y, w, h, r, r, to_d2d(c), stroke); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let pw = if stroke >= 1.5 { round_i32(stroke) } else { 1 };
            let pen = win32::create_pen(win32::PS_SOLID, pw, gdi_colorref(p, c));
            guard pen.is_valid() else { return; }
            let old_p = p.hdc.select_pen(pen);
            let old_b = p.hdc.select_object(win32::stock_object(win32::NULL_BRUSH));
            let d = round_i32(r * 2.0);
            p.hdc.round_rect(round_i32(p.ox + x), round_i32(p.oy + y), round_i32(p.ox + x + w), round_i32(p.oy + y + h), d, d);
            p.hdc.select_object(old_b);
            p.hdc.select_object(old_p);
            pen.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.draw_rounded_rect(p.ox + x, p.oy + y, w, h, r, to_d2d(c), stroke); }
        },
    }
}

fn fill_ellipse(p: const Painter&, cx: f32, cy: f32, rx: f32, ry: f32, c: Color) {
    guard rx > 0.0 && ry > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.fill_ellipse(cx, cy, rx, ry, to_d2d(c)); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let brush = win32::create_solid_brush(gdi_colorref(p, c));
            guard brush.is_valid() else { return; }
            let old_b = p.hdc.select_brush(brush);
            let old_p = p.hdc.select_object(win32::stock_object(win32::NULL_PEN));
            p.hdc.ellipse(round_i32(p.ox + cx - rx), round_i32(p.oy + cy - ry), round_i32(p.ox + cx + rx) + 1, round_i32(p.oy + cy + ry) + 1);
            p.hdc.select_object(old_p);
            p.hdc.select_object(old_b);
            brush.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.fill_ellipse(p.ox + cx, p.oy + cy, rx, ry, to_d2d(c)); }
        },
    }
}

fn draw_ellipse(p: const Painter&, cx: f32, cy: f32, rx: f32, ry: f32, c: Color, stroke: f32 = 1.0) {
    guard rx > 0.0 && ry > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.draw_ellipse(cx, cy, rx, ry, to_d2d(c), stroke); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let pw = if stroke >= 1.5 { round_i32(stroke) } else { 1 };
            let pen = win32::create_pen(win32::PS_SOLID, pw, gdi_colorref(p, c));
            guard pen.is_valid() else { return; }
            let old_p = p.hdc.select_pen(pen);
            let old_b = p.hdc.select_object(win32::stock_object(win32::NULL_BRUSH));
            p.hdc.ellipse(round_i32(p.ox + cx - rx), round_i32(p.oy + cy - ry), round_i32(p.ox + cx + rx), round_i32(p.oy + cy + ry));
            p.hdc.select_object(old_b);
            p.hdc.select_object(old_p);
            pen.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.draw_ellipse(p.ox + cx, p.oy + cy, rx, ry, to_d2d(c), stroke); }
        },
    }
}

fn draw_line(p: const Painter&, x0: f32, y0: f32, x1: f32, y1: f32, c: Color, stroke: f32 = 1.0) {
    guard c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() { p.d2d.draw_line(x0, y0, x1, y1, to_d2d(c), stroke); }
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let pw = if stroke >= 1.5 { round_i32(stroke) } else { 1 };
            let pen = win32::create_pen(win32::PS_SOLID, pw, gdi_colorref(p, c));
            guard pen.is_valid() else { return; }
            let old_p = p.hdc.select_pen(pen);
            p.hdc.move_to(round_i32(p.ox + x0), round_i32(p.oy + y0));
            p.hdc.line_to(round_i32(p.ox + x1), round_i32(p.oy + y1));
            p.hdc.select_object(old_p);
            pen.delete();
        },
        OpenGL => {
            if p.gl2d.is_valid() { p.gl2d.draw_line(p.ox + x0, p.oy + y0, p.ox + x1, p.oy + y1, to_d2d(c), stroke); }
        },
    }
}

fn measure_painter_text_width(p: const Painter&, text: const u8[:], role: FontRole) -> f32 {
    if text.len == 0 { return 0.0; }
    match p.backend {
        Direct2D => {
            if p.d2d.is_valid() {
                let df = select_font(p.fonts, role);
                if df.is_valid() {
                    let w, _h = p.d2d.measure_text(text, df);
                    return w;
                }
            }
        },
        Software, OpenGL => {
            if p.metric_dc.is_valid() {
                let hf = select_metric_hfont(p.metric_fonts, role);
                if hf.is_valid() {
                    return measure_gdi_text_width(p.metric_dc, hf, text);
                }
            }
        },
    }
    return measure_text_width_role(text, p.theme, role);
}

fn fit_painter_text_bytes(p: const Painter&, text: const u8[:], max_w: f32, role: FontRole) -> i64 {
    if text.len == 0 || max_w <= 0.0 { return 0; }
    if measure_painter_text_width(p, text, role) <= max_w {
        return text.len;
    }
    var bounds: i64[>..] = [];
    bounds.push(0);
    var i: i64 = 0;
    while i < text.len {
        let b0 = text[i];
        var step: i64 = 1;
        if b0 >= 0xF0 && i + 3 < text.len { step = 4; }
        else if b0 >= 0xE0 && i + 2 < text.len { step = 3; }
        else if b0 >= 0xC0 && i + 1 < text.len { step = 2; }
        i += step;
        bounds.push(i);
    }
    var lo: i64 = 0;
    var hi: i64 = bounds.len - 1;
    while lo < hi {
        let mid = lo + (hi - lo + 1) / 2;
        if measure_painter_text_width(p, text[..bounds[mid]], role) <= max_w {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return bounds[lo];
}

fn draw_text(
    p: const Painter&,
    text: const u8[:],
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    c: Color,
    role: FontRole = FontRole.Body,
    h_align: Align = Align.Start,
    v_align: Align = Align.Center
) {
    guard text.len > 0 && w > 0.0 && h > 0.0 && c.a > 0.0 else { return; }
    match p.backend {
        Direct2D => {
            guard p.d2d.is_valid() else { return; }
            let f = select_font(p.fonts, role);
            guard f.is_valid() else { return; }
            f.set_align(align_to_d2d_h(h_align), align_to_d2d_v(v_align));
            p.d2d.draw_text(text, f, x, y, w, h, to_d2d(c));
        },
        Software => {
            guard p.hdc.is_valid() else { return; }
            let f = select_gdi_font(p.gdi_fonts, role);
            let old_f = if f.is_valid() { p.hdc.select_object(f.raw) } else { 0 };
            p.hdc.set_bk_mode(win32::TRANSPARENT);
            p.hdc.set_text_color(gdi_colorref(p, c));
            var fmt = win32::DT_SINGLELINE | DT_NOPREFIX;
            match h_align {
                Center => { fmt |= win32::DT_CENTER; },
                End => { fmt |= win32::DT_RIGHT; },
                _ => { fmt |= win32::DT_LEFT; },
            }
            match v_align {
                Start => { fmt |= win32::DT_TOP; },
                End => { fmt |= win32::DT_BOTTOM; },
                _ => { fmt |= win32::DT_VCENTER; },
            }
            var rc = win32::Rect {
                left: round_i32(p.ox + x),
                top: round_i32(p.oy + y),
                right: round_i32(p.ox + x + w),
                bottom: round_i32(p.oy + y + h),
            };
            p.hdc.draw_text(text, rc, fmt);
            if old_f != 0 { p.hdc.select_object(old_f); }
        },
        OpenGL => {
            guard p.gl2d.is_valid() else { return; }
            let f = select_gl2d_font(p.gl2d_fonts, role);
            guard f.is_valid() else { return; }
            p.gl2d.draw_text(text, f, p.ox + x, p.oy + y, w, h, align_to_gl2d_h(h_align), align_to_gl2d_v(v_align), to_d2d(c));
        },
    }
}

fn draw_text_wrapped(
    p: const Painter&,
    text: const u8[:],
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    c: Color,
    role: FontRole = FontRole.Body,
    h_align: Align = Align.Start,
    v_align: Align = Align.Start
) {
    guard text.len > 0 && w > 2.0 && h > 2.0 && c.a > 0.0 else { return; }
    let fsz = font_size_for_role(p.theme, role);
    let line_h = fsz * 1.38;
    var max_lines = (h / line_h) as! i32;
    if max_lines < 1 { max_lines = 1; }
    if max_lines > 64 { max_lines = 64; }

    let wrap_w = if w > 2.0 { w - 2.0 } else { w };
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    var total_h: f32 = 0.0;
    var pos: i64 = 0;

    while pos < text.len && starts.len < max_lines {
        var seg_end = pos;
        while seg_end < text.len && text[seg_end] != '\n' && text[seg_end] != '\r' {
            seg_end += 1;
        }
        if seg_end == pos {
            starts.push(pos);
            ends.push(pos);
            total_h += line_h;
            if pos < text.len && text[pos] == '\r' { pos += 1; }
            if pos < text.len && text[pos] == '\n' { pos += 1; }
            continue;
        }

        var fit = fit_painter_text_bytes(p, text[pos..seg_end], wrap_w, role);
        if fit <= 0 {
            let b0 = text[pos];
            var step: i64 = 1;
            if b0 >= 0xF0 && pos + 3 < seg_end { step = 4; }
            else if b0 >= 0xE0 && pos + 2 < seg_end { step = 3; }
            else if b0 >= 0xC0 && pos + 1 < seg_end { step = 2; }
            fit = step;
        }

        var line_end = pos + fit;
        var next_pos = line_end;
        if line_end < seg_end {
            let min_break = pos + fit / 2;
            var k = line_end - 1;
            while k >= min_break {
                let ch = text[k];
                if ch == ' ' {
                    line_end = k;
                    next_pos = k + 1;
                    break;
                }
                if ch == ',' || ch == '/' || ch == '\\' || ch == '-' || ch == ':' {
                    line_end = k + 1;
                    next_pos = k + 1;
                    break;
                }
                k -= 1;
            }
        } else {
            if next_pos < text.len && text[next_pos] == '\r' { next_pos += 1; }
            if next_pos < text.len && text[next_pos] == '\n' { next_pos += 1; }
        }

        starts.push(pos);
        ends.push(line_end);
        total_h += line_h;
        pos = next_pos;
    }

    if starts.len == 0 { return; }
    let truncated = pos < text.len;
    let rem_h = if h > total_h { h - total_h } else { 0.0 };
    var ly = match v_align {
        Start => y,
        End => y + rem_h,
        _ => y + rem_h * 0.5,
    };
    if ly < y { ly = y; }

    let ell_w = measure_painter_text_width(p, "...", role);
    for li in 0..starts.len {
        let s = starts[li];
        let e = ends[li];
        if truncated && li == starts.len - 1 {
            var ell: u8[>..] = [];
            let avail = if wrap_w > ell_w { wrap_w - ell_w } else { 0.0 };
            let keep = fit_painter_text_bytes(p, text[s..e], avail, role);
            if keep > 0 { ell.append(text[s..s + keep]); }
            ell.append("...");
            p.draw_text(ell, x, ly, w, line_h, c, role, h_align, Align.Center);
        } else if e > s {
            p.draw_text(text[s..e], x, ly, w, line_h, c, role, h_align, Align.Center);
        }
        ly += line_h;
    }
}

// --- Helper: Combo dropdown geometry (shared by painter & events) -----------

fn combo_popup_rect(app: const App&, combo_id: WidgetId) -> RectF {
    guard app.valid_widget(combo_id) else { return RectF {}; }
    let r = app.widgets[combo_id.index].rect;
    let cnt = app.item_count(combo_id);
    if cnt <= 0 { return RectF {}; }
    let vis = if cnt > 8 { 8 } else { cnt };
    let ih: f32 = 28.0;
    let h = vis * ih + 8.0;
    let win = app.widgets[combo_id.index].window;
    var py = r.y + r.h + 3.0;
    if app.valid_window(win) {
        let wh = app.windows[win.index].height as f32;
        if py + h > wh - 4.0 && r.y - h - 3.0 >= 4.0 {
            py = r.y - h - 3.0;
        }
    }
    return RectF { x: r.x, y: py, w: r.w, h: h };
}

// --- Helper: Tab header button geometry (shared by painter & events) --------

fn tab_header_rect(app: const App&, tab_id: WidgetId, tab_idx: i32) -> RectF {
    guard app.valid_widget(tab_id) else { return RectF {}; }
    let r = app.widgets[tab_id.index].rect;
    let tbh = app.widgets[tab_id.index].tab_bar_height;
    var cur_x = r.x + 6.0;
    var idx: i32 = 0;
    for i in app.list_items.len {
        if app.list_items[i].alive && eq(app.list_items[i].owner, tab_id) {
            let tw = measure_text_width_role(app.str_view(app.list_items[i].text), app.theme, FontRole.BodyBold);
            let w = if tw + 28.0 > 76.0 { tw + 28.0 } else { 76.0 };
            if idx == tab_idx {
                return RectF { x: cur_x, y: r.y + 4.0, w: w, h: tbh - 4.0 };
            }
            cur_x += w + 4.0;
            idx += 1;
        }
    }
    return RectF {};
}

// --- Helper: Format numeric value for SpinBox -------------------------------

fn format_spin_value(out: u8[>..]&, val: f64, decimals: i32) {
    if decimals <= 0 {
        let iv = (if val >= 0.0 { val + 0.5 } else { val - 0.5 }) as! i64;
        format(out, iv);
    } else {
        format_flt(out, val, decimals);
    }
}

// --- Widget Tree Renderer ---------------------------------------------------

fn paint_focus_ring(p: const Painter&, r: RectF, rad: f32) {
    p.draw_rounded_rect(r.x - 1.5, r.y - 1.5, r.w + 3.0, r.h + 3.0, rad + 1.5, p.theme.border_focus, 1.5);
}

fn paint_single_widget(app: const App&, win_idx: i32, id: WidgetId, p: const Painter&, clip: RectF) {
    let w = app.widgets[id.index];
    let r = w.rect;
    guard r.w > 0.0 && r.h > 0.0 else { return; }

    let t = app.theme;
    let is_hovered = eq(app.windows[win_idx].hovered, id);
    let is_pressed = eq(app.windows[win_idx].pressed, id);
    let is_focused = eq(app.windows[win_idx].focused, id);
    let rad = if has_radius(w.style) { w.style.radius } else { t.radius };
    let wtext = app.str_view(w.text);

    match w.kind {
        Panel => {
            let pr = if has_radius(w.style) { w.style.radius } else { 0.0 };
            if has_bg(w.style) {
                p.fill_rounded_rect(r.x, r.y, r.w, r.h, pr, unpack_rgba(w.style.bg_rgba));
            }
            if has_border(w.style) {
                p.draw_rounded_rect(r.x, r.y, r.w, r.h, pr, unpack_rgba(w.style.border_rgba), w.style.border_width);
            }
        },
        Frame => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.surface_bg };
            let bd = if has_border(w.style) { unpack_rgba(w.style.border_rgba) } else { t.border_subtle };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, w.style.border_width);
        },
        GroupBox => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.surface_bg };
            let bd = if has_border(w.style) { unpack_rgba(w.style.border_rgba) } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);
            if wtext.len > 0 {
                let title_col = if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_secondary };
                p.draw_text(wtext, r.x + 12.0, r.y + 6.0, r.w - 24.0, 20.0, title_col, FontRole.BodyBold, Align.Start, Align.Center);
                p.draw_line(r.x + 10.0, r.y + 28.0, r.x + r.w - 10.0, r.y + 28.0, t.border_subtle, 1.0);
            }
        },
        Spacer => {},
        Separator => {
            let col = if has_border(w.style) { unpack_rgba(w.style.border_rgba) } else { t.border_subtle };
            match w.orientation {
                Horizontal => {
                    let my = r.y + r.h * 0.5;
                    p.draw_line(r.x, my, r.x + r.w, my, col, 1.0);
                },
                Vertical => {
                    let mx = r.x + r.w * 0.5;
                    p.draw_line(mx, r.y, mx, r.y + r.h, col, 1.0);
                },
            }
        },
        Label => {
            if has_bg(w.style) {
                p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, unpack_rgba(w.style.bg_rgba));
            }
            let fg = if !w.enabled {
                t.text_disabled
            } else if has_fg(w.style) {
                unpack_rgba(w.style.fg_rgba)
            } else {
                t.text_primary
            };
            if w.word_wrap {
                p.draw_text_wrapped(wtext, r.x, r.y, r.w, r.h, fg, w.font_role, w.text_align_h, w.text_align_v);
            } else {
                p.draw_text(wtext, r.x, r.y, r.w, r.h, fg, w.font_role, w.text_align_h, w.text_align_v);
            }
        },
        Button => {
            var bg = t.surface_elevated;
            var fg = t.text_primary;
            var bd = t.border;
            var draw_bd = true;

            match w.variant {
                Primary => {
                    bg = if !w.enabled {
                        t.surface_elevated
                    } else if is_pressed || (w.checkable && w.checked) {
                        t.accent_active
                    } else if is_hovered {
                        t.accent_hover
                    } else {
                        t.accent
                    };
                    fg = if w.enabled { t.accent_text } else { t.text_disabled };
                    draw_bd = false;
                },
                Danger => {
                    bg = if !w.enabled {
                        t.surface_elevated
                    } else if is_pressed {
                        t.danger_active
                    } else if is_hovered {
                        t.danger_hover
                    } else {
                        t.danger
                    };
                    fg = if w.enabled { t.accent_text } else { t.text_disabled };
                    draw_bd = false;
                },
                Ghost => {
                    bg = if !w.enabled {
                        COLOR_TRANSPARENT
                    } else if is_pressed || (w.checkable && w.checked) {
                        t.surface_active
                    } else if is_hovered {
                        t.surface_hover
                    } else {
                        COLOR_TRANSPARENT
                    };
                    fg = if w.enabled { t.text_primary } else { t.text_disabled };
                    draw_bd = false;
                },
                Secondary => {
                    bg = if !w.enabled {
                        t.input_bg_disabled
                    } else if is_pressed || (w.checkable && w.checked) {
                        t.surface_active
                    } else if is_hovered {
                        t.surface_hover
                    } else {
                        t.surface_bg
                    };
                    fg = if w.enabled { t.text_secondary } else { t.text_disabled };
                },
                Default => {
                    bg = if !w.enabled {
                        t.input_bg_disabled
                    } else if is_pressed {
                        t.surface_active
                    } else if w.checkable && w.checked {
                        t.accent
                    } else if is_hovered {
                        t.surface_hover
                    } else {
                        t.surface_elevated
                    };
                    fg = if !w.enabled {
                        t.text_disabled
                    } else if w.checkable && w.checked {
                        t.accent_text
                    } else {
                        t.text_primary
                    };
                },
            }

            if has_bg(w.style) { bg = unpack_rgba(w.style.bg_rgba); }
            if has_fg(w.style) { fg = unpack_rgba(w.style.fg_rgba); }
            if has_border(w.style) { bd = unpack_rgba(w.style.border_rgba); draw_bd = true; }

            if bg.a > 0.0 {
                p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            }
            if draw_bd {
                p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);
            }
            if is_focused && w.enabled {
                paint_focus_ring(p, r, rad);
            }
            p.draw_text(wtext, r.x + 8.0, r.y, r.w - 16.0, r.h, fg, FontRole.BodyBold, w.text_align_h, Align.Center);
        },
        CheckBox => {
            let box_sz: f32 = 18.0;
            let bx = r.x + 2.0;
            let by = r.y + (r.h - box_sz) * 0.5;
            let fill = if !w.enabled {
                t.input_bg_disabled
            } else if w.checked {
                if is_hovered { t.accent_hover } else { t.accent }
            } else {
                if is_hovered { t.surface_hover } else { t.input_bg }
            };
            let bd = if w.checked && w.enabled {
                t.accent
            } else if is_focused {
                t.border_focus
            } else {
                t.border
            };
            p.fill_rounded_rect(bx, by, box_sz, box_sz, t.radius_sm, fill);
            p.draw_rounded_rect(bx + 0.5, by + 0.5, box_sz - 1.0, box_sz - 1.0, t.radius_sm, bd, 1.2);
            if w.checked {
                let ck = if w.enabled { t.accent_text } else { t.text_disabled };
                p.draw_line(bx + 4.0, by + 9.2, bx + 7.6, by + 13.0, ck, 2.0);
                p.draw_line(bx + 7.6, by + 13.0, bx + 14.2, by + 5.2, ck, 2.0);
            }
            let fg = if !w.enabled { t.text_disabled } else if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_primary };
            p.draw_text(wtext, bx + box_sz + 8.0, r.y, r.w - box_sz - 10.0, r.h, fg, w.font_role, Align.Start, Align.Center);
        },
        RadioButton => {
            let rad_r: f32 = 9.0;
            let cx = r.x + rad_r + 2.0;
            let cy = r.y + r.h * 0.5;
            let bg = if !w.enabled { t.input_bg_disabled } else if is_hovered { t.surface_hover } else { t.input_bg };
            let bd = if w.checked && w.enabled { t.accent } else if is_focused { t.border_focus } else { t.border };
            p.fill_ellipse(cx, cy, rad_r, rad_r, bg);
            p.draw_ellipse(cx, cy, rad_r, rad_r, bd, 1.5);
            if w.checked {
                let dot = if w.enabled { t.accent } else { t.text_disabled };
                p.fill_ellipse(cx, cy, 4.5, 4.5, dot);
            }
            let fg = if !w.enabled { t.text_disabled } else if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_primary };
            p.draw_text(wtext, r.x + 26.0, r.y, r.w - 26.0, r.h, fg, w.font_role, Align.Start, Align.Center);
        },
        ToggleSwitch => {
            let tw: f32 = 38.0;
            let th: f32 = 20.0;
            let tx = r.x + 2.0;
            let ty = r.y + (r.h - th) * 0.5;
            let track = if !w.enabled {
                t.input_bg_disabled
            } else if w.checked {
                if is_hovered { t.accent_hover } else { t.accent }
            } else {
                if is_hovered { t.surface_active } else { t.surface_elevated }
            };
            p.fill_rounded_rect(tx, ty, tw, th, th * 0.5, track);
            if !w.checked {
                p.draw_rounded_rect(tx + 0.5, ty + 0.5, tw - 1.0, th - 1.0, th * 0.5, if is_focused { t.border_focus } else { t.border }, 1.0);
            }
            let kx = if w.checked { tx + tw - 10.0 } else { tx + 10.0 };
            let ky = ty + th * 0.5;
            let knob_col = if w.checked { t.accent_text } else if w.enabled { t.text_secondary } else { t.text_disabled };
            p.fill_ellipse(kx, ky, 7.0, 7.0, knob_col);

            let fg = if !w.enabled { t.text_disabled } else if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_primary };
            p.draw_text(wtext, tx + tw + 10.0, r.y, r.w - tw - 12.0, r.h, fg, w.font_role, Align.Start, Align.Center);
        },
        LineEdit => {
            let bg = if !w.enabled { t.input_bg_disabled } else if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.input_bg };
            let bd = if is_focused && w.enabled { t.border_focus } else if is_hovered && w.enabled { t.text_muted } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, if is_focused { 1.6 } else { 1.0 });

            let pad_x: f32 = 9.0;
            let inner_x = r.x + pad_x;
            let inner_w = if r.w > pad_x * 2.0 { r.w - pad_x * 2.0 } else { 0.0 };
            let wph = app.str_view(w.placeholder);
            let vis_start = utf8_snap_boundary(wtext, w.text_scroll_byte);

            if wtext.len == 0 && wph.len > 0 {
                p.draw_text(wph, inner_x, r.y, inner_w, r.h, t.text_muted, w.font_role, Align.Start, Align.Center);
            } else if wtext.len > 0 && inner_w > 0.0 {
                let vis_end = fit_line_edit_end(app, win_idx, wtext, vis_start, inner_w, w.font_role, w.password_mode);
                var display: u8[>..] = [];
                if vis_end > vis_start {
                    if w.password_mode {
                        var i: i64 = vis_start;
                        while i < vis_end {
                            if (wtext[i] & 0xC0) != 0x80 { display.push('*'); }
                            i += 1;
                        }
                    } else {
                        display.append(wtext[vis_start..vis_end]);
                    }
                }

                if is_focused && w.caret != w.sel_anchor {
                    let s0 = if w.caret < w.sel_anchor { w.caret } else { w.sel_anchor };
                    let s1 = if w.caret > w.sel_anchor { w.caret } else { w.sel_anchor };
                    let ds0 = if s0 > vis_start { s0 } else { vis_start };
                    let ds1 = if s1 < vis_end { s1 } else { vis_end };
                    if ds1 > ds0 {
                        let x0 = inner_x + line_edit_slice_width(app, win_idx, wtext, vis_start, ds0, w.font_role, w.password_mode);
                        let x1 = inner_x + line_edit_slice_width(app, win_idx, wtext, vis_start, ds1, w.font_role, w.password_mode);
                        let sx = clamp_f32(x0, inner_x, inner_x + inner_w);
                        let ex = clamp_f32(x1, inner_x, inner_x + inner_w);
                        if ex > sx {
                            p.fill_rounded_rect(sx, r.y + 5.0, ex - sx, r.h - 10.0, 2.0, t.selection_bg);
                        }
                    }
                }

                if display.len > 0 {
                    let fg = if !w.enabled { t.text_disabled } else if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_primary };
                    p.draw_text(display, inner_x, r.y, inner_w, r.h, fg, w.font_role, Align.Start, Align.Center);
                }
            }

            if is_focused && w.enabled && !w.read_only && w.caret >= vis_start {
                let cx_off = line_edit_slice_width(app, win_idx, wtext, vis_start, w.caret, w.font_role, w.password_mode);
                let cx = clamp_f32(inner_x + cx_off, inner_x, inner_x + inner_w);
                p.draw_line(cx, r.y + 6.0, cx, r.y + r.h - 6.0, t.border_focus, 1.6);
            }
        },
        Slider => {
            let span = w.max_value - w.min_value;
            let frac = if span > 0.0 { clamp_f32(((w.value - w.min_value) / span) as f32, 0.0, 1.0) } else { 0.0 };
            let thumb_r: f32 = 8.0;
            let track_col = if w.enabled { t.surface_elevated } else { t.input_bg_disabled };
            let fill_col = if !w.enabled { t.text_disabled } else if is_hovered || is_pressed { t.accent_hover } else { t.accent };

            match w.orientation {
                Horizontal => {
                    let cy = r.y + r.h * 0.5;
                    let x0 = r.x + thumb_r;
                    let tw = if r.w > thumb_r * 2.0 { r.w - thumb_r * 2.0 } else { 1.0 };
                    p.fill_rounded_rect(x0, cy - 3.0, tw, 6.0, 3.0, track_col);
                    p.fill_rounded_rect(x0, cy - 3.0, tw * frac, 6.0, 3.0, fill_col);
                    let kx = x0 + tw * frac;
                    if is_hovered || is_pressed || is_focused {
                        p.fill_ellipse(kx, cy, thumb_r + 3.5, thumb_r + 3.5, with_alpha(t.accent, 0.22));
                    }
                    p.fill_ellipse(kx, cy, thumb_r, thumb_r, if w.enabled { t.accent_text } else { t.surface_hover });
                    p.draw_ellipse(kx, cy, thumb_r, thumb_r, fill_col, 2.0);
                },
                Vertical => {
                    let cx = r.x + r.w * 0.5;
                    let y0 = r.y + thumb_r;
                    let th = if r.h > thumb_r * 2.0 { r.h - thumb_r * 2.0 } else { 1.0 };
                    p.fill_rounded_rect(cx - 3.0, y0, 6.0, th, 3.0, track_col);
                    let filled_h = th * frac;
                    p.fill_rounded_rect(cx - 3.0, y0 + th - filled_h, 6.0, filled_h, 3.0, fill_col);
                    let ky = y0 + th - filled_h;
                    if is_hovered || is_pressed || is_focused {
                        p.fill_ellipse(cx, ky, thumb_r + 3.5, thumb_r + 3.5, with_alpha(t.accent, 0.22));
                    }
                    p.fill_ellipse(cx, ky, thumb_r, thumb_r, if w.enabled { t.accent_text } else { t.surface_hover });
                    p.draw_ellipse(cx, ky, thumb_r, thumb_r, fill_col, 2.0);
                },
            }
        },
        SpinBox => {
            let bg = if !w.enabled { t.input_bg_disabled } else { t.input_bg };
            let bd = if is_focused && w.enabled { t.border_focus } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);

            let btn_w: f32 = 26.0;
            let minus_x = r.x + r.w - btn_w * 2.0;
            let plus_x = r.x + r.w - btn_w;

            let mx = app.windows[win_idx].mouse_x;
            let my = app.windows[win_idx].mouse_y;
            let hover_minus = is_hovered && mx >= minus_x && mx < plus_x && my >= r.y && my < r.y + r.h;
            let hover_plus = is_hovered && mx >= plus_x && mx < r.x + r.w && my >= r.y && my < r.y + r.h;
            let plus_rad = if rad > 1.0 { rad - 1.0 } else { 0.0 };
            p.fill_rect(minus_x, r.y + 1.0, btn_w, r.h - 2.0, if hover_minus && w.enabled { t.surface_hover } else { t.surface_elevated });
            p.fill_rounded_rect(plus_x, r.y + 1.0, btn_w - 1.0, r.h - 2.0, plus_rad, if hover_plus && w.enabled { t.surface_hover } else { t.surface_elevated });
            p.draw_line(minus_x, r.y + 1.0, minus_x, r.y + r.h - 1.0, t.border_subtle, 1.0);
            p.draw_line(plus_x, r.y + 1.0, plus_x, r.y + r.h - 1.0, t.border_subtle, 1.0);

            let fg = if w.enabled { t.text_primary } else { t.text_disabled };
            p.draw_text("-", minus_x, r.y, btn_w, r.h, fg, FontRole.BodyBold, Align.Center, Align.Center);
            p.draw_text("+", plus_x, r.y, btn_w, r.h, fg, FontRole.BodyBold, Align.Center, Align.Center);

            var num_buf: u8[>..] = [];
            format_spin_value(num_buf, w.value, w.decimals);
            let val_w = if r.w > btn_w * 2.0 + 12.0 { r.w - btn_w * 2.0 - 12.0 } else { 0.0 };
            p.draw_text(num_buf, r.x + 8.0, r.y, val_w, r.h, fg, FontRole.Mono, Align.Start, Align.Center);
        },
        ProgressBar => {
            let span = w.max_value - w.min_value;
            let frac = if span > 0.0 { clamp_f32(((w.value - w.min_value) / span) as f32, 0.0, 1.0) } else { 0.0 };
            let pr = if r.h * 0.5 < rad { r.h * 0.5 } else { rad };
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.surface_elevated };
            let fill = if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.accent };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, pr, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, pr, t.border_subtle, 1.0);
            let fw = r.w * frac;
            if fw > 2.0 {
                let fpr = if fw * 0.5 < pr { fw * 0.5 } else { pr };
                p.fill_rounded_rect(r.x, r.y, fw, r.h, fpr, fill);
            }
            if w.show_percentage {
                let pct = (frac * 100.0 + 0.5) as! i32;
                var txt: u8[>..] = [];
                format(txt, pct, "%");
                p.draw_text(txt, r.x, r.y, r.w, r.h, if frac > 0.52 { t.accent_text } else { t.text_primary }, FontRole.Caption, Align.Center, Align.Center);
            }
        },
        ComboBox => {
            let is_open = eq(app.windows[win_idx].open_combo, id);
            let bg = if !w.enabled {
                t.input_bg_disabled
            } else if is_open || is_hovered {
                t.surface_hover
            } else {
                t.surface_elevated
            };
            let bd = if is_open || is_focused { t.border_focus } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, if is_open || is_focused { 1.4 } else { 1.0 });

            let fg = if w.enabled { t.text_primary } else { t.text_disabled };
            let wph = app.str_view(w.placeholder);
            if w.selected_index >= 0 {
                let txt = app.item_text(id, w.selected_index);
                p.draw_text(txt, r.x + 10.0, r.y, r.w - 34.0, r.h, fg, w.font_role, Align.Start, Align.Center);
            } else if wph.len > 0 {
                p.draw_text(wph, r.x + 10.0, r.y, r.w - 34.0, r.h, t.text_muted, w.font_role, Align.Start, Align.Center);
            }

            let ax = r.x + r.w - 16.0;
            let ay = r.y + r.h * 0.5;
            let ac = if w.enabled { t.text_secondary } else { t.text_disabled };
            if is_open {
                p.draw_line(ax - 4.0, ay + 2.0, ax, ay - 2.5, ac, 1.6);
                p.draw_line(ax, ay - 2.5, ax + 4.0, ay + 2.0, ac, 1.6);
            } else {
                p.draw_line(ax - 4.0, ay - 2.0, ax, ay + 2.5, ac, 1.6);
                p.draw_line(ax, ay + 2.5, ax + 4.0, ay - 2.0, ac, 1.6);
            }
        },
        ListView => {
            let vis = intersect(r, clip);
            guard vis.w > 0.0 && vis.h > 0.0 else { return; }
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.input_bg };
            let bd = if is_focused { t.border_focus } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);

            let ih = w.item_height;
            let sb_w: f32 = if w.scroll_max_y > 0.0 { 10.0 } else { 0.0 };
            let row_w = if r.w > 8.0 + sb_w { r.w - 8.0 - sb_w } else { 0.0 };
            let top_y = r.y + 4.0;
            let bot_y = r.y + r.h - 4.0;
            let cw = if r.w > 4.0 { r.w - 4.0 } else { 0.0 };
            let ch_clip = if bot_y > top_y { bot_y - top_y } else { 0.0 };

            var saved_dc: i32 = 0;
            match p.backend {
                Direct2D => {
                    if p.d2d.is_valid() { p.d2d.push_clip(r.x + 2.0, top_y, cw, ch_clip); }
                },
                Software => {
                    if p.hdc.is_valid() {
                        saved_dc = SaveDC(p.hdc.raw);
                        IntersectClipRect(
                            p.hdc.raw,
                            round_i32(p.ox + r.x + 2.0),
                            round_i32(p.oy + top_y),
                            round_i32(p.ox + r.x + r.w - 2.0),
                            round_i32(p.oy + bot_y)
                        );
                    }
                },
                OpenGL => {
                    if p.gl2d.is_valid() { p.gl2d.push_clip(p.ox + r.x + 2.0, p.oy + top_y, cw, ch_clip); }
                },
            }

            var idx: i32 = 0;
            for i in app.list_items.len {
                if app.list_items[i].alive && eq(app.list_items[i].owner, id) {
                    let iy = top_y + idx * ih - w.scroll_y;
                    if iy + ih > top_y && iy < bot_y {
                        let sel = idx == w.selected_index;
                        let hov = is_hovered && idx == w.hovered_item;
                        if sel {
                            p.fill_rounded_rect(r.x + 4.0, iy + 1.0, row_w, ih - 2.0, t.radius_sm, t.accent);
                        } else if hov {
                            p.fill_rounded_rect(r.x + 4.0, iy + 1.0, row_w, ih - 2.0, t.radius_sm, t.surface_hover);
                        }
                        let fg = if sel { t.accent_text } else { t.text_primary };
                        let sub_fg = if sel { with_alpha(t.accent_text, 0.85) } else { t.text_muted };
                        let itxt = app.str_view(app.list_items[i].text);
                        let isub = app.str_view(app.list_items[i].subtext);
                        let has_sub = isub.len > 0;
                        let text_w = if has_sub { row_w * 0.65 } else { row_w - 16.0 };
                        p.draw_text(itxt, r.x + 12.0, iy, text_w, ih, fg, w.font_role, Align.Start, Align.Center);
                        if has_sub {
                            p.draw_text(isub, r.x + 12.0 + text_w, iy, row_w - text_w - 20.0, ih, sub_fg, FontRole.Caption, Align.End, Align.Center);
                        }
                    }
                    idx += 1;
                }
            }

            match p.backend {
                Direct2D => { if p.d2d.is_valid() { p.d2d.pop_clip(); } },
                Software => { if saved_dc != 0 { RestoreDC(p.hdc.raw, saved_dc); } },
                OpenGL => { if p.gl2d.is_valid() { p.gl2d.pop_clip(); } },
            }

            if w.scroll_max_y > 0.0 {
                let track_h = r.h - 8.0;
                let total_h = track_h + w.scroll_max_y;
                let thumb_h = clamp_f32(track_h * (track_h / total_h), 24.0, track_h);
                let thumb_y = r.y + 4.0 + (track_h - thumb_h) * (w.scroll_y / w.scroll_max_y);
                p.fill_rounded_rect(r.x + r.w - 8.0, thumb_y, 5.0, thumb_h, 2.5, t.border);
            }
        },
        TabWidget => {
            let tbh = w.tab_bar_height;
            p.fill_rounded_rect(r.x, r.y + tbh - 2.0, r.w, r.h - tbh + 2.0, rad, t.surface_bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + tbh - 1.5, r.w - 1.0, r.h - tbh + 1.0, rad, t.border, 1.0);

            let mx = app.windows[win_idx].mouse_x;
            let my = app.windows[win_idx].mouse_y;
            var idx: i32 = 0;
            for i in app.list_items.len {
                if app.list_items[i].alive && eq(app.list_items[i].owner, id) {
                    let tr = tab_header_rect(app, id, idx);
                    let active = idx == w.selected_index;
                    let hov = contains(tr, mx, my);
                    if active {
                        p.fill_rounded_rect(tr.x, tr.y, tr.w, tr.h + 2.0, t.radius_sm, t.surface_bg);
                        p.draw_rounded_rect(tr.x + 0.5, tr.y + 0.5, tr.w - 1.0, tr.h, t.radius_sm, t.border, 1.0);
                        p.fill_rect(tr.x + 1.0, tr.y + tr.h - 2.0, tr.w - 2.0, 4.0, t.surface_bg);
                        p.fill_rounded_rect(tr.x + 8.0, tr.y + tr.h - 3.0, tr.w - 16.0, 2.5, 1.2, t.accent);
                    } else if hov {
                        p.fill_rounded_rect(tr.x, tr.y + 2.0, tr.w, tr.h - 4.0, t.radius_sm, t.surface_hover);
                    }
                    let fg = if active { t.text_primary } else if hov { t.text_secondary } else { t.text_muted };
                    p.draw_text(app.str_view(app.list_items[i].text), tr.x, tr.y, tr.w, tr.h - 2.0, fg, if active { FontRole.BodyBold } else { FontRole.Body }, Align.Center, Align.Center);
                    idx += 1;
                }
            }
        },
        ScrollArea => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.surface_bg };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, t.border_subtle, 1.0);
        },
        Splitter => {
            let bar = w.splitter_size;
            let col = if is_hovered || is_pressed { t.accent } else { t.border };
            match w.orientation {
                Horizontal => {
                    let avail = if r.w > bar { r.w - bar } else { 0.0 };
                    let hx = r.x + avail * w.split_ratio + bar * 0.5;
                    p.draw_line(hx, r.y + 4.0, hx, r.y + r.h - 4.0, col, if is_hovered || is_pressed { 2.0 } else { 1.0 });
                    let my = r.y + r.h * 0.5;
                    p.fill_ellipse(hx, my - 8.0, 1.6, 1.6, col);
                    p.fill_ellipse(hx, my, 1.6, 1.6, col);
                    p.fill_ellipse(hx, my + 8.0, 1.6, 1.6, col);
                },
                Vertical => {
                    let avail = if r.h > bar { r.h - bar } else { 0.0 };
                    let hy = r.y + avail * w.split_ratio + bar * 0.5;
                    p.draw_line(r.x + 4.0, hy, r.x + r.w - 4.0, hy, col, if is_hovered || is_pressed { 2.0 } else { 1.0 });
                    let mx = r.x + r.w * 0.5;
                    p.fill_ellipse(mx - 8.0, hy, 1.6, 1.6, col);
                    p.fill_ellipse(mx, hy, 1.6, 1.6, col);
                    p.fill_ellipse(mx + 8.0, hy, 1.6, 1.6, col);
                },
            }
        },
        StatusBar => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.statusbar_bg };
            p.fill_rect(r.x, r.y, r.w, r.h, bg);
            p.draw_line(r.x, r.y + 0.5, r.x + r.w, r.y + 0.5, t.border_subtle, 1.0);
            let fg = if has_fg(w.style) { unpack_rgba(w.style.fg_rgba) } else { t.text_secondary };
            p.draw_text(wtext, r.x + 12.0, r.y, r.w - 24.0, r.h, fg, FontRole.Caption, Align.Start, Align.Center);
        },
        Canvas => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.input_bg };
            let bd = if is_focused { t.border_focus } else if has_border(w.style) { unpack_rgba(w.style.border_rgba) } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);
        },
        WebView => {
            let bg = if has_bg(w.style) { unpack_rgba(w.style.bg_rgba) } else { t.surface_bg };
            let bd = if is_focused { t.border_focus } else if has_border(w.style) { unpack_rgba(w.style.border_rgba) } else { t.border };
            p.fill_rounded_rect(r.x, r.y, r.w, r.h, rad, bg);
            p.draw_rounded_rect(r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, rad, bd, 1.0);
            if app.webview_has_failed(id) {
                let err_msg = app.webview_last_error(id);
                let label = if err_msg.len > 0 { err_msg } else { "WebView2 Runtime unavailable" };
                p.draw_text(label, r.x + 12.0, r.y + 12.0, r.w - 24.0, r.h - 24.0, t.danger, FontRole.Body, Align.Center, Align.Center);
            } else if !app.webview_is_ready(id) {
                p.draw_text("Loading WebView...", r.x + 12.0, r.y + 12.0, r.w - 24.0, r.h - 24.0, t.text_muted, FontRole.Caption, Align.Center, Align.Center);
            }
        },
    }
}

struct PaintFrame {
    id: WidgetId = WIDGET_NONE,
    clip: RectF = RectF {},
    saved_dc: i32 = 0,
    gl_clip: bool = false,
    d2d_clip: bool = false,
    exit_phase: bool = false,
}

fn paint_widget_tree_with<OnCanvas>(app: const App&, win_idx: i32, root_id: WidgetId, p: const Painter&, full_clip: RectF) {
    let is_sw = match p.backend { Software => true, _ => false };
    let is_gl = match p.backend { OpenGL => true, _ => false };
    let is_d2d = match p.backend { Direct2D => true, _ => false };
    var stack: PaintFrame[>..<] = [];
    stack.push(PaintFrame { id: root_id, clip: full_clip });

    while stack.len > 0 {
        let fr = stack.pop();
        let id = fr.id;
        if fr.exit_phase {
            if fr.saved_dc != 0 && p.hdc.is_valid() {
                RestoreDC(p.hdc.raw, fr.saved_dc);
            } else if fr.gl_clip {
                p.gl2d.pop_clip();
            } else if fr.d2d_clip {
                p.d2d.pop_clip();
            }
            if app.valid_widget(id) {
                match app.widgets[id.index].kind {
                    ScrollArea => {
                        let r = app.widgets[id.index].rect;
                        let max_s = app.widgets[id.index].scroll_max_y;
                        if max_s > 0.0 {
                            let track_h = r.h - 8.0;
                            let total_h = track_h + max_s;
                            let thumb_h = clamp_f32(track_h * (track_h / total_h), 24.0, track_h);
                            let thumb_y = r.y + 4.0 + (track_h - thumb_h) * (app.widgets[id.index].scroll_y / max_s);
                            p.fill_rounded_rect(r.x + r.w - 8.0, thumb_y, 5.0, thumb_h, 2.5, app.theme.border);
                        }
                    },
                    _ => {},
                }
            }
            continue;
        }

        if !app.valid_widget(id) { continue; }
        if !app.widgets[id.index].visible { continue; }
        let r = app.widgets[id.index].rect;
        if r.w <= 0.0 || r.h <= 0.0 { continue; }

        let clip = fr.clip;
        if r.x + r.w <= clip.x || r.x >= clip.x + clip.w || r.y + r.h <= clip.y || r.y >= clip.y + clip.h {
            continue;
        }

        let is_scroll = match app.widgets[id.index].kind { ScrollArea => true, _ => false };

        paint_single_widget(app, win_idx, id, p, clip);

        match app.widgets[id.index].kind {
            Canvas => {
                if r.w > 2.0 && r.h > 2.0 {
                    var cp = p;
                    cp.width = r.w;
                    cp.height = r.h;
                    match p.backend {
                        Direct2D => {
                            if p.d2d.is_valid() {
                                p.d2d.push_clip(r.x, r.y, r.w, r.h);
                                p.d2d.set_transform(1.0, 0.0, 0.0, 1.0, r.x, r.y);
                                OnCanvas(id, cp);
                                p.d2d.set_identity();
                                p.d2d.pop_clip();
                            }
                        },
                        Software => {
                            var csave: i32 = 0;
                            if p.hdc.is_valid() {
                                csave = SaveDC(p.hdc.raw);
                                IntersectClipRect(
                                    p.hdc.raw,
                                    round_i32(p.ox + r.x),
                                    round_i32(p.oy + r.y),
                                    round_i32(p.ox + r.x + r.w),
                                    round_i32(p.oy + r.y + r.h)
                                );
                            }
                            cp.ox = p.ox + r.x;
                            cp.oy = p.oy + r.y;
                            OnCanvas(id, cp);
                            if csave != 0 {
                                RestoreDC(p.hdc.raw, csave);
                            }
                        },
                        OpenGL => {
                            p.gl2d.push_clip(p.ox + r.x, p.oy + r.y, r.w, r.h);
                            cp.ox = p.ox + r.x;
                            cp.oy = p.oy + r.y;
                            OnCanvas(id, cp);
                            p.gl2d.pop_clip();
                        },
                    }
                }
            },
            _ => {},
        }

        let next_clip = if is_scroll { intersect(clip, r) } else { clip };

        var saved_dc: i32 = 0;
        var gl_clip = false;
        var d2d_clip = false;
        if is_scroll {
            if is_sw && p.hdc.is_valid() {
                saved_dc = SaveDC(p.hdc.raw);
                IntersectClipRect(
                    p.hdc.raw,
                    round_i32(p.ox + next_clip.x + 1.0),
                    round_i32(p.oy + next_clip.y + 1.0),
                    round_i32(p.ox + next_clip.x + next_clip.w - 1.0),
                    round_i32(p.oy + next_clip.y + next_clip.h - 1.0)
                );
            } else if is_gl {
                let cw = if next_clip.w > 2.0 { next_clip.w - 2.0 } else { 0.0 };
                let ch_h = if next_clip.h > 2.0 { next_clip.h - 2.0 } else { 0.0 };
                p.gl2d.push_clip(p.ox + next_clip.x + 1.0, p.oy + next_clip.y + 1.0, cw, ch_h);
                gl_clip = true;
            } else if is_d2d && p.d2d.is_valid() {
                let cw = if next_clip.w > 2.0 { next_clip.w - 2.0 } else { 0.0 };
                let ch_h = if next_clip.h > 2.0 { next_clip.h - 2.0 } else { 0.0 };
                p.d2d.push_clip(next_clip.x + 1.0, next_clip.y + 1.0, cw, ch_h);
                d2d_clip = true;
            }
        }

        if is_scroll || saved_dc != 0 || gl_clip || d2d_clip {
            stack.push(PaintFrame { id: id, clip: next_clip, saved_dc: saved_dc, gl_clip: gl_clip, d2d_clip: d2d_clip, exit_phase: true });
        }

        // Push children in reverse order so first_child is popped and painted first.
        var ch = app.widgets[id.index].last_child;
        while app.valid_widget(ch) {
            let cr = app.widgets[ch.index].rect;
            if cr.w > 0.0 && cr.h > 0.0 && cr.y + cr.h > next_clip.y && cr.y < next_clip.y + next_clip.h {
                stack.push(PaintFrame { id: ch, clip: next_clip });
            }
            ch = app.widgets[ch.index].prev_sibling;
        }
    }
}

fn paint_overlays(app: const App&, win_idx: i32, p: const Painter&) {
    let t = app.theme;

    let combo = app.windows[win_idx].open_combo;
    if app.valid_widget(combo) {
        let pr = combo_popup_rect(app, combo);
        let cnt = app.item_count(combo);
        if pr.w > 0.0 && pr.h > 0.0 && cnt > 0 {
            p.fill_rounded_rect(pr.x + 2.0, pr.y + 4.0, pr.w, pr.h, t.radius, rgba(0, 0, 0, 0.35));
            p.fill_rounded_rect(pr.x, pr.y, pr.w, pr.h, t.radius, t.surface_elevated);
            p.draw_rounded_rect(pr.x + 0.5, pr.y + 0.5, pr.w - 1.0, pr.h - 1.0, t.radius, t.border_focus, 1.0);

            let max_sc = if cnt > 8 { cnt - 8 } else { 0 };
            var sc = app.windows[win_idx].open_combo_scroll;
            if sc < 0 { sc = 0; }
            if sc > max_sc { sc = max_sc; }
            let sb_w: f32 = if cnt > 8 { 8.0 } else { 0.0 };
            let item_w = if pr.w > 8.0 + sb_w { pr.w - 8.0 - sb_w } else { 0.0 };

            let ih: f32 = 28.0;
            var idx: i32 = 0;
            var vis_row: i32 = 0;
            for i in app.list_items.len {
                if app.list_items[i].alive && eq(app.list_items[i].owner, combo) {
                    if idx >= sc && vis_row < 8 {
                        let iy = pr.y + 4.0 + vis_row * ih;
                        let sel = idx == app.widgets[combo.index].selected_index;
                        let hov = idx == app.windows[win_idx].open_combo_hover;
                        if hov {
                            p.fill_rounded_rect(pr.x + 4.0, iy, item_w, ih - 2.0, t.radius_sm, t.accent);
                        } else if sel {
                            p.fill_rounded_rect(pr.x + 4.0, iy, item_w, ih - 2.0, t.radius_sm, t.surface_active);
                        }
                        let fg = if hov { t.accent_text } else { t.text_primary };
                        p.draw_text(app.str_view(app.list_items[i].text), pr.x + 12.0, iy, item_w - 16.0, ih - 2.0, fg, FontRole.Body, Align.Start, Align.Center);
                        vis_row += 1;
                    }
                    idx += 1;
                }
            }

            if cnt > 8 {
                let track_h = pr.h - 8.0;
                let thumb_h = clamp_f32(track_h * (8.0 / cnt), 20.0, track_h);
                let thumb_y = pr.y + 4.0 + (track_h - thumb_h) * ((sc as f32) / max_sc);
                p.fill_rounded_rect(pr.x + pr.w - 7.0, thumb_y, 4.0, thumb_h, 2.0, t.border);
            }
        }
    }

    let hov = app.windows[win_idx].hovered;
    if app.valid_widget(hov) && !app.windows[win_idx].mouse_down && !app.valid_widget(combo) {
        let tip = app.str_view(app.widgets[hov.index].tooltip);
        if tip.len > 0 {
            let now = win32::tick_count_ms();
            if app.windows[win_idx].tooltip_visible || now >= app.windows[win_idx].hover_since_ms + 450 {
                let tw = measure_text_width_role(tip, t, FontRole.Caption) + 18.0;
                let th: f32 = 26.0;
                let ww = app.windows[win_idx].width as f32;
                let wh = app.windows[win_idx].height as f32;
                var tx = app.windows[win_idx].mouse_x + 12.0;
                var ty = app.windows[win_idx].mouse_y + 18.0;
                if tx + tw > ww - 6.0 { tx = ww - tw - 6.0; }
                if ty + th > wh - 6.0 { ty = app.windows[win_idx].mouse_y - th - 8.0; }
                if tx < 4.0 { tx = 4.0; }
                if ty < 4.0 { ty = 4.0; }

                p.fill_rounded_rect(tx + 1.0, ty + 2.0, tw, th, t.radius_sm, rgba(0, 0, 0, 0.35));
                p.fill_rounded_rect(tx, ty, tw, th, t.radius_sm, t.tooltip_bg);
                p.draw_rounded_rect(tx + 0.5, ty + 0.5, tw - 1.0, th - 1.0, t.radius_sm, t.border, 1.0);
                p.draw_text(tip, tx + 8.0, ty, tw - 16.0, th, t.tooltip_text, FontRole.Caption, Align.Start, Align.Center);
            }
        }
    }
}

fn sync_window_client_size(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    if app.windows[win.index].headless || !app.windows[win.index].hwnd.is_valid() {
        return;
    }
    let rc = app.windows[win.index].hwnd.client_rect();
    let cw = rc.width();
    let ch = rc.height();
    if cw <= 0 || ch <= 0 { return; }
    if cw != app.windows[win.index].width || ch != app.windows[win.index].height {
        app.windows[win.index].width = cw;
        app.windows[win.index].height = ch;
        if app.windows[win.index].d2d.is_valid() {
            app.windows[win.index].d2d.resize(cw, ch);
        } else if app.windows[win.index].gl2d.is_valid() {
            app.windows[win.index].gl2d.resize(cw, ch);
        }
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.windows[win.index].layout_dirty = true;
    }
}

fn render_window_with<OnCanvas>(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    sync_window_client_size(app, win);
    app.update_layout(win);

    if app.windows[win.index].headless {
        app.windows[win.index].dirty = false;
        return;
    }
    if !app.windows[win.index].visible || app.windows[win.index].width <= 0 || app.windows[win.index].height <= 0 {
        return;
    }

    let ww = app.windows[win.index].width as f32;
    let wh = app.windows[win.index].height as f32;
    let full_clip = RectF { x: 0.0, y: 0.0, w: ww, h: wh };
    let backend = app.windows[win.index].backend;

    var p = Painter {
        backend: backend,
        d2d: app.windows[win.index].d2d,
        fonts: app.windows[win.index].fonts,
        gl2d: app.windows[win.index].gl2d,
        gl2d_fonts: app.windows[win.index].gl2d_fonts,
        gdi_fonts: app.windows[win.index].gdi_fonts,
        metric_dc: app.windows[win.index].metric_dc,
        metric_fonts: match backend {
            Software => app.windows[win.index].gdi_fonts,
            _ => app.windows[win.index].metric_fonts,
        },
        theme: app.theme,
        width: ww,
        height: wh,
    };

    match backend {
        Direct2D => {
            guard p.d2d.is_valid() else { return; }
            p.d2d.begin_draw();
            p.d2d.set_identity();
            p.d2d.clear(to_d2d(app.theme.window_bg));
        },
        Software => {
            var paint_rc = win32::Rect {};
            let dc = app.windows[win.index].hwnd.begin_paint(paint_rc);
            guard dc.is_valid() else { return; }
            p.hdc = dc;
            dc.fill_rect(paint_rc, to_colorref(app.theme.window_bg));
        },
        OpenGL => {
            guard p.gl2d.is_valid() else { return; }
            p.gl2d.begin_draw(to_d2d(app.theme.window_bg));
        },
    }

    let root_id = app.windows[win.index].root_widget;
    if app.valid_widget(root_id) {
        paint_widget_tree_with(app, win.index, root_id, p, full_clip) { cid, cp => OnCanvas(cid, cp); };
    }

    let sb = app.windows[win.index].status_bar;
    if app.valid_widget(sb) && app.widgets[sb.index].visible {
        paint_single_widget(app, win.index, sb, p, full_clip);
    }

    paint_overlays(app, win.index, p);

    match backend {
        Direct2D => { p.d2d.end_draw(); },
        Software => { app.windows[win.index].hwnd.end_paint(); },
        OpenGL => { p.gl2d.end_draw(); },
    }
    app.windows[win.index].dirty = false;
}

fn render_window(app: App&, win: WindowId) {
    app.render_window_with(win) { _id, _p => };
}

fn render_all_with<OnCanvas>(app: App&) {
    for i in app.windows.len {
        if app.windows[i].alive && (app.windows[i].dirty || app.windows[i].layout_dirty) {
            let wid = WindowId { index: i as! i32, gen: app.windows[i].gen };
            app.render_window_with(wid) { cid, p => OnCanvas(cid, p); };
        }
    }
}

fn render_all(app: App&) {
    app.render_all_with() { _id, _p => };
}
