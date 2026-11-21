// Theme palette, per-widget style overrides, and UTF-8 text metrics.
namespace goose_ui;

import std;
import types;

struct Theme {
    is_dark: bool = true,

    // Surfaces
    window_bg: Color = COLOR_TRANSPARENT,
    surface_bg: Color = COLOR_TRANSPARENT,
    surface_elevated: Color = COLOR_TRANSPARENT,
    surface_hover: Color = COLOR_TRANSPARENT,
    surface_active: Color = COLOR_TRANSPARENT,
    input_bg: Color = COLOR_TRANSPARENT,
    input_bg_disabled: Color = COLOR_TRANSPARENT,
    statusbar_bg: Color = COLOR_TRANSPARENT,
    tooltip_bg: Color = COLOR_TRANSPARENT,

    // Borders
    border: Color = COLOR_TRANSPARENT,
    border_subtle: Color = COLOR_TRANSPARENT,
    border_focus: Color = COLOR_TRANSPARENT,

    // Text
    text_primary: Color = COLOR_TRANSPARENT,
    text_secondary: Color = COLOR_TRANSPARENT,
    text_muted: Color = COLOR_TRANSPARENT,
    text_disabled: Color = COLOR_TRANSPARENT,
    tooltip_text: Color = COLOR_TRANSPARENT,

    // Semantic accents
    accent: Color = COLOR_TRANSPARENT,
    accent_hover: Color = COLOR_TRANSPARENT,
    accent_active: Color = COLOR_TRANSPARENT,
    accent_text: Color = COLOR_TRANSPARENT,
    selection_bg: Color = COLOR_TRANSPARENT,

    danger: Color = COLOR_TRANSPARENT,
    danger_hover: Color = COLOR_TRANSPARENT,
    danger_active: Color = COLOR_TRANSPARENT,
    success: Color = COLOR_TRANSPARENT,
    warning: Color = COLOR_TRANSPARENT,

    // Metrics
    radius: f32 = 6.0,
    radius_sm: f32 = 4.0,
    radius_lg: f32 = 10.0,
    control_height: f32 = 32.0,
    spacing: f32 = 8.0,
    font_size_body: f32 = 14.0,
    font_size_heading: f32 = 22.0,
    font_size_subheading: f32 = 16.0,
    font_size_caption: f32 = 12.0,
    font_size_mono: f32 = 13.5,
}

fn theme_dark() -> Theme {
    return Theme {
        is_dark: true,

        window_bg: color_hex(0x161922),
        surface_bg: color_hex(0x1E222F),
        surface_elevated: color_hex(0x262B3B),
        surface_hover: color_hex(0x2F364A),
        surface_active: color_hex(0x39425B),
        input_bg: color_hex(0x12151D),
        input_bg_disabled: color_hex(0x191D28),
        statusbar_bg: color_hex(0x12151C),
        tooltip_bg: color_hex(0x0E1118),

        border: color_hex(0x343C52),
        border_subtle: color_hex(0x262C3D),
        border_focus: color_hex(0x60A5FA),

        text_primary: color_hex(0xF1F5F9),
        text_secondary: color_hex(0xCBD5E1),
        text_muted: color_hex(0x8894AA),
        text_disabled: color_hex(0x556075),
        tooltip_text: color_hex(0xF8FAFC),

        accent: color_hex(0x3B82F6),
        accent_hover: color_hex(0x60A5FA),
        accent_active: color_hex(0x2563EB),
        accent_text: color_hex(0xFFFFFF),
        selection_bg: color_hex(0x3B82F6, 0.32),

        danger: color_hex(0xEF4444),
        danger_hover: color_hex(0xF87171),
        danger_active: color_hex(0xDC2626),
        success: color_hex(0x22C55E),
        warning: color_hex(0xF59E0B),

        radius: 6.0,
        radius_sm: 4.0,
        radius_lg: 10.0,
        control_height: 32.0,
        spacing: 8.0,
        font_size_body: 14.0,
        font_size_heading: 22.0,
        font_size_subheading: 16.0,
        font_size_caption: 12.0,
        font_size_mono: 13.5,
    };
}

fn theme_light() -> Theme {
    return Theme {
        is_dark: false,

        window_bg: color_hex(0xF3F5F9),
        surface_bg: color_hex(0xFFFFFF),
        surface_elevated: color_hex(0xF8FAFC),
        surface_hover: color_hex(0xEBF0F7),
        surface_active: color_hex(0xDCE4F0),
        input_bg: color_hex(0xFFFFFF),
        input_bg_disabled: color_hex(0xF1F5F9),
        statusbar_bg: color_hex(0xE8ECF4),
        tooltip_bg: color_hex(0x1E293B),

        border: color_hex(0xCBD5E1),
        border_subtle: color_hex(0xE2E8F0),
        border_focus: color_hex(0x2563EB),

        text_primary: color_hex(0x0F172A),
        text_secondary: color_hex(0x334155),
        text_muted: color_hex(0x64748B),
        text_disabled: color_hex(0x94A3B8),
        tooltip_text: color_hex(0xF8FAFC),

        accent: color_hex(0x2563EB),
        accent_hover: color_hex(0x3B82F6),
        accent_active: color_hex(0x1D4ED8),
        accent_text: color_hex(0xFFFFFF),
        selection_bg: color_hex(0x2563EB, 0.20),

        danger: color_hex(0xDC2626),
        danger_hover: color_hex(0xEF4444),
        danger_active: color_hex(0xB91C1C),
        success: color_hex(0x16A34A),
        warning: color_hex(0xD97706),

        radius: 6.0,
        radius_sm: 4.0,
        radius_lg: 10.0,
        control_height: 32.0,
        spacing: 8.0,
        font_size_body: 14.0,
        font_size_heading: 22.0,
        font_size_subheading: 16.0,
        font_size_caption: 12.0,
        font_size_mono: 13.5,
    };
}

// Compact per-widget style overrides (24 bytes; packed RGBA colors).
let STYLE_HAS_BG: u8 = 1;
let STYLE_HAS_FG: u8 = 2;
let STYLE_HAS_BORDER: u8 = 4;
let STYLE_HAS_RADIUS: u8 = 8;

struct WidgetStyle {
    flags: u8 = 0,
    bg_rgba: u32 = 0,
    fg_rgba: u32 = 0,
    border_rgba: u32 = 0,
    radius: f32 = 6.0,
    border_width: f32 = 1.0,
}

fn has_bg(s: const WidgetStyle&) -> bool { (s.flags & STYLE_HAS_BG) != 0 }
fn has_fg(s: const WidgetStyle&) -> bool { (s.flags & STYLE_HAS_FG) != 0 }
fn has_border(s: const WidgetStyle&) -> bool { (s.flags & STYLE_HAS_BORDER) != 0 }
fn has_radius(s: const WidgetStyle&) -> bool { (s.flags & STYLE_HAS_RADIUS) != 0 }

fn font_size_for_role(theme: const Theme&, role: FontRole) -> f32 {
    return match role {
        Body => theme.font_size_body,
        BodyBold => theme.font_size_body,
        Heading => theme.font_size_heading,
        Subheading => theme.font_size_subheading,
        Caption => theme.font_size_caption,
        Mono => theme.font_size_mono,
    };
}

// --- Pure-Goose UTF-8 Text Advance Metrics ----------------------------------
// Calibrated to Segoe UI (proportional) and Consolas (monospace) so layout size
// hints and LineEdit caret positioning work accurately both visually and in
// headless tests without requiring GDI/DirectWrite roundtrips.

fn char_width_ratio_segoe(cp: i64) -> f32 {
    if cp == 32 { return 0.28; } // space
    if cp == 9 { return 1.12; }  // tab
    if cp >= 0x3000 { return 0.96; } // CJK / fullwidth
    if cp >= 0x0080 { return 0.56; } // Latin-1 / extended
    // Narrow ASCII glyphs
    if cp == 'i' || cp == 'l' || cp == '!' || cp == '|' || cp == '.' || cp == ',' || cp == ':' || cp == ';' || cp == '\'' || cp == 'I' {
        return 0.27;
    }
    if cp == 'j' || cp == 'f' || cp == 'r' || cp == 't' || cp == '(' || cp == ')' || cp == '[' || cp == ']' || cp == '{' || cp == '}' || cp == '/' || cp == '\\' || cp == '-' {
        return 0.35;
    }
    // Wide ASCII glyphs
    if cp == 'm' || cp == 'w' || cp == 'M' || cp == 'W' || cp == '@' || cp == '%' {
        return 0.84;
    }
    if cp >= 'A' && cp <= 'Z' {
        return 0.64;
    }
    if cp >= '0' && cp <= '9' {
        return 0.54;
    }
    return 0.52;
}

fn measure_text_width(text: const u8[:], font_size: f32, mono: bool = false) -> f32 {
    var total: f32 = 0.0;
    var i: i64 = 0;
    while i < text.len {
        let b0 = text[i];
        var cp: i64 = b0;
        var step: i64 = 1;
        if b0 >= 0xF0 && i + 3 < text.len {
            cp = (((b0 & 0x07) as i64) << 18) | (((text[i + 1] & 0x3F) as i64) << 12) | (((text[i + 2] & 0x3F) as i64) << 6) | (text[i + 3] & 0x3F);
            step = 4;
        } else if b0 >= 0xE0 && i + 2 < text.len {
            cp = (((b0 & 0x0F) as i64) << 12) | (((text[i + 1] & 0x3F) as i64) << 6) | (text[i + 2] & 0x3F);
            step = 3;
        } else if b0 >= 0xC0 && i + 1 < text.len {
            cp = (((b0 & 0x1F) as i64) << 6) | (text[i + 1] & 0x3F);
            step = 2;
        }
        if mono {
            total += font_size * (if cp >= 0x3000 { 1.0 } else { 0.55 });
        } else {
            total += font_size * char_width_ratio_segoe(cp);
        }
        i += step;
    }
    return total;
}

fn measure_text_width_role(text: const u8[:], theme: const Theme&, role: FontRole) -> f32 {
    let sz = font_size_for_role(theme, role);
    let is_mono = match role { Mono => true, _ => false };
    let is_bold = match role { BodyBold, Heading, Subheading => true, _ => false };
    let w = measure_text_width(text, sz, is_mono);
    return if is_bold { w * 1.04 } else { w };
}

fn password_char_width(font_size: f32, mono: bool = false) -> f32 {
    return font_size * (if mono { 0.55 } else { char_width_ratio_segoe('*') });
}

fn measure_text_prefix_width(text: const u8[:], byte_pos: i32, font_size: f32, mono: bool = false, password_mode: bool = false) -> f32 {
    let n = text.len as! i32;
    let pos = if byte_pos < 0 { 0 } else if byte_pos > n { n } else { byte_pos };
    if pos == 0 { return 0.0; }
    if password_mode {
        var chars: i32 = 0;
        for i in 0..pos {
            if (text[i] & 0xC0) != 0x80 { chars += 1; }
        }
        return chars * password_char_width(font_size, mono);
    }
    return measure_text_width(text[..pos], font_size, mono);
}

// Finds the byte offset in `text` whose visual x position is closest to `rel_x`.
fn caret_byte_from_x(text: const u8[:], rel_x: f32, font_size: f32, mono: bool = false, password_mode: bool = false) -> i32 {
    if rel_x <= 0.0 || text.len == 0 { return 0; }
    var acc: f32 = 0.0;
    var i: i64 = 0;
    while i < text.len {
        let b0 = text[i];
        var cp: i64 = b0;
        var step: i64 = 1;
        if b0 >= 0xF0 && i + 3 < text.len {
            cp = (((b0 & 0x07) as i64) << 18) | (((text[i + 1] & 0x3F) as i64) << 12) | (((text[i + 2] & 0x3F) as i64) << 6) | (text[i + 3] & 0x3F);
            step = 4;
        } else if b0 >= 0xE0 && i + 2 < text.len {
            cp = (((b0 & 0x0F) as i64) << 12) | (((text[i + 1] & 0x3F) as i64) << 6) | (text[i + 2] & 0x3F);
            step = 3;
        } else if b0 >= 0xC0 && i + 1 < text.len {
            cp = (((b0 & 0x1F) as i64) << 6) | (text[i + 1] & 0x3F);
            step = 2;
        }
        let cw = if password_mode {
            password_char_width(font_size, mono)
        } else if mono {
            font_size * (if cp >= 0x3000 { 1.0 } else { 0.55 })
        } else {
            font_size * char_width_ratio_segoe(cp)
        };
        if rel_x < acc + cw * 0.5 {
            return i as! i32;
        }
        acc += cw;
        i += step;
    }
    return text.len as! i32;
}

// Snaps `pos` to a valid UTF-8 codepoint boundary in `text`.
fn utf8_snap_boundary(text: const u8[:], pos: i32) -> i32 {
    let n = text.len as! i32;
    if pos <= 0 || n <= 0 { return 0; }
    if pos >= n { return n; }
    var p = pos;
    while p > 0 && (text[p] & 0xC0) == 0x80 {
        p -= 1;
    }
    return p;
}

// UTF-8 navigation helpers (never split multi-byte characters).
fn utf8_prev_char(text: const u8[:], pos: i32) -> i32 {
    let n = text.len as! i32;
    if pos <= 0 || n <= 0 { return 0; }
    var p = pos - 1;
    if p >= n { p = n - 1; }
    while p > 0 && (text[p] & 0xC0) == 0x80 {
        p -= 1;
    }
    return p;
}

fn utf8_next_char(text: const u8[:], pos: i32) -> i32 {
    let n = text.len as! i32;
    if n <= 0 { return 0; }
    if pos < 0 { return 0; }
    if pos >= n { return n; }
    var p = pos + 1;
    while p < n && (text[p] & 0xC0) == 0x80 {
        p += 1;
    }
    return p;
}
