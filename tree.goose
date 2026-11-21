// Widget tree management, string pool, window lifecycle (Software GDI & Direct2D),
// widget constructors, properties, and declarative Signal-Slot connections.
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import theme;
import widget;

// Internal Win32 timer ID for hover tooltip auto-reveal (reserved outside user IDs).
let INTERNAL_TOOLTIP_TIMER_ID: u64 = 0x7FFF0001;

// --- Direct GDI Font Creation (for Software GDI backend) --------------------

extern "gdi32" {
    fn CreateFontA(
        height: i32,
        width: i32,
        escapement: i32,
        orientation: i32,
        weight: i32,
        italic: u32,
        underline: u32,
        strikeout: u32,
        charset: u32,
        out_prec: u32,
        clip_prec: u32,
        quality: u32,
        pitch_family: u32,
        face: const u8&
    ) -> u64;
}

// --- Inline & Pooled String Helpers -----------------------------------------

fn copy_str<B>(dst: B&, src: const u8[:]) {
    dst.resize(0);
    let cap = dst.cap;
    var n = src.len;
    if n > cap {
        n = cap;
        while n > 0 && (src[n] & 0xC0) == 0x80 {
            n -= 1;
        }
    }
    if n > 0 {
        dst.append(src[..n]);
    }
}

fn str_view(app: const App&, s: StrSpan) -> const u8[:] {
    if s.len <= 0 || s.off < 0 || s.off + s.len > app.str_pool.len {
        return "";
    }
    return app.str_pool[s.off..s.off + s.len];
}

// Stores `src` into `pool` using `s`. Reuses `s`'s existing slot in-place when
// `src.len <= s.cap`; otherwise allocates a new run at the end of `pool`.
fn str_set(pool: u8[>..]&, s: StrSpan&, src: const u8[:], min_grow: i32 = 0) {
    let n = src.len as! i32;
    if n == 0 {
        s.len = 0;
        return;
    }

    if n <= s.cap && s.cap > 0 && s.off >= 0 && s.off + s.cap <= pool.len {
        // Copy via temporary buffer in case `src` aliases inside `pool`.
        var tmp: u8[>..] = [];
        tmp.append(src);
        for i in 0..n {
            pool[s.off + i] = tmp[i];
        }
        s.len = n;
        return;
    }

    var new_cap = n;
    if min_grow > new_cap { new_cap = min_grow; }
    if s.cap > 0 {
        let doubled = s.cap * 2;
        if doubled > new_cap { new_cap = doubled; }
        if new_cap < 32 { new_cap = 32; }
    }

    let off = pool.len as! i32;
    // Grow-only `pool` never moves, so `src` remains valid even if it points into `pool`.
    pool.append(src);
    if new_cap > n {
        for _ in n..new_cap {
            pool.push(0);
        }
    }
    s.off = off;
    s.len = n;
    s.cap = new_cap;
}

// --- App Initialization, Backends & Font Caches -----------------------------

fn init(app: App&, dark: bool = true, backend: RenderBackend = RenderBackend.Direct2D) {
    if !app.initialized {
        win32::enable_dpi_awareness();
        app.theme = if dark { theme_dark() } else { theme_light() };
        app.backend = backend;
        app.initialized = true;
    }
}

fn set_backend(app: App&, backend: RenderBackend) {
    app.backend = backend;
}

fn create_window_fonts(d2d: win32::D2dTarget, t: const Theme&) -> FontSet {
    var fs = FontSet {};
    guard d2d.is_valid() else { return fs; }
    fs.body = d2d.create_font("Segoe UI", t.font_size_body, 400, false);
    fs.body_bold = d2d.create_font("Segoe UI", t.font_size_body, 600, false);
    fs.heading = d2d.create_font("Segoe UI", t.font_size_heading, 600, false);
    fs.subheading = d2d.create_font("Segoe UI", t.font_size_subheading, 600, false);
    fs.caption = d2d.create_font("Segoe UI", t.font_size_caption, 400, false);
    fs.mono = d2d.create_font("Consolas", t.font_size_mono, 400, false);
    return fs;
}

fn destroy_window_fonts(fs: FontSet&) {
    if fs.body.is_valid() { fs.body.destroy(); }
    if fs.body_bold.is_valid() { fs.body_bold.destroy(); }
    if fs.heading.is_valid() { fs.heading.destroy(); }
    if fs.subheading.is_valid() { fs.subheading.destroy(); }
    if fs.caption.is_valid() { fs.caption.destroy(); }
    if fs.mono.is_valid() { fs.mono.destroy(); }
    fs = FontSet {};
}

fn make_gdi_font(px_size: f32, weight: i32, face_nul: const u8[:]) -> win32::Hfont {
    // Negative cHeight specifies character height in device pixels; quality 5 = CLEARTYPE_QUALITY.
    let h = -((px_size * 1.15 + 0.5) as! i32);
    let raw = CreateFontA(h, 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 5, 0, face_nul[0]);
    return win32::Hfont { raw: raw };
}

fn create_gdi_fonts(t: const Theme&) -> GdiFontSet {
    let segoe: const u8[:] = "Segoe UI\0";
    let consolas: const u8[:] = "Consolas\0";
    return GdiFontSet {
        body: make_gdi_font(t.font_size_body, 400, segoe),
        body_bold: make_gdi_font(t.font_size_body, 600, segoe),
        heading: make_gdi_font(t.font_size_heading, 600, segoe),
        subheading: make_gdi_font(t.font_size_subheading, 600, segoe),
        caption: make_gdi_font(t.font_size_caption, 400, segoe),
        mono: make_gdi_font(t.font_size_mono, 400, consolas),
    };
}

fn destroy_gdi_font(f: win32::Hfont) {
    if f.is_valid() { win32::DeleteObject(f.raw); }
}

fn destroy_gdi_fonts(fs: GdiFontSet&) {
    destroy_gdi_font(fs.body);
    destroy_gdi_font(fs.body_bold);
    destroy_gdi_font(fs.heading);
    destroy_gdi_font(fs.subheading);
    destroy_gdi_font(fs.caption);
    destroy_gdi_font(fs.mono);
    fs = GdiFontSet {};
}

fn set_theme(app: App&, t: Theme) {
    app.theme = t;
    for i in app.windows.len {
        if app.windows[i].alive {
            if !app.windows[i].headless && app.windows[i].hwnd.is_valid() {
                app.windows[i].hwnd.set_dark_titlebar(t.is_dark);
                match app.windows[i].backend {
                    Direct2D => {
                        destroy_window_fonts(app.windows[i].fonts);
                        app.windows[i].fonts = create_window_fonts(app.windows[i].d2d, app.theme);
                    },
                    Software => {
                        destroy_gdi_fonts(app.windows[i].gdi_fonts);
                        app.windows[i].gdi_fonts = create_gdi_fonts(app.theme);
                    },
                }
            }
            app.windows[i].layout_dirty = true;
            app.windows[i].dirty = true;
        }
    }
}

fn toggle_theme(app: App&) {
    if app.theme.is_dark {
        app.set_theme(theme_light());
    } else {
        app.set_theme(theme_dark());
    }
}

fn is_dark_theme(app: const App&) -> bool {
    return app.theme.is_dark;
}

// --- Handle Validation Helpers ----------------------------------------------

fn valid_window(app: const App&, id: WindowId) -> bool {
    if id.index < 0 || id.index >= app.windows.len || id.gen == 0 { return false; }
    return app.windows[id.index].alive && app.windows[id.index].gen == id.gen;
}

fn valid_widget(app: const App&, id: WidgetId) -> bool {
    if id.index < 0 || id.index >= app.widgets.len || id.gen == 0 { return false; }
    return app.widgets[id.index].alive && app.widgets[id.index].gen == id.gen;
}

fn mark_dirty(app: App&, win: WindowId) {
    if app.valid_window(win) {
        app.windows[win.index].dirty = true;
    }
}

fn mark_layout_dirty(app: App&, win: WindowId) {
    if app.valid_window(win) {
        app.windows[win.index].layout_dirty = true;
        app.windows[win.index].dirty = true;
    }
}

fn mark_widget_dirty(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }
    app.mark_dirty(app.widgets[id.index].window);
}

fn mark_widget_layout_dirty(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }
    app.mark_layout_dirty(app.widgets[id.index].window);
}

fn active_window_count(app: const App&) -> i32 {
    var count: i32 = 0;
    for i in app.windows.len {
        if app.windows[i].alive { count += 1; }
    }
    return count;
}

fn find_window_by_hwnd(app: const App&, raw_hwnd: u64) -> WindowId {
    for i in app.windows.len {
        if app.windows[i].alive && !app.windows[i].headless && app.windows[i].hwnd.raw == raw_hwnd {
            return WindowId { index: i as! i32, gen: app.windows[i].gen };
        }
    }
    return WINDOW_NONE;
}

// --- Internal Widget Allocation & Tree Operations ---------------------------

fn alloc_widget(app: App&, kind: WidgetKind, win: WindowId) -> WidgetId {
    var idx: i64 = -1;
    var next_gen: u32 = 1;
    if app.free_widgets.len > 0 {
        idx = app.free_widgets.pop();
        next_gen = app.widgets[idx].gen + 1;
        if next_gen == 0 { next_gen = 1; }
        app.widgets[idx] = Widget {
            alive: true,
            gen: next_gen,
            kind: kind,
            window: win,
        };
    } else {
        idx = app.widgets.len;
        app.widgets.push(Widget {
            alive: true,
            gen: 1,
            kind: kind,
            window: win,
        });
    }
    return WidgetId { index: idx as! i32, gen: next_gen };
}

fn attach_child(app: App&, parent: WidgetId, child: WidgetId) {
    guard app.valid_widget(parent) && app.valid_widget(child) else { return; }
    let win = app.widgets[parent.index].window;
    app.widgets[child.index].window = win;
    app.widgets[child.index].parent = parent;
    app.widgets[child.index].next_sibling = WIDGET_NONE;

    let last = app.widgets[parent.index].last_child;
    if app.valid_widget(last) {
        app.widgets[last.index].next_sibling = child;
        app.widgets[child.index].prev_sibling = last;
        app.widgets[parent.index].last_child = child;
    } else {
        app.widgets[parent.index].first_child = child;
        app.widgets[parent.index].last_child = child;
        app.widgets[child.index].prev_sibling = WIDGET_NONE;
    }
    app.widgets[parent.index].child_count += 1;
    app.mark_layout_dirty(win);
}

fn detach_from_parent(app: App&, child: WidgetId) {
    guard app.valid_widget(child) else { return; }
    let parent = app.widgets[child.index].parent;
    guard app.valid_widget(parent) else { return; }

    let prev = app.widgets[child.index].prev_sibling;
    let next = app.widgets[child.index].next_sibling;

    if app.valid_widget(prev) {
        app.widgets[prev.index].next_sibling = next;
    } else {
        app.widgets[parent.index].first_child = next;
    }

    if app.valid_widget(next) {
        app.widgets[next.index].prev_sibling = prev;
    } else {
        app.widgets[parent.index].last_child = prev;
    }

    app.widgets[parent.index].child_count -= 1;
    app.widgets[child.index].parent = WIDGET_NONE;
    app.widgets[child.index].prev_sibling = WIDGET_NONE;
    app.widgets[child.index].next_sibling = WIDGET_NONE;
    app.mark_layout_dirty(app.widgets[parent.index].window);
}

fn cancel_tooltip_timer(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    if app.windows[win.index].tooltip_timer_active {
        if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
            app.windows[win.index].hwnd.kill_timer(INTERNAL_TOOLTIP_TIMER_ID);
        }
        app.windows[win.index].tooltip_timer_active = false;
    }
    if app.windows[win.index].tooltip_visible {
        app.windows[win.index].tooltip_visible = false;
        app.windows[win.index].dirty = true;
    }
}

fn is_ancestor_or_self(app: const App&, ancestor: WidgetId, node: WidgetId) -> bool {
    var cur = node;
    while app.valid_widget(cur) {
        if eq(cur, ancestor) { return true; }
        cur = app.widgets[cur.index].parent;
    }
    return false;
}

fn clear_window_refs_in_subtree(app: App&, root: WidgetId) {
    guard app.valid_widget(root) else { return; }
    let win = app.widgets[root.index].window;
    guard app.valid_window(win) else { return; }

    if is_ancestor_or_self(app, root, app.windows[win.index].hovered) {
        app.windows[win.index].hovered = WIDGET_NONE;
        cancel_tooltip_timer(app, win);
        app.mark_dirty(win);
    }
    if is_ancestor_or_self(app, root, app.windows[win.index].pressed) {
        app.windows[win.index].pressed = WIDGET_NONE;
        app.windows[win.index].mouse_down = false;
        app.mark_dirty(win);
    }
    let foc = app.windows[win.index].focused;
    if is_ancestor_or_self(app, root, foc) {
        app.windows[win.index].focused = WIDGET_NONE;
        app.signals.push(Signal.FocusChanged { widget: foc, window: win, focused: false });
        app.mark_dirty(win);
    }
    if is_ancestor_or_self(app, root, app.windows[win.index].captured) {
        app.windows[win.index].captured = WIDGET_NONE;
        app.windows[win.index].mouse_down = false;
        if !app.windows[win.index].headless { win32::release_capture(); }
        app.mark_dirty(win);
    }
    if is_ancestor_or_self(app, root, app.windows[win.index].open_combo) {
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
        app.mark_dirty(win);
    }
    if is_ancestor_or_self(app, root, app.windows[win.index].last_click_widget) {
        app.windows[win.index].last_click_widget = WIDGET_NONE;
        app.windows[win.index].last_click_item = -1;
    }
}

fn compact_list_items(app: App&, force: bool = false) {
    let n = app.list_items.len;
    if n == 0 { return; }
    var alive_cnt: i64 = 0;
    for i in n {
        if app.list_items[i].alive { alive_cnt += 1; }
    }
    let dead_cnt = n - alive_cnt;
    if dead_cnt == 0 { return; }
    if !force && dead_cnt < 32 && dead_cnt * 2 < n {
        // Always trim dead tail slots cheaply.
        var new_len = n;
        while new_len > 0 && !app.list_items[new_len - 1].alive {
            new_len -= 1;
        }
        if new_len < n {
            app.list_items.resize(new_len);
        }
        return;
    }
    var write: i64 = 0;
    for i in n {
        if app.list_items[i].alive {
            if write != i {
                app.list_items[write] = app.list_items[i];
            }
            write += 1;
        }
    }
    app.list_items.resize(write);
}

fn compact_connections(app: App&) {
    let n = app.connections.len;
    if n == 0 { return; }
    var alive_cnt: i64 = 0;
    for i in n {
        if app.connections[i].alive { alive_cnt += 1; }
    }
    let dead_cnt = n - alive_cnt;
    if dead_cnt == 0 { return; }
    if dead_cnt < 32 && dead_cnt * 2 < n {
        var new_len = n;
        while new_len > 0 && !app.connections[new_len - 1].alive {
            new_len -= 1;
        }
        if new_len < n {
            app.connections.resize(new_len);
        }
        return;
    }
    var write: i64 = 0;
    for i in n {
        if app.connections[i].alive {
            if write != i {
                app.connections[write] = app.connections[i];
            }
            write += 1;
        }
    }
    app.connections.resize(write);
}

recursive fn destroy_widget_subtree(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }

    var ch = app.widgets[id.index].first_child;
    while app.valid_widget(ch) {
        let next = app.widgets[ch.index].next_sibling;
        destroy_widget_subtree(app, ch);
        ch = next;
    }

    let win = app.widgets[id.index].window;
    if app.valid_window(win) {
        if eq(app.windows[win.index].hovered, id) {
            app.windows[win.index].hovered = WIDGET_NONE;
            cancel_tooltip_timer(app, win);
        }
        if eq(app.windows[win.index].pressed, id) {
            app.windows[win.index].pressed = WIDGET_NONE;
            app.windows[win.index].mouse_down = false;
        }
        if eq(app.windows[win.index].focused, id) {
            app.windows[win.index].focused = WIDGET_NONE;
        }
        if eq(app.windows[win.index].captured, id) {
            app.windows[win.index].captured = WIDGET_NONE;
            app.windows[win.index].mouse_down = false;
            if !app.windows[win.index].headless { win32::release_capture(); }
        }
        if eq(app.windows[win.index].open_combo, id) {
            app.windows[win.index].open_combo = WIDGET_NONE;
            app.windows[win.index].open_combo_hover = -1;
            app.windows[win.index].open_combo_scroll = 0;
        }
        if eq(app.windows[win.index].last_click_widget, id) {
            app.windows[win.index].last_click_widget = WIDGET_NONE;
            app.windows[win.index].last_click_item = -1;
        }
    }

    for i in app.list_items.len {
        if app.list_items[i].alive && (eq(app.list_items[i].owner, id) || eq(app.list_items[i].page, id)) {
            app.list_items[i].alive = false;
        }
    }
    for i in app.connections.len {
        if app.connections[i].alive && (eq(app.connections[i].sender, id) || eq(app.connections[i].receiver, id)) {
            app.connections[i].alive = false;
        }
    }

    app.widgets[id.index].alive = false;
    app.free_widgets.push(id.index);
}

fn destroy_widget(app: App&, id: WidgetId) {
    guard app.valid_widget(id) else { return; }
    let win = app.widgets[id.index].window;
    let parent = app.widgets[id.index].parent;
    detach_from_parent(app, id);
    destroy_widget_subtree(app, id);
    compact_list_items(app);
    compact_connections(app);
    // Keep TabWidget selected_index in bounds if a tab page was destroyed directly.
    if app.valid_widget(parent) {
        match app.widgets[parent.index].kind {
            TabWidget => {
                let cnt = app.item_count(parent);
                if cnt <= 0 {
                    app.widgets[parent.index].selected_index = -1;
                } else if app.widgets[parent.index].selected_index >= cnt {
                    app.widgets[parent.index].selected_index = cnt - 1;
                }
            },
            _ => {},
        }
    }
    app.mark_layout_dirty(win);
}

// --- Window Creation & Destruction ------------------------------------------

fn alloc_window_slot(app: App&) -> WindowId {
    for i in app.windows.len {
        if !app.windows[i].alive {
            var next_gen = app.windows[i].gen + 1;
            if next_gen == 0 { next_gen = 1; }
            app.windows[i] = Window { alive: true, gen: next_gen };
            return WindowId { index: i as! i32, gen: next_gen };
        }
    }
    let idx = app.windows.len;
    app.windows.push(Window { alive: true, gen: 1 });
    return WindowId { index: idx as! i32, gen: 1 };
}

// Creates a top-level Win32 window using the specified rendering backend.
fn create_window_with_backend(
    app: App&,
    title: const u8[:],
    width: i32,
    height: i32,
    resizable: bool,
    backend: RenderBackend
) -> WindowId {
    if !app.initialized { app.init(true, backend); }

    let style = if resizable {
        win32::WS_OVERLAPPEDWINDOW
    } else {
        win32::WS_OVERLAPPED | win32::WS_CAPTION | win32::WS_SYSMENU | win32::WS_MINIMIZEBOX
    };

    let hwnd = win32::create_window(title, width, height, style);
    guard hwnd.is_valid() else { return WINDOW_NONE; }

    hwnd.set_dark_titlebar(app.theme.is_dark);
    hwnd.set_corner_preference(win32::DWMWCP_ROUND);

    var d2d = win32::D2dTarget {};
    var fonts = FontSet {};
    var gdi_fonts = GdiFontSet {};

    match backend {
        Direct2D => {
            d2d = win32::d2d_create(hwnd, true);
            guard d2d.is_valid() else {
                hwnd.destroy();
                return WINDOW_NONE;
            }
            fonts = create_window_fonts(d2d, app.theme);
        },
        Software => {
            gdi_fonts = create_gdi_fonts(app.theme);
        },
    }

    let wid = alloc_window_slot(app);
    let rc = hwnd.client_rect();
    let cw = if rc.width() > 0 { rc.width() } else { width };
    let ch = if rc.height() > 0 { rc.height() } else { height };

    str_set(app.str_pool, app.windows[wid.index].title, title);
    app.windows[wid.index].headless = false;
    app.windows[wid.index].backend = backend;
    app.windows[wid.index].hwnd = hwnd;
    app.windows[wid.index].d2d = d2d;
    app.windows[wid.index].fonts = fonts;
    app.windows[wid.index].gdi_fonts = gdi_fonts;
    app.windows[wid.index].width = cw;
    app.windows[wid.index].height = ch;
    app.windows[wid.index].dpi = hwnd.dpi();
    app.windows[wid.index].visible = false;
    app.windows[wid.index].dirty = true;
    app.windows[wid.index].layout_dirty = true;

    let root_id = alloc_widget(app, WidgetKind.Panel, wid);
    app.widgets[root_id.index].layout = LayoutKind.VBox;
    app.widgets[root_id.index].spacing = 0.0;
    app.widgets[root_id.index].policy_h = SizePolicy.Expanding;
    app.widgets[root_id.index].policy_v = SizePolicy.Expanding;
    app.windows[wid.index].root_widget = root_id;

    return wid;
}

// Creates a top-level Win32 window inheriting `app.backend` (Direct2D or Software GDI).
fn create_window(
    app: App&,
    title: const u8[:],
    width: i32 = 960,
    height: i32 = 640,
    resizable: bool = true
) -> WindowId {
    return app.create_window_with_backend(title, width, height, resizable, app.backend);
}

// Creates a headless virtual window (no Win32 HWND/GPU) for automated testing.
fn create_headless_window(app: App&, title: const u8[:], width: i32 = 800, height: i32 = 600) -> WindowId {
    if !app.initialized {
        app.theme = theme_dark();
        app.initialized = true;
    }
    let wid = alloc_window_slot(app);
    str_set(app.str_pool, app.windows[wid.index].title, title);
    app.windows[wid.index].headless = true;
    app.windows[wid.index].backend = RenderBackend.Software;
    app.windows[wid.index].width = width;
    app.windows[wid.index].height = height;
    app.windows[wid.index].visible = true;
    app.windows[wid.index].dirty = true;
    app.windows[wid.index].layout_dirty = true;

    let root_id = alloc_widget(app, WidgetKind.Panel, wid);
    app.widgets[root_id.index].layout = LayoutKind.VBox;
    app.widgets[root_id.index].spacing = 0.0;
    app.widgets[root_id.index].policy_h = SizePolicy.Expanding;
    app.widgets[root_id.index].policy_v = SizePolicy.Expanding;
    app.windows[wid.index].root_widget = root_id;

    return wid;
}

fn root(app: const App&, win: WindowId) -> WidgetId {
    guard app.valid_window(win) else { return WIDGET_NONE; }
    return app.windows[win.index].root_widget;
}

fn hwnd(app: const App&, win: WindowId) -> win32::Hwnd {
    guard app.valid_window(win) else { return win32::Hwnd {}; }
    return app.windows[win.index].hwnd;
}

fn show_window(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    app.windows[win.index].visible = true;
    app.windows[win.index].layout_dirty = true;
    app.windows[win.index].dirty = true;
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.show(win32::SW_SHOW);
        app.windows[win.index].hwnd.update();
    }
}

fn hide_window(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    app.windows[win.index].visible = false;
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.show(win32::SW_HIDE);
    }
}

fn set_window_title(app: App&, win: WindowId, title: const u8[:]) {
    guard app.valid_window(win) else { return; }
    str_set(app.str_pool, app.windows[win.index].title, title);
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.set_title(title);
    }
}

fn set_auto_close(app: App&, win: WindowId, enabled: bool) {
    guard app.valid_window(win) else { return; }
    app.windows[win.index].auto_close = enabled;
}

fn enable_drop_files(app: App&, win: WindowId, enabled: bool = true) {
    guard app.valid_window(win) else { return; }
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.accept_drop_files(enabled);
    }
}

fn close_window(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }

    cancel_tooltip_timer(app, win);
    for i in app.timers.len {
        if app.timers[i].alive && eq(app.timers[i].window, win) {
            if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
                app.windows[win.index].hwnd.kill_timer(app.timers[i].timer_id);
            }
            app.timers[i].alive = false;
        }
    }

    let root_id = app.windows[win.index].root_widget;
    if app.valid_widget(root_id) {
        destroy_widget_subtree(app, root_id);
    }
    let sb = app.windows[win.index].status_bar;
    if app.valid_widget(sb) {
        destroy_widget_subtree(app, sb);
    }
    compact_list_items(app);
    compact_connections(app);

    if !app.windows[win.index].headless {
        destroy_window_fonts(app.windows[win.index].fonts);
        destroy_gdi_fonts(app.windows[win.index].gdi_fonts);
        if app.windows[win.index].d2d.is_valid() {
            app.windows[win.index].d2d.destroy();
            app.windows[win.index].d2d = win32::D2dTarget {};
        }
        let had_hwnd = app.windows[win.index].hwnd.is_valid();
        if had_hwnd {
            // DestroyWindow automatically destroys any menu bar attached via SetMenu.
            app.windows[win.index].hwnd.destroy();
            app.windows[win.index].hwnd = win32::Hwnd {};
            app.windows[win.index].menu_bar = win32::Hmenu {};
        } else if app.windows[win.index].menu_bar.is_valid() {
            app.windows[win.index].menu_bar.destroy();
            app.windows[win.index].menu_bar = win32::Hmenu {};
        }
    }

    app.windows[win.index].alive = false;
    if app.quit_on_last_window_closed && app.active_window_count() == 0 {
        app.running = false;
    }
}

fn quit(app: App&) {
    app.running = false;
}

fn destroy_all(app: App&) {
    for i in app.windows.len {
        if app.windows[i].alive {
            let wid = WindowId { index: i as! i32, gen: app.windows[i].gen };
            app.close_window(wid);
        }
    }
}

// --- Widget Factory Constructors (Qt-inspired API) --------------------------

fn add_panel(app: App&, parent: WidgetId, layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 0.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Panel, app.widgets[parent.index].window);
    app.widgets[id.index].layout = layout;
    app.widgets[id.index].spacing = spacing;
    app.widgets[id.index].padding = margins(padding);
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Preferred;
    attach_child(app, parent, id);
    return id;
}

fn add_vbox(app: App&, parent: WidgetId, spacing: f32 = 8.0, padding: f32 = 0.0) -> WidgetId {
    return app.add_panel(parent, LayoutKind.VBox, spacing, padding);
}

fn add_hbox(app: App&, parent: WidgetId, spacing: f32 = 8.0, padding: f32 = 0.0) -> WidgetId {
    return app.add_panel(parent, LayoutKind.HBox, spacing, padding);
}

fn add_grid(app: App&, parent: WidgetId, columns: i32 = 2, spacing: f32 = 8.0, padding: f32 = 0.0) -> WidgetId {
    let id = app.add_panel(parent, LayoutKind.Grid, spacing, padding);
    if app.valid_widget(id) {
        app.widgets[id.index].grid_cols = if columns > 0 { columns } else { 1 };
    }
    return id;
}

fn add_form(app: App&, parent: WidgetId, label_width: f32 = 130.0, spacing: f32 = 10.0, padding: f32 = 0.0) -> WidgetId {
    let id = app.add_panel(parent, LayoutKind.Form, spacing, padding);
    if app.valid_widget(id) {
        app.widgets[id.index].form_label_width = label_width;
    }
    return id;
}

fn add_stack(app: App&, parent: WidgetId, padding: f32 = 0.0) -> WidgetId {
    let id = app.add_panel(parent, LayoutKind.Stack, 0.0, padding);
    if app.valid_widget(id) {
        app.widgets[id.index].selected_index = 0;
        app.widgets[id.index].policy_v = SizePolicy.Expanding;
    }
    return id;
}

fn add_frame(app: App&, parent: WidgetId, layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 12.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Frame, app.widgets[parent.index].window);
    app.widgets[id.index].layout = layout;
    app.widgets[id.index].spacing = spacing;
    app.widgets[id.index].padding = margins(padding);
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Preferred;
    attach_child(app, parent, id);
    return id;
}

fn add_group_box(app: App&, parent: WidgetId, title: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 12.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.GroupBox, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, title);
    app.widgets[id.index].layout = layout;
    app.widgets[id.index].spacing = spacing;
    app.widgets[id.index].padding = margins(padding);
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Preferred;
    attach_child(app, parent, id);
    return id;
}

fn add_spacer(app: App&, parent: WidgetId, stretch: f32 = 1.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Spacer, app.widgets[parent.index].window);
    app.widgets[id.index].stretch = stretch;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    attach_child(app, parent, id);
    return id;
}

fn add_separator(app: App&, parent: WidgetId, orientation: Orientation = Orientation.Horizontal) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Separator, app.widgets[parent.index].window);
    app.widgets[id.index].orientation = orientation;
    match orientation {
        Horizontal => {
            app.widgets[id.index].policy_h = SizePolicy.Expanding;
            app.widgets[id.index].policy_v = SizePolicy.Fixed;
            app.widgets[id.index].fixed_h = 9.0;
        },
        Vertical => {
            app.widgets[id.index].policy_h = SizePolicy.Fixed;
            app.widgets[id.index].policy_v = SizePolicy.Expanding;
            app.widgets[id.index].fixed_w = 9.0;
        },
    }
    attach_child(app, parent, id);
    return id;
}

fn add_label(app: App&, parent: WidgetId, text: const u8[:], role: FontRole = FontRole.Body) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Label, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, text);
    app.widgets[id.index].font_role = role;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_button(app: App&, parent: WidgetId, text: const u8[:], variant: ButtonVariant = ButtonVariant.Default) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Button, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, text);
    app.widgets[id.index].variant = variant;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    app.widgets[id.index].text_align_h = Align.Center;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_checkbox(app: App&, parent: WidgetId, text: const u8[:], checked: bool = false) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.CheckBox, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, text);
    app.widgets[id.index].checked = checked;
    app.widgets[id.index].checkable = true;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_radio_button(app: App&, parent: WidgetId, text: const u8[:], checked: bool = false) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.RadioButton, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, text);
    app.widgets[id.index].checked = checked;
    app.widgets[id.index].checkable = true;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    if checked {
        var sib = app.widgets[parent.index].first_child;
        while app.valid_widget(sib) {
            if !eq(sib, id) {
                match app.widgets[sib.index].kind {
                    RadioButton => { app.widgets[sib.index].checked = false; },
                    _ => {},
                }
            }
            sib = app.widgets[sib.index].next_sibling;
        }
    }
    return id;
}

fn add_toggle_switch(app: App&, parent: WidgetId, text: const u8[:], checked: bool = false) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.ToggleSwitch, app.widgets[parent.index].window);
    str_set(app.str_pool, app.widgets[id.index].text, text);
    app.widgets[id.index].checked = checked;
    app.widgets[id.index].checkable = true;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_line_edit(app: App&, parent: WidgetId, placeholder: const u8[:] = "", initial_text: const u8[:] = "") -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.LineEdit, app.widgets[parent.index].window);
    if placeholder.len > 0 {
        str_set(app.str_pool, app.widgets[id.index].placeholder, placeholder);
    }
    if initial_text.len > 0 {
        str_set(app.str_pool, app.widgets[id.index].text, initial_text);
    }
    let n = app.widgets[id.index].text.len;
    app.widgets[id.index].caret = n;
    app.widgets[id.index].sel_anchor = n;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.IBeam;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_slider(
    app: App&,
    parent: WidgetId,
    min_val: f64 = 0.0,
    max_val: f64 = 100.0,
    initial: f64 = 0.0,
    step: f64 = 1.0,
    orientation: Orientation = Orientation.Horizontal
) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Slider, app.widgets[parent.index].window);
    app.widgets[id.index].min_value = min_val;
    app.widgets[id.index].max_value = if max_val > min_val { max_val } else { min_val + 1.0 };
    app.widgets[id.index].value = clamp_f64(initial, min_val, app.widgets[id.index].max_value);
    app.widgets[id.index].step = if step > 0.0 { step } else { 1.0 };
    app.widgets[id.index].orientation = orientation;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    match orientation {
        Horizontal => {
            app.widgets[id.index].policy_h = SizePolicy.Expanding;
            app.widgets[id.index].policy_v = SizePolicy.Fixed;
        },
        Vertical => {
            app.widgets[id.index].policy_h = SizePolicy.Fixed;
            app.widgets[id.index].policy_v = SizePolicy.Expanding;
        },
    }
    attach_child(app, parent, id);
    return id;
}

fn add_spin_box(
    app: App&,
    parent: WidgetId,
    min_val: f64 = 0.0,
    max_val: f64 = 100.0,
    initial: f64 = 0.0,
    step: f64 = 1.0,
    decimals: i32 = 0
) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.SpinBox, app.widgets[parent.index].window);
    app.widgets[id.index].min_value = min_val;
    app.widgets[id.index].max_value = if max_val > min_val { max_val } else { min_val + 1.0 };
    app.widgets[id.index].value = clamp_f64(initial, min_val, app.widgets[id.index].max_value);
    app.widgets[id.index].step = if step > 0.0 { step } else { 1.0 };
    app.widgets[id.index].decimals = decimals;
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].policy_h = SizePolicy.Preferred;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_progress_bar(app: App&, parent: WidgetId, min_val: f64 = 0.0, max_val: f64 = 100.0, initial: f64 = 0.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.ProgressBar, app.widgets[parent.index].window);
    app.widgets[id.index].min_value = min_val;
    app.widgets[id.index].max_value = if max_val > min_val { max_val } else { min_val + 1.0 };
    app.widgets[id.index].value = clamp_f64(initial, min_val, app.widgets[id.index].max_value);
    app.widgets[id.index].show_percentage = true;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_combo_box(app: App&, parent: WidgetId) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.ComboBox, app.widgets[parent.index].window);
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].cursor = CursorShape.Hand;
    app.widgets[id.index].selected_index = -1;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Fixed;
    attach_child(app, parent, id);
    return id;
}

fn add_list_view(app: App&, parent: WidgetId, item_height: f32 = 30.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.ListView, app.widgets[parent.index].window);
    app.widgets[id.index].focusable = true;
    app.widgets[id.index].item_height = if item_height >= 20.0 { item_height } else { 20.0 };
    app.widgets[id.index].selected_index = -1;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    app.widgets[id.index].min_size = SizeF { w: 120.0, h: 100.0 };
    attach_child(app, parent, id);
    return id;
}

fn add_tab_widget(app: App&, parent: WidgetId) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.TabWidget, app.widgets[parent.index].window);
    app.widgets[id.index].selected_index = 0;
    app.widgets[id.index].tab_bar_height = 36.0;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    app.widgets[id.index].padding = margins(12.0);
    attach_child(app, parent, id);
    return id;
}

fn add_tab(app: App&, tab_widget: WidgetId, title: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 10.0, padding: f32 = 12.0) -> WidgetId {
    guard app.valid_widget(tab_widget) else { return WIDGET_NONE; }
    let page = alloc_widget(app, WidgetKind.Panel, app.widgets[tab_widget.index].window);
    app.widgets[page.index].layout = layout;
    app.widgets[page.index].spacing = spacing;
    app.widgets[page.index].padding = margins(padding);
    app.widgets[page.index].policy_h = SizePolicy.Expanding;
    app.widgets[page.index].policy_v = SizePolicy.Expanding;
    attach_child(app, tab_widget, page);

    var item = ListItem { alive: true, owner: tab_widget, page: page };
    str_set(app.str_pool, item.text, title);
    app.list_items.push(item);

    if app.widgets[tab_widget.index].selected_index < 0 {
        app.widgets[tab_widget.index].selected_index = 0;
    }
    app.mark_widget_layout_dirty(tab_widget);
    return page;
}

fn add_scroll_area(app: App&, parent: WidgetId, spacing: f32 = 8.0, padding: f32 = 10.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.ScrollArea, app.widgets[parent.index].window);
    app.widgets[id.index].layout = LayoutKind.VBox;
    app.widgets[id.index].spacing = spacing;
    app.widgets[id.index].padding = margins(padding);
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    app.widgets[id.index].min_size = SizeF { w: 100.0, h: 80.0 };
    attach_child(app, parent, id);
    return id;
}

fn add_splitter(app: App&, parent: WidgetId, orientation: Orientation = Orientation.Horizontal, ratio: f32 = 0.35) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Splitter, app.widgets[parent.index].window);
    app.widgets[id.index].orientation = orientation;
    app.widgets[id.index].split_ratio = clamp_f32(ratio, 0.1, 0.9);
    app.widgets[id.index].splitter_size = 7.0;
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    attach_child(app, parent, id);
    return id;
}

fn set_status_bar(app: App&, win: WindowId, initial_text: const u8[:] = "Ready") -> WidgetId {
    guard app.valid_window(win) else { return WIDGET_NONE; }
    let existing = app.windows[win.index].status_bar;
    if app.valid_widget(existing) {
        str_set(app.str_pool, app.widgets[existing.index].text, initial_text);
        app.mark_dirty(win);
        return existing;
    }
    let id = alloc_widget(app, WidgetKind.StatusBar, win);
    str_set(app.str_pool, app.widgets[id.index].text, initial_text);
    app.widgets[id.index].font_role = FontRole.Caption;
    app.widgets[id.index].fixed_h = 26.0;
    app.windows[win.index].status_bar = id;
    app.mark_layout_dirty(win);
    return id;
}

fn set_status_text(app: App&, win: WindowId, text: const u8[:]) {
    guard app.valid_window(win) else { return; }
    let sb = app.windows[win.index].status_bar;
    guard app.valid_widget(sb) else { return; }
    str_set(app.str_pool, app.widgets[sb.index].text, text, 64);
    app.mark_dirty(win);
}

fn add_canvas(app: App&, parent: WidgetId, min_w: f32 = 200.0, min_h: f32 = 160.0) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let id = alloc_widget(app, WidgetKind.Canvas, app.widgets[parent.index].window);
    app.widgets[id.index].min_size = SizeF { w: min_w, h: min_h };
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    app.widgets[id.index].focusable = true;
    attach_child(app, parent, id);
    return id;
}

// --- Property Setters & Getters ---------------------------------------------

fn set_name(app: App&, id: WidgetId, name: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    str_set(app.str_pool, app.widgets[id.index].name, name);
}

fn set_tag(app: App&, id: WidgetId, tag: i64) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].tag = tag;
}

fn tag(app: const App&, id: WidgetId) -> i64 {
    guard app.valid_widget(id) else { return 0; }
    return app.widgets[id.index].tag;
}

fn find_by_name(app: const App&, win: WindowId, name: const u8[:]) -> WidgetId {
    for i in app.widgets.len {
        if app.widgets[i].alive && eq(app.widgets[i].window, win) && app.str_view(app.widgets[i].name) == name {
            return WidgetId { index: i as! i32, gen: app.widgets[i].gen };
        }
    }
    return WIDGET_NONE;
}

// Win32-style integer control ID (tag) lookup & convenience accessors.
fn by_id(app: const App&, win: WindowId, control_id: i64) -> WidgetId {
    for i in app.widgets.len {
        if app.widgets[i].alive && eq(app.widgets[i].window, win) && app.widgets[i].tag == control_id {
            return WidgetId { index: i as! i32, gen: app.widgets[i].gen };
        }
    }
    return WIDGET_NONE;
}

fn action_id(app: const App&, id: WidgetId) -> i64 {
    return app.tag(id);
}

fn text_of(app: const App&, win: WindowId, control_id: i64) -> const u8[:] {
    return app.text(app.by_id(win, control_id));
}

fn set_text_of(app: App&, win: WindowId, control_id: i64, value: const u8[:]) {
    app.set_text(app.by_id(win, control_id), value);
}

fn value_of(app: const App&, win: WindowId, control_id: i64) -> f64 {
    return app.value(app.by_id(win, control_id));
}

fn set_value_of(app: App&, win: WindowId, control_id: i64, v: f64) {
    app.set_value(app.by_id(win, control_id), v);
}

fn checked_of(app: const App&, win: WindowId, control_id: i64) -> bool {
    return app.is_checked(app.by_id(win, control_id));
}

fn set_checked_of(app: App&, win: WindowId, control_id: i64, c: bool) {
    app.set_checked(app.by_id(win, control_id), c);
}

// Sets Win32/WinForms-style absolute bounds and resize anchor inside a LayoutKind.None container.
fn set_bounds(
    app: App&,
    id: WidgetId,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    anchor: u8 = ANCHOR_TOP_LEFT,
    ref_w: f32 = 0.0,
    ref_h: f32 = 0.0
) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].abs_rect = RectF { x, y, w, h };
    app.widgets[id.index].anchor = anchor;
    app.widgets[id.index].has_abs_bounds = true;
    // When ref_w / ref_h <= 0, the layout engine captures the parent's initial inner size lazily.
    app.widgets[id.index].abs_ref = SizeF {
        w: if ref_w > 0.0 { ref_w } else { 0.0 },
        h: if ref_h > 0.0 { ref_h } else { 0.0 },
    };
    app.mark_widget_layout_dirty(id);
}

fn set_layout(app: App&, id: WidgetId, layout: LayoutKind) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].layout = layout;
    app.mark_widget_layout_dirty(id);
}

fn set_text(app: App&, id: WidgetId, text: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    str_set(app.str_pool, app.widgets[id.index].text, text);
    let n = app.widgets[id.index].text.len;
    app.widgets[id.index].caret = n;
    app.widgets[id.index].sel_anchor = n;
    app.mark_widget_layout_dirty(id);
}

fn text(app: const App&, id: WidgetId) -> const u8[:] {
    guard app.valid_widget(id) else { return ""; }
    return app.str_view(app.widgets[id.index].text);
}

fn set_placeholder(app: App&, id: WidgetId, text: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    str_set(app.str_pool, app.widgets[id.index].placeholder, text);
    app.mark_widget_dirty(id);
}

fn set_tooltip(app: App&, id: WidgetId, text: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    str_set(app.str_pool, app.widgets[id.index].tooltip, text);
}

fn set_visible(app: App&, id: WidgetId, visible: bool) {
    guard app.valid_widget(id) else { return; }
    if app.widgets[id.index].visible != visible {
        app.widgets[id.index].visible = visible;
        if !visible {
            clear_window_refs_in_subtree(app, id);
        }
        app.mark_widget_layout_dirty(id);
    }
}

fn is_visible(app: const App&, id: WidgetId) -> bool {
    guard app.valid_widget(id) else { return false; }
    return app.widgets[id.index].visible;
}

fn set_enabled(app: App&, id: WidgetId, enabled: bool) {
    guard app.valid_widget(id) else { return; }
    if app.widgets[id.index].enabled != enabled {
        app.widgets[id.index].enabled = enabled;
        if !enabled {
            clear_window_refs_in_subtree(app, id);
        }
        app.mark_widget_dirty(id);
    }
}

fn is_enabled(app: const App&, id: WidgetId) -> bool {
    guard app.valid_widget(id) else { return false; }
    return app.widgets[id.index].enabled;
}

fn set_checkable(app: App&, id: WidgetId, checkable: bool) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].checkable = checkable;
    app.mark_widget_dirty(id);
}

fn set_checked(app: App&, id: WidgetId, checked: bool) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].checked = checked;
    match app.widgets[id.index].kind {
        RadioButton => {
            if checked {
                let p = app.widgets[id.index].parent;
                if app.valid_widget(p) {
                    var sib = app.widgets[p.index].first_child;
                    while app.valid_widget(sib) {
                        if !eq(sib, id) {
                            match app.widgets[sib.index].kind {
                                RadioButton => { app.widgets[sib.index].checked = false; },
                                _ => {},
                            }
                        }
                        sib = app.widgets[sib.index].next_sibling;
                    }
                }
            }
        },
        _ => {},
    }
    app.mark_widget_dirty(id);
}

fn is_checked(app: const App&, id: WidgetId) -> bool {
    guard app.valid_widget(id) else { return false; }
    return app.widgets[id.index].checked;
}

fn set_value(app: App&, id: WidgetId, value: f64) {
    guard app.valid_widget(id) else { return; }
    let clamped = clamp_f64(value, app.widgets[id.index].min_value, app.widgets[id.index].max_value);
    app.widgets[id.index].value = clamped;
    app.mark_widget_dirty(id);
}

fn value(app: const App&, id: WidgetId) -> f64 {
    guard app.valid_widget(id) else { return 0.0; }
    return app.widgets[id.index].value;
}

fn set_range(app: App&, id: WidgetId, min_val: f64, max_val: f64) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].min_value = min_val;
    app.widgets[id.index].max_value = if max_val > min_val { max_val } else { min_val + 1.0 };
    app.widgets[id.index].value = clamp_f64(app.widgets[id.index].value, min_val, app.widgets[id.index].max_value);
    app.mark_widget_dirty(id);
}

fn set_password_mode(app: App&, id: WidgetId, enabled: bool) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].password_mode = enabled;
    app.mark_widget_dirty(id);
}

fn set_read_only(app: App&, id: WidgetId, ro: bool) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].read_only = ro;
    app.mark_widget_dirty(id);
}

fn set_show_percentage(app: App&, id: WidgetId, show: bool) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].show_percentage = show;
    app.mark_widget_dirty(id);
}

fn set_button_variant(app: App&, id: WidgetId, variant: ButtonVariant) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].variant = variant;
    app.mark_widget_dirty(id);
}

// --- Layout Property Setters ------------------------------------------------

fn set_stretch(app: App&, id: WidgetId, stretch: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].stretch = if stretch >= 0.0 { stretch } else { 0.0 };
    app.mark_widget_layout_dirty(id);
}

fn set_spacing(app: App&, id: WidgetId, spacing: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].spacing = spacing;
    app.mark_widget_layout_dirty(id);
}

fn set_padding(app: App&, id: WidgetId, m: Margins) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].padding = m;
    app.mark_widget_layout_dirty(id);
}

fn set_padding(app: App&, id: WidgetId, all: f32) {
    app.set_padding(id, margins(all));
}

fn set_fixed_size(app: App&, id: WidgetId, w: f32, h: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].fixed_w = w;
    app.widgets[id.index].fixed_h = h;
    if w >= 0.0 { app.widgets[id.index].policy_h = SizePolicy.Fixed; }
    if h >= 0.0 { app.widgets[id.index].policy_v = SizePolicy.Fixed; }
    app.mark_widget_layout_dirty(id);
}

fn set_fixed_width(app: App&, id: WidgetId, w: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].fixed_w = w;
    if w >= 0.0 { app.widgets[id.index].policy_h = SizePolicy.Fixed; }
    app.mark_widget_layout_dirty(id);
}

fn set_fixed_height(app: App&, id: WidgetId, h: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].fixed_h = h;
    if h >= 0.0 { app.widgets[id.index].policy_v = SizePolicy.Fixed; }
    app.mark_widget_layout_dirty(id);
}

fn set_min_size(app: App&, id: WidgetId, w: f32, h: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].min_size = SizeF { w, h };
    app.mark_widget_layout_dirty(id);
}

fn set_max_size(app: App&, id: WidgetId, w: f32, h: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].max_size = SizeF { w, h };
    app.mark_widget_layout_dirty(id);
}

fn set_size_policy(app: App&, id: WidgetId, h: SizePolicy, v: SizePolicy) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].policy_h = h;
    app.widgets[id.index].policy_v = v;
    app.mark_widget_layout_dirty(id);
}

fn set_align(app: App&, id: WidgetId, h: Align, v: Align = Align.Stretch) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].align_h = h;
    app.widgets[id.index].align_v = v;
    app.mark_widget_layout_dirty(id);
}

fn set_text_align(app: App&, id: WidgetId, h: Align, v: Align = Align.Center) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].text_align_h = h;
    app.widgets[id.index].text_align_v = v;
    app.mark_widget_dirty(id);
}

fn set_font_role(app: App&, id: WidgetId, role: FontRole) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].font_role = role;
    app.mark_widget_layout_dirty(id);
}

fn set_bg(app: App&, id: WidgetId, color: Color) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].style.flags |= STYLE_HAS_BG;
    app.widgets[id.index].style.bg_rgba = pack_rgba(color);
    app.mark_widget_dirty(id);
}

fn set_fg(app: App&, id: WidgetId, color: Color) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].style.flags |= STYLE_HAS_FG;
    app.widgets[id.index].style.fg_rgba = pack_rgba(color);
    app.mark_widget_dirty(id);
}

fn set_border(app: App&, id: WidgetId, color: Color, width: f32 = 1.0) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].style.flags |= STYLE_HAS_BORDER;
    app.widgets[id.index].style.border_rgba = pack_rgba(color);
    app.widgets[id.index].style.border_width = width;
    app.mark_widget_dirty(id);
}

fn set_radius(app: App&, id: WidgetId, radius: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].style.flags |= STYLE_HAS_RADIUS;
    app.widgets[id.index].style.radius = radius;
    app.mark_widget_dirty(id);
}

fn set_split_ratio(app: App&, id: WidgetId, ratio: f32) {
    guard app.valid_widget(id) else { return; }
    app.widgets[id.index].split_ratio = clamp_f32(ratio, 0.1, 0.9);
    app.mark_widget_layout_dirty(id);
}

fn widget_rect(app: const App&, id: WidgetId) -> RectF {
    guard app.valid_widget(id) else { return RectF {}; }
    return app.widgets[id.index].rect;
}

// --- ListView / ComboBox / TabWidget Item Management ------------------------

fn item_count(app: const App&, owner: WidgetId) -> i32 {
    guard app.valid_widget(owner) else { return 0; }
    var n: i32 = 0;
    for i in app.list_items.len {
        if app.list_items[i].alive && eq(app.list_items[i].owner, owner) {
            n += 1;
        }
    }
    return n;
}

fn find_nth_item(app: const App&, owner: WidgetId, nth: i32) -> i64 {
    if nth < 0 { return -1; }
    var cur: i32 = 0;
    for i in app.list_items.len {
        if app.list_items[i].alive && eq(app.list_items[i].owner, owner) {
            if cur == nth { return i; }
            cur += 1;
        }
    }
    return -1;
}

fn add_item(app: App&, owner: WidgetId, text: const u8[:], subtext: const u8[:] = "", tag: i64 = 0) -> i32 {
    guard app.valid_widget(owner) else { return -1; }
    let idx = app.item_count(owner);
    var item = ListItem { alive: true, owner: owner, tag: tag };
    str_set(app.str_pool, item.text, text);
    if subtext.len > 0 {
        str_set(app.str_pool, item.subtext, subtext);
    }
    app.list_items.push(item);

    match app.widgets[owner.index].kind {
        ComboBox => {
            if app.widgets[owner.index].selected_index < 0 {
                app.widgets[owner.index].selected_index = 0;
            }
        },
        _ => {},
    }
    app.mark_widget_layout_dirty(owner);
    return idx;
}

fn clear_items(app: App&, owner: WidgetId) {
    guard app.valid_widget(owner) else { return; }
    let is_tabs = match app.widgets[owner.index].kind { TabWidget => true, _ => false };
    for i in app.list_items.len {
        if app.list_items[i].alive && eq(app.list_items[i].owner, owner) {
            let page = app.list_items[i].page;
            app.list_items[i].alive = false;
            if is_tabs && app.valid_widget(page) {
                detach_from_parent(app, page);
                destroy_widget_subtree(app, page);
            }
        }
    }
    app.widgets[owner.index].selected_index = -1;
    app.widgets[owner.index].hovered_item = -1;
    app.widgets[owner.index].scroll_y = 0.0;
    app.widgets[owner.index].scroll_max_y = 0.0;
    let win = app.widgets[owner.index].window;
    if app.valid_window(win) && eq(app.windows[win.index].open_combo, owner) {
        app.windows[win.index].open_combo = WIDGET_NONE;
        app.windows[win.index].open_combo_hover = -1;
        app.windows[win.index].open_combo_scroll = 0;
    }
    compact_list_items(app);
    app.mark_widget_layout_dirty(owner);
}

fn remove_item(app: App&, owner: WidgetId, index: i32) -> bool {
    let slot = app.find_nth_item(owner, index);
    guard slot >= 0 else { return false; }
    let page = app.list_items[slot].page;
    let is_tabs = match app.widgets[owner.index].kind { TabWidget => true, _ => false };
    app.list_items[slot].alive = false;
    if is_tabs && app.valid_widget(page) {
        detach_from_parent(app, page);
        destroy_widget_subtree(app, page);
    }
    let cnt = app.item_count(owner);
    let sel = app.widgets[owner.index].selected_index;
    if cnt <= 0 {
        app.widgets[owner.index].selected_index = -1;
    } else if index < sel {
        app.widgets[owner.index].selected_index = sel - 1;
    } else if sel >= cnt {
        app.widgets[owner.index].selected_index = cnt - 1;
    }
    let hov = app.widgets[owner.index].hovered_item;
    if hov == index || cnt <= 0 {
        app.widgets[owner.index].hovered_item = -1;
    } else if index < hov {
        app.widgets[owner.index].hovered_item = hov - 1;
    } else if hov >= cnt {
        app.widgets[owner.index].hovered_item = -1;
    }
    let win = app.widgets[owner.index].window;
    if app.valid_window(win) && eq(app.windows[win.index].open_combo, owner) {
        if cnt <= 0 {
            app.windows[win.index].open_combo = WIDGET_NONE;
            app.windows[win.index].open_combo_hover = -1;
            app.windows[win.index].open_combo_scroll = 0;
        } else {
            let max_sc = if cnt > 8 { cnt - 8 } else { 0 };
            if app.windows[win.index].open_combo_scroll > max_sc {
                app.windows[win.index].open_combo_scroll = max_sc;
            }
            if app.windows[win.index].open_combo_hover >= cnt {
                app.windows[win.index].open_combo_hover = cnt - 1;
            }
        }
    }
    compact_list_items(app);
    app.mark_widget_layout_dirty(owner);
    return true;
}

fn item_text(app: const App&, owner: WidgetId, index: i32) -> const u8[:] {
    let slot = app.find_nth_item(owner, index);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.list_items[slot].text);
}

fn item_subtext(app: const App&, owner: WidgetId, index: i32) -> const u8[:] {
    let slot = app.find_nth_item(owner, index);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.list_items[slot].subtext);
}

fn item_tag(app: const App&, owner: WidgetId, index: i32) -> i64 {
    let slot = app.find_nth_item(owner, index);
    guard slot >= 0 else { return 0; }
    return app.list_items[slot].tag;
}

fn clear_inactive_page_refs(app: App&, container: WidgetId, prev_idx: i32, new_idx: i32) {
    if prev_idx == new_idx || prev_idx < 0 { return; }
    match app.widgets[container.index].kind {
        TabWidget => {
            let slot = app.find_nth_item(container, prev_idx);
            if slot >= 0 {
                let page = app.list_items[slot].page;
                if app.valid_widget(page) {
                    clear_window_refs_in_subtree(app, page);
                }
            }
        },
        Panel, Frame, GroupBox => {
            match app.widgets[container.index].layout {
                Stack => {
                    var ch = app.widgets[container.index].first_child;
                    var idx: i32 = 0;
                    while app.valid_widget(ch) {
                        if idx == prev_idx {
                            clear_window_refs_in_subtree(app, ch);
                            break;
                        }
                        ch = app.widgets[ch.index].next_sibling;
                        idx += 1;
                    }
                },
                _ => {},
            }
        },
        _ => {},
    }
}

fn set_selected_index(app: App&, id: WidgetId, index: i32) {
    guard app.valid_widget(id) else { return; }
    let prev = app.widgets[id.index].selected_index;
    let cnt = match app.widgets[id.index].kind {
        TabWidget, ComboBox, ListView => app.item_count(id),
        _ => app.widgets[id.index].child_count,
    };
    var next_sel: i32 = -1;
    if cnt <= 0 {
        next_sel = -1;
    } else if index < -1 {
        next_sel = -1;
    } else if index >= cnt {
        next_sel = cnt - 1;
    } else {
        next_sel = index;
    }
    app.widgets[id.index].selected_index = next_sel;
    clear_inactive_page_refs(app, id, prev, next_sel);
    app.mark_widget_layout_dirty(id);
}

fn selected_index(app: const App&, id: WidgetId) -> i32 {
    guard app.valid_widget(id) else { return -1; }
    return app.widgets[id.index].selected_index;
}

fn set_current_tab(app: App&, tab_widget: WidgetId, index: i32) {
    app.set_selected_index(tab_widget, index);
}

fn current_tab(app: const App&, tab_widget: WidgetId) -> i32 {
    return app.selected_index(tab_widget);
}

// --- Declarative Signal-to-Slot Connections (Qt connect) --------------------

fn connect(
    app: App&,
    sender: WidgetId,
    signal: SignalKind,
    receiver: WidgetId,
    slot: SlotAction,
    param_f64: f64 = 0.0
) {
    app.connections.push(Connection {
        sender: sender,
        signal: signal,
        receiver: receiver,
        slot: slot,
        param_f64: param_f64,
        alive: true,
    });
}

fn disconnect_all(app: App&, sender: WidgetId) {
    for i in app.connections.len {
        if app.connections[i].alive && eq(app.connections[i].sender, sender) {
            app.connections[i].alive = false;
        }
    }
    compact_connections(app);
}
