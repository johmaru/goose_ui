// Native Windows integrations: MenuBar, Context Menus, Common Dialogs,
// MessageBox, Clipboard, QTimer, DWM styling, and Drag & Drop files.
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import widget;
import tree;

// --- Native Menu Bar & Context Menus (QMenuBar / QMenu / QAction) -----------

fn create_menu_bar(app: App&, win: WindowId) -> MenuHandle {
    guard app.valid_window(win) else { return MenuHandle {}; }
    if app.windows[win.index].headless { return MenuHandle {}; }
    let bar = win32::create_menu();
    guard bar.is_valid() else { return MenuHandle {}; }
    let old_bar = app.windows[win.index].menu_bar;
    app.windows[win.index].hwnd.set_menu(bar);
    if old_bar.is_valid() {
        old_bar.destroy();
    }
    app.windows[win.index].menu_bar = bar;
    let rc = app.windows[win.index].hwnd.client_rect();
    if rc.width() > 0 && rc.height() > 0 {
        app.windows[win.index].width = rc.width();
        app.windows[win.index].height = rc.height();
        app.mark_layout_dirty(win);
    }
    return MenuHandle { raw: bar };
}

fn create_popup_menu() -> MenuHandle {
    return MenuHandle { raw: win32::create_popup_menu() };
}

fn add_submenu(parent: MenuHandle, title: const u8[:]) -> MenuHandle {
    guard parent.is_valid() else { return MenuHandle {}; }
    let sub = win32::create_popup_menu();
    guard sub.is_valid() else { return MenuHandle {}; }
    parent.raw.append_submenu(sub, title);
    return MenuHandle { raw: sub };
}

fn add_action(menu: MenuHandle, action_id: u32, text: const u8[:], enabled: bool = true, checked: bool = false) -> bool {
    guard menu.is_valid() else { return false; }
    var flags = win32::MF_STRING;
    if !enabled { flags |= win32::MF_GRAYED; }
    if checked { flags |= win32::MF_CHECKED; }
    return menu.raw.append_item(action_id, text, flags);
}

fn add_menu_separator(menu: MenuHandle) -> bool {
    guard menu.is_valid() else { return false; }
    return menu.raw.append_separator();
}

fn set_action_enabled(menu: MenuHandle, action_id: u32, enabled: bool) -> bool {
    guard menu.is_valid() else { return false; }
    return menu.raw.set_enabled(action_id, enabled);
}

fn set_action_checked(menu: MenuHandle, action_id: u32, checked: bool) -> bool {
    guard menu.is_valid() else { return false; }
    return menu.raw.set_checked(action_id, checked);
}

fn refresh_menu_bar(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.draw_menu_bar();
    }
}

fn show_context_menu(app: App&, win: WindowId, menu: MenuHandle, client_x: i32, client_y: i32) -> u32 {
    guard app.valid_window(win) && menu.is_valid() else { return 0; }
    if app.windows[win.index].headless { return 0; }
    return menu.raw.track_popup_client(app.windows[win.index].hwnd, client_x, client_y);
}

fn destroy_menu(menu: MenuHandle) {
    if menu.is_valid() { menu.raw.destroy(); }
}

// --- Native Message Boxes (QMessageBox) -------------------------------------

fn msg_info(app: const App&, win: WindowId, title: const u8[:], text: const u8[:]) {
    let owner = app.hwnd(win);
    win32::message_box(text, title, win32::MB_OK | win32::MB_ICONINFORMATION, owner);
}

fn msg_warning(app: const App&, win: WindowId, title: const u8[:], text: const u8[:]) {
    let owner = app.hwnd(win);
    win32::message_box(text, title, win32::MB_OK | win32::MB_ICONWARNING, owner);
}

fn msg_error(app: const App&, win: WindowId, title: const u8[:], text: const u8[:]) {
    let owner = app.hwnd(win);
    win32::message_box(text, title, win32::MB_OK | win32::MB_ICONERROR, owner);
}

fn msg_question(app: const App&, win: WindowId, title: const u8[:], text: const u8[:]) -> bool {
    let owner = app.hwnd(win);
    return win32::message_box(text, title, win32::MB_YESNO | win32::MB_ICONQUESTION, owner) == win32::IDYES;
}

// --- Native File, Folder, Color & Input Dialogs (QFileDialog / QColorDialog / QInputDialog)

fn open_file_dialog(
    app: const App&,
    win: WindowId,
    out_path: u8[>..]&,
    title: const u8[:] = "Open File",
    filter: const u8[:] = "All Files (*.*)|*.*",
    default_ext: const u8[:] = ""
) -> bool {
    return win32::open_file_dialog(out_path, app.hwnd(win), title, filter, default_ext);
}

fn save_file_dialog(
    app: const App&,
    win: WindowId,
    out_path: u8[>..]&,
    title: const u8[:] = "Save File",
    filter: const u8[:] = "All Files (*.*)|*.*",
    default_ext: const u8[:] = "",
    initial_name: const u8[:] = ""
) -> bool {
    return win32::save_file_dialog(out_path, app.hwnd(win), title, filter, default_ext, initial_name);
}

fn select_folder_dialog(
    app: const App&,
    win: WindowId,
    out_path: u8[>..]&,
    title: const u8[:] = "Select Folder"
) -> bool {
    return win32::browse_folder_dialog(out_path, app.hwnd(win), title);
}

fn choose_color_dialog(app: const App&, win: WindowId, color: Color&) -> bool {
    var cr = to_colorref(color);
    guard win32::choose_color_dialog(cr, app.hwnd(win)) else { return false; }
    color = from_colorref(cr);
    return true;
}

fn input_dialog(
    app: const App&,
    win: WindowId,
    out_text: u8[>..]&,
    title: const u8[:] = "Input",
    prompt: const u8[:] = "Enter text:",
    initial_text: const u8[:] = ""
) -> bool {
    return win32::input_box(out_text, app.hwnd(win), title, prompt, initial_text);
}

// --- Clipboard (QClipboard) -------------------------------------------------

fn clipboard_text() -> u8[>..] {
    return win32::clipboard_get_text();
}

fn set_clipboard_text(text: const u8[:]) -> bool {
    return win32::clipboard_set_text(text);
}

// --- Timers (QTimer) --------------------------------------------------------

fn start_timer(app: App&, win: WindowId, interval_ms: u32, single_shot: bool = false) -> u64 {
    guard app.valid_window(win) else { return 0; }
    let tid = app.next_timer_id;
    app.next_timer_id += 1;
    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        app.windows[win.index].hwnd.set_timer(tid, interval_ms);
    }
    let info = TimerInfo {
        alive: true,
        window: win,
        timer_id: tid,
        interval_ms: interval_ms,
        single_shot: single_shot,
    };
    for i in app.timers.len {
        if !app.timers[i].alive {
            app.timers[i] = info;
            return tid;
        }
    }
    app.timers.push(info);
    return tid;
}

fn stop_timer(app: App&, timer_id: u64) {
    for i in app.timers.len {
        if app.timers[i].alive && app.timers[i].timer_id == timer_id {
            let win = app.timers[i].window;
            if app.valid_window(win) && !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
                app.windows[win.index].hwnd.kill_timer(timer_id);
            }
            app.timers[i].alive = false;
            return;
        }
    }
}

// --- Drag & Drop Dropped Files Accessors ------------------------------------

fn dropped_file_count() -> i32 {
    return win32::dropped_file_count();
}

fn dropped_file_path(index: i32) -> u8[>..] {
    var out: u8[>..] = [];
    win32::dropped_file_path(index, out);
    return out;
}
