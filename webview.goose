// Pure-Goose WebView2 widget wrapper, sparse App state management, layout/clip sync,
// JS<->Goose bridge payloads, and headless synthetic event injection.
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import theme;
import widget;
import tree;
import log;

// --- Availability & Runtime Discovery ---------------------------------------

fn webview_is_available() -> bool {
    return win32::webview_is_available();
}

fn webview_runtime_version() -> u8[>..] {
    return win32::webview_runtime_version();
}

fn set_webview_user_data_dir(app: App&, dir: const u8[:]) {
    str_set(app.str_pool, app.webview_default_data_dir, dir);
}

// --- Internal Helpers -------------------------------------------------------

fn wv_policy_code(p: WebViewNewWindowPolicy) -> i32 {
    return match p {
        BlockAndNotify => win32::WV_NEWWIN_BLOCK,
        NavigateSelf => win32::WV_NEWWIN_NAVIGATE_SELF,
        OpenExternal => win32::WV_NEWWIN_OPEN_EXTERNAL,
        AllowPopup => win32::WV_NEWWIN_ALLOW_POPUP,
    };
}

fn wv_scheme_code(s: WebViewColorScheme) -> i32 {
    return match s {
        FollowTheme => 0,
        Auto => 1,
        Light => 2,
        Dark => 3,
    };
}

fn wv_host_access_code(a: WebViewHostAccess) -> i32 {
    return match a {
        Deny => win32::WV_HOST_DENY,
        Allow => win32::WV_HOST_ALLOW,
        DenyCors => win32::WV_HOST_DENY_CORS,
    };
}

fn wv_effective_win32_scheme(app: const App&, scheme_code: i32) -> i32 {
    if scheme_code == 1 { return win32::WV_SCHEME_AUTO; }
    if scheme_code == 2 { return win32::WV_SCHEME_LIGHT; }
    if scheme_code == 3 { return win32::WV_SCHEME_DARK; }
    return if app.theme.is_dark { win32::WV_SCHEME_DARK } else { win32::WV_SCHEME_LIGHT };
}

fn wv_round_i32(v: f32) -> i32 {
    return (if v >= 0.0 { v + 0.5 } else { v - 0.5 }) as! i32;
}

fn wv_color_bytes(c: Color) -> u8, u8, u8, u8 {
    let r = (clamp_f32(c.r, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    let g = (clamp_f32(c.g, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    let b = (clamp_f32(c.b, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    let a = (clamp_f32(c.a, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    return r, g, b, a;
}

fn wv_find_slot(app: const App&, id: WidgetId) -> i64 {
    guard app.valid_widget(id) else { return -1; }
    for i in app.webviews.len {
        if app.webviews[i].alive && eq(app.webviews[i].widget, id) {
            return i;
        }
    }
    return -1;
}

fn wv_find_by_native(app: const App&, wv_id: u32) -> i64 {
    if wv_id == 0 { return -1; }
    for i in app.webviews.len {
        if app.webviews[i].alive && app.webviews[i].handle.id == wv_id {
            return i;
        }
    }
    return -1;
}

fn wv_alloc_slot(app: App&) -> i64 {
    for i in app.webviews.len {
        if !app.webviews[i].alive {
            app.webviews[i] = WebViewState { alive: true };
            return i;
        }
    }
    app.webviews.push(WebViewState { alive: true });
    return app.webviews.len - 1;
}

fn wv_push_payload(app: App&, text: const u8[:], aux: const u8[:] = "") -> i32 {
    var tspan = StrSpan {};
    if text.len > 0 {
        str_set(app.webview_msg_pool, tspan, text);
    }
    var aspan = StrSpan {};
    if aux.len > 0 {
        str_set(app.webview_msg_pool, aspan, aux);
    }
    app.webview_payloads.push(WebViewPayload { text: tspan, aux: aspan });
    return (app.webview_payloads.len - 1) as! i32;
}

fn webview_payload(app: const App&, payload_id: i32) -> const u8[:] {
    if payload_id < 0 || payload_id >= app.webview_payloads.len { return ""; }
    let sp = app.webview_payloads[payload_id].text;
    if sp.len <= 0 || sp.off < 0 || sp.off + sp.len > app.webview_msg_pool.len {
        return "";
    }
    return app.webview_msg_pool[sp.off..sp.off + sp.len];
}

fn webview_payload_source(app: const App&, payload_id: i32) -> const u8[:] {
    if payload_id < 0 || payload_id >= app.webview_payloads.len { return ""; }
    let sp = app.webview_payloads[payload_id].aux;
    if sp.len <= 0 || sp.off < 0 || sp.off + sp.len > app.webview_msg_pool.len {
        return "";
    }
    return app.webview_msg_pool[sp.off..sp.off + sp.len];
}

fn wv_push_signal(app: App&, sig: Signal) {
    if app.log.ui_events && (app.log.file.is_valid() || app.log.also_stderr) {
        app.log_signal(sig);
    }
    app.signals.push(sig);
}

// --- Constructors -----------------------------------------------------------

fn add_webview_with_options(app: App&, parent: WidgetId, opts: WebViewOptions) -> WidgetId {
    guard app.valid_widget(parent) else { return WIDGET_NONE; }
    let win = app.widgets[parent.index].window;
    guard app.valid_window(win) else { return WIDGET_NONE; }

    let id = alloc_widget(app, WidgetKind.WebView, win);
    let mw = if opts.min_w > 0.0 { opts.min_w } else { 320.0 };
    let mh = if opts.min_h > 0.0 { opts.min_h } else { 240.0 };
    app.widgets[id.index].min_size = SizeF { w: mw, h: mh };
    app.widgets[id.index].policy_h = SizePolicy.Expanding;
    app.widgets[id.index].policy_v = SizePolicy.Expanding;
    app.widgets[id.index].focusable = true;
    attach_child(app, parent, id);

    let slot = wv_alloc_slot(app);
    let scheme_code = wv_scheme_code(opts.color_scheme);
    let policy_code = wv_policy_code(opts.new_window_policy);
    app.webviews[slot].widget = id;
    app.webviews[slot].window = win;
    app.webviews[slot].color_scheme_code = scheme_code;
    app.webviews[slot].new_window_policy_code = policy_code;
    app.webviews[slot].devtools = opts.devtools;
    app.webviews[slot].context_menu = opts.context_menu;
    app.webviews[slot].status_bar = opts.status_bar;
    app.webviews[slot].zoom_control = opts.zoom_control;
    app.webviews[slot].accelerator_keys = opts.accelerator_keys;

    if opts.user_data_dir.len > 0 {
        str_set(app.str_pool, app.webviews[slot].user_data_dir, opts.user_data_dir);
    } else if app.webview_default_data_dir.len > 0 {
        var tmp: u8[>..] = [];
        tmp.append(app.str_view(app.webview_default_data_dir));
        str_set(app.str_pool, app.webviews[slot].user_data_dir, tmp);
    }

    if !app.windows[win.index].headless && app.windows[win.index].hwnd.is_valid() {
        var udf_buf: u8[>..] = [];
        udf_buf.append(app.str_view(app.webviews[slot].user_data_dir));
        let wv = win32::webview_create(
            app.windows[win.index].hwnd,
            0, 0,
            wv_round_i32(mw), wv_round_i32(mh),
            udf_buf,
            opts.additional_args
        );
        if wv.is_valid() {
            app.webviews[slot].handle = wv;
            let r, g, b, a = wv_color_bytes(app.theme.surface_bg);
            wv.set_background_color(r, g, b, a);
            wv.set_color_scheme(wv_effective_win32_scheme(app, scheme_code));
            wv.set_devtools_enabled(opts.devtools);
            wv.set_context_menu_enabled(opts.context_menu);
            wv.set_status_bar_enabled(opts.status_bar);
            wv.set_zoom_control_enabled(opts.zoom_control);
            wv.set_accelerator_keys_enabled(opts.accelerator_keys);
            wv.set_new_window_policy(policy_code);
            wv.set_visible(false);
        } else {
            app.webviews[slot].failed = true;
            str_set(app.str_pool, app.webviews[slot].last_error, "Failed to create native WebView2 host");
        }
    }

    if opts.html.len > 0 {
        app.webview_set_html(id, opts.html);
    } else if opts.url.len > 0 {
        app.webview_navigate(id, opts.url);
    }

    app.mark_widget_layout_dirty(id);
    return id;
}

fn add_webview(
    app: App&,
    parent: WidgetId,
    url: const u8[:] = "",
    min_w: f32 = 320.0,
    min_h: f32 = 240.0
) -> WidgetId {
    return app.add_webview_with_options(parent, WebViewOptions {
        url: url,
        min_w: min_w,
        min_h: min_h,
    });
}

fn add_webview_html(
    app: App&,
    parent: WidgetId,
    html: const u8[:],
    min_w: f32 = 320.0,
    min_h: f32 = 240.0
) -> WidgetId {
    return app.add_webview_with_options(parent, WebViewOptions {
        html: html,
        min_w: min_w,
        min_h: min_h,
    });
}

// --- Navigation & State Queries ---------------------------------------------

fn webview_navigate(app: App&, id: WidgetId, url: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    str_set(app.str_pool, app.webviews[slot].url, url);
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.navigate(url);
    }
    return true;
}

fn webview_set_html(app: App&, id: WidgetId, html: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    str_set(app.str_pool, app.webviews[slot].url, "about:blank");
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_html(html);
    }
    return true;
}

fn webview_reload(app: App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.reload();
    }
    return false;
}

fn webview_stop(app: App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.stop();
    }
    return false;
}

fn webview_go_back(app: App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.go_back();
    }
    return false;
}

fn webview_go_forward(app: App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.go_forward();
    }
    return false;
}

fn webview_can_go_back(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    return app.webviews[slot].can_go_back;
}

fn webview_can_go_forward(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    return app.webviews[slot].can_go_forward;
}

fn webview_url(app: const App&, id: WidgetId) -> const u8[:] {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.webviews[slot].url);
}

fn webview_title(app: const App&, id: WidgetId) -> const u8[:] {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.webviews[slot].title);
}

fn webview_is_ready(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    return app.webviews[slot].ready;
}

fn webview_has_failed(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    return app.webviews[slot].failed;
}

fn webview_last_error(app: const App&, id: WidgetId) -> const u8[:] {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.webviews[slot].last_error);
}

fn webview_effective_visible(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    return app.webviews[slot].effective_visible;
}

fn webview_clipped_rect(app: const App&, id: WidgetId) -> RectF {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return RectF {}; }
    return app.webviews[slot].clipped_rect;
}

// --- JavaScript & Bidirectional Messaging -----------------------------------

fn webview_eval_js(app: App&, id: WidgetId, script: const u8[:]) -> u64 {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return 0; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.eval_js(script);
    }
    return 0;
}

fn webview_add_init_script(app: App&, id: WidgetId, script: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.add_init_script(script);
    }
    return true;
}

fn webview_post_json(app: App&, id: WidgetId, json: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.post_message_json(json);
    }
    return true;
}

fn webview_post_string(app: App&, id: WidgetId, text: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.post_message_string(text);
    }
    return true;
}

fn webview_last_message(app: const App&, id: WidgetId) -> const u8[:] {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.webviews[slot].last_message);
}

fn webview_last_script_result(app: const App&, id: WidgetId) -> const u8[:] {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return ""; }
    return app.str_view(app.webviews[slot].last_script_result);
}

// --- Settings, Appearance & Virtual Host ------------------------------------

fn webview_set_zoom(app: App&, id: WidgetId, factor: f64) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    let z = clamp_f64(factor, 0.25, 5.0);
    app.webviews[slot].zoom = z;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_zoom(z);
    }
    return true;
}

fn webview_zoom(app: const App&, id: WidgetId) -> f64 {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return 1.0; }
    return app.webviews[slot].zoom;
}

fn webview_set_muted(app: App&, id: WidgetId, muted: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].muted = muted;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_muted(muted);
    }
    return true;
}

fn webview_is_muted(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.is_muted();
    }
    return app.webviews[slot].muted;
}

fn webview_is_playing_audio(app: const App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.is_playing_audio();
    }
    return false;
}

fn webview_set_devtools_enabled(app: App&, id: WidgetId, enabled: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].devtools = enabled;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_devtools_enabled(enabled);
    }
    return true;
}

fn webview_open_devtools(app: App&, id: WidgetId) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.open_devtools();
    }
    return false;
}

fn webview_set_context_menu_enabled(app: App&, id: WidgetId, enabled: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].context_menu = enabled;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_context_menu_enabled(enabled);
    }
    return true;
}

fn webview_set_status_bar_enabled(app: App&, id: WidgetId, enabled: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].status_bar = enabled;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_status_bar_enabled(enabled);
    }
    return true;
}

fn webview_set_zoom_control_enabled(app: App&, id: WidgetId, enabled: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].zoom_control = enabled;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_zoom_control_enabled(enabled);
    }
    return true;
}

fn webview_set_accelerator_keys_enabled(app: App&, id: WidgetId, enabled: bool) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.webviews[slot].accelerator_keys = enabled;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_accelerator_keys_enabled(enabled);
    }
    return true;
}

fn webview_set_user_agent(app: App&, id: WidgetId, ua: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_user_agent(ua);
    }
    return true;
}

fn webview_set_new_window_policy(app: App&, id: WidgetId, policy: WebViewNewWindowPolicy) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    let code = wv_policy_code(policy);
    app.webviews[slot].new_window_policy_code = code;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_new_window_policy(code);
    }
    return true;
}

fn webview_set_color_scheme(app: App&, id: WidgetId, scheme: WebViewColorScheme) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    let code = wv_scheme_code(scheme);
    app.webviews[slot].color_scheme_code = code;
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_color_scheme(wv_effective_win32_scheme(app, code));
    }
    return true;
}

fn webview_set_background_color(app: App&, id: WidgetId, c: Color) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    app.set_bg(id, c);
    if app.webviews[slot].handle.is_valid() {
        let r, g, b, a = wv_color_bytes(c);
        return app.webviews[slot].handle.set_background_color(r, g, b, a);
    }
    return true;
}

fn webview_set_virtual_host(
    app: App&,
    id: WidgetId,
    host_name: const u8[:],
    folder_path: const u8[:],
    access: WebViewHostAccess = WebViewHostAccess.Allow
) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.set_virtual_host_mapping(host_name, folder_path, wv_host_access_code(access));
    }
    return true;
}

fn webview_clear_virtual_host(app: App&, id: WidgetId, host_name: const u8[:]) -> bool {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return false; }
    if app.webviews[slot].handle.is_valid() {
        return app.webviews[slot].handle.clear_virtual_host_mapping(host_name);
    }
    return true;
}

fn webview_focus(app: App&, id: WidgetId) {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    if app.webviews[slot].handle.is_valid() {
        app.webviews[slot].handle.focus();
    }
}

// --- Layout / Visibility / Clip Sync & Event Draining -----------------------

fn wv_is_active_page_child(app: const App&, container: WidgetId, child: WidgetId) -> bool {
    match app.widgets[container.index].kind {
        TabWidget => {
            let sel = app.widgets[container.index].selected_index;
            let slot = app.find_nth_item(container, sel);
            if slot < 0 { return false; }
            return eq(app.list_items[slot].page, child);
        },
        Panel, Frame, GroupBox => {
            match app.widgets[container.index].layout {
                Stack => {
                    let sel = app.widgets[container.index].selected_index;
                    var cur = app.widgets[container.index].first_child;
                    var idx: i32 = 0;
                    while app.valid_widget(cur) {
                        if idx == sel {
                            return eq(cur, child);
                        }
                        cur = app.widgets[cur.index].next_sibling;
                        idx += 1;
                    }
                    return false;
                },
                _ => { return true; },
            }
        },
        _ => { return true; },
    }
}

fn sync_window_webviews(app: App&, win: WindowId) {
    guard app.valid_window(win) else { return; }
    if app.webviews.len == 0 { return; }

    let win_vis = app.windows[win.index].visible;
    let ww = app.windows[win.index].width as f32;
    let wh = app.windows[win.index].height as f32;
    var avail_h = wh;
    let sb = app.windows[win.index].status_bar;
    if app.valid_widget(sb) && app.widgets[sb.index].visible {
        let sbh = if app.widgets[sb.index].fixed_h > 0.0 { app.widgets[sb.index].fixed_h } else { 26.0 };
        avail_h = if wh > sbh { wh - sbh } else { 0.0 };
    }
    let win_clip = RectF { x: 0.0, y: 0.0, w: ww, h: avail_h };

    for i in app.webviews.len {
        if !app.webviews[i].alive || !eq(app.webviews[i].window, win) { continue; }
        let id = app.webviews[i].widget;
        if !app.valid_widget(id) { continue; }

        var vis = win_vis && app.widgets[id.index].visible;
        var clip = win_clip;

        var cur = id;
        while vis && app.valid_widget(cur) {
            if !app.widgets[cur.index].visible {
                vis = false;
                break;
            }
            let p = app.widgets[cur.index].parent;
            if app.valid_widget(p) {
                if !wv_is_active_page_child(app, p, cur) {
                    vis = false;
                    break;
                }
                match app.widgets[p.index].kind {
                    ScrollArea => {
                        let sr = app.widgets[p.index].rect;
                        let sb_res: f32 = if app.widgets[p.index].scroll_max_y > 0.0 { 11.0 } else { 2.0 };
                        let s_clip = RectF {
                            x: sr.x + 1.0,
                            y: sr.y + 1.0,
                            w: if sr.w > sb_res + 1.0 { sr.w - sb_res - 1.0 } else { 0.0 },
                            h: if sr.h > 2.0 { sr.h - 2.0 } else { 0.0 },
                        };
                        clip = intersect(clip, s_clip);
                    },
                    _ => {},
                }
            }
            cur = p;
        }

        let r = app.widgets[id.index].rect;
        let final_clip = intersect(r, clip);
        let eff_vis = vis && r.w > 0.0 && r.h > 0.0 && final_clip.w > 0.0 && final_clip.h > 0.0;
        app.webviews[i].effective_visible = eff_vis;
        app.webviews[i].clipped_rect = if eff_vis { final_clip } else { RectF {} };

        if !app.windows[win.index].headless && app.webviews[i].handle.is_valid() {
            app.webviews[i].handle.set_bounds_clipped(
                wv_round_i32(r.x),
                wv_round_i32(r.y),
                wv_round_i32(r.w),
                wv_round_i32(r.h),
                wv_round_i32(clip.x),
                wv_round_i32(clip.y),
                wv_round_i32(clip.w),
                wv_round_i32(clip.h)
            );
            app.webviews[i].handle.set_visible(eff_vis);
        }
    }
}

fn notify_window_webviews_moved(app: App&, win: WindowId) {
    guard app.valid_window(win) && !app.windows[win.index].headless else { return; }
    for i in app.webviews.len {
        if app.webviews[i].alive && eq(app.webviews[i].window, win) && app.webviews[i].handle.is_valid() {
            app.webviews[i].handle.notify_parent_pos_changed();
        }
    }
}

fn drain_webview_events(app: App&) {
    var ev = win32::WebViewEvent {};
    var s1: u8[>..] = [];
    var s2: u8[>..] = [];

    while win32::webview_poll_event(ev, s1, s2) {
        let slot = wv_find_by_native(app, ev.webview_id);
        if slot < 0 { continue; }
        let id = app.webviews[slot].widget;
        let win = app.webviews[slot].window;
        guard app.valid_widget(id) && app.valid_window(win) else { continue; }

        if ev.kind == win32::WV_EV_READY {
            app.webviews[slot].ready = true;
            app.webviews[slot].failed = false;
            app.mark_dirty(win);
            wv_push_signal(app, Signal.WebViewReady { widget: id, window: win });
        } else if ev.kind == win32::WV_EV_INIT_FAILED {
            app.webviews[slot].failed = true;
            app.webviews[slot].last_hr = ev.int_val;
            str_set(app.str_pool, app.webviews[slot].last_error, s1);
            app.mark_dirty(win);
            wv_push_signal(app, Signal.WebViewInitFailed { widget: id, window: win, hr: ev.int_val });
        } else if ev.kind == win32::WV_EV_NAV_STARTING {
            str_set(app.str_pool, app.webviews[slot].url, s1);
            let pid = wv_push_payload(app, s1);
            wv_push_signal(app, Signal.WebViewNavigationStarting {
                widget: id,
                window: win,
                payload: pid,
                user_initiated: ev.flag_a,
                redirected: ev.flag_b,
            });
        } else if ev.kind == win32::WV_EV_NAV_COMPLETED {
            wv_push_signal(app, Signal.WebViewNavigationCompleted {
                widget: id,
                window: win,
                success: ev.flag_a,
                error_status: ev.int_val,
            });
        } else if ev.kind == win32::WV_EV_SOURCE_CHANGED {
            str_set(app.str_pool, app.webviews[slot].url, s1);
            wv_push_signal(app, Signal.WebViewSourceChanged {
                widget: id,
                window: win,
                is_new_document: ev.flag_a,
            });
        } else if ev.kind == win32::WV_EV_TITLE_CHANGED {
            str_set(app.str_pool, app.webviews[slot].title, s1);
            wv_push_signal(app, Signal.WebViewTitleChanged { widget: id, window: win });
        } else if ev.kind == win32::WV_EV_HISTORY_CHANGED {
            app.webviews[slot].can_go_back = ev.flag_a;
            app.webviews[slot].can_go_forward = ev.flag_b;
            wv_push_signal(app, Signal.WebViewHistoryChanged {
                widget: id,
                window: win,
                can_go_back: ev.flag_a,
                can_go_forward: ev.flag_b,
            });
        } else if ev.kind == win32::WV_EV_WEB_MESSAGE {
            str_set(app.str_pool, app.webviews[slot].last_message, s1);
            let pid = wv_push_payload(app, s1, s2);
            wv_push_signal(app, Signal.WebViewMessageReceived {
                widget: id,
                window: win,
                payload: pid,
                is_json: ev.flag_a,
            });
        } else if ev.kind == win32::WV_EV_SCRIPT_RESULT {
            str_set(app.str_pool, app.webviews[slot].last_script_result, s1);
            let pid = wv_push_payload(app, s1);
            wv_push_signal(app, Signal.WebViewScriptResult {
                widget: id,
                window: win,
                request_id: ev.req_id,
                payload: pid,
                ok: ev.flag_a,
            });
        } else if ev.kind == win32::WV_EV_NEW_WINDOW {
            let pid = wv_push_payload(app, s1);
            wv_push_signal(app, Signal.WebViewNewWindowRequested {
                widget: id,
                window: win,
                payload: pid,
                user_initiated: ev.flag_a,
            });
        } else if ev.kind == win32::WV_EV_FOCUS_CHANGED {
            if ev.flag_a {
                if !eq(app.windows[win.index].focused, id) {
                    let prev = app.windows[win.index].focused;
                    if app.valid_widget(prev) {
                        wv_push_signal(app, Signal.FocusChanged { widget: prev, window: win, focused: false });
                    }
                    app.windows[win.index].focused = id;
                    wv_push_signal(app, Signal.FocusChanged { widget: id, window: win, focused: true });
                    app.mark_dirty(win);
                }
            }
        }
    }
}

// --- Synthetic Injection Helpers (for Headless Automated Tests) -------------

fn inject_webview_ready(app: App&, id: WidgetId) {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    app.webviews[slot].ready = true;
    app.webviews[slot].failed = false;
    wv_push_signal(app, Signal.WebViewReady { widget: id, window: app.webviews[slot].window });
}

fn inject_webview_navigation(app: App&, id: WidgetId, url: const u8[:], success: bool = true, error_status: i32 = 0) {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    let win = app.webviews[slot].window;
    str_set(app.str_pool, app.webviews[slot].url, url);
    let pid = wv_push_payload(app, url);
    wv_push_signal(app, Signal.WebViewNavigationStarting {
        widget: id,
        window: win,
        payload: pid,
        user_initiated: true,
        redirected: false,
    });
    wv_push_signal(app, Signal.WebViewSourceChanged {
        widget: id,
        window: win,
        is_new_document: true,
    });
    wv_push_signal(app, Signal.WebViewNavigationCompleted {
        widget: id,
        window: win,
        success: success,
        error_status: error_status,
    });
}

fn inject_webview_title(app: App&, id: WidgetId, title: const u8[:]) {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    str_set(app.str_pool, app.webviews[slot].title, title);
    wv_push_signal(app, Signal.WebViewTitleChanged { widget: id, window: app.webviews[slot].window });
}

fn inject_webview_message(app: App&, id: WidgetId, payload: const u8[:], is_json: bool = false, source: const u8[:] = "https://local/") {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    str_set(app.str_pool, app.webviews[slot].last_message, payload);
    let pid = wv_push_payload(app, payload, source);
    wv_push_signal(app, Signal.WebViewMessageReceived {
        widget: id,
        window: app.webviews[slot].window,
        payload: pid,
        is_json: is_json,
    });
}

fn inject_webview_script_result(app: App&, id: WidgetId, request_id: u64, result: const u8[:], ok: bool = true) {
    let slot = wv_find_slot(app, id);
    guard slot >= 0 else { return; }
    str_set(app.str_pool, app.webviews[slot].last_script_result, result);
    let pid = wv_push_payload(app, result);
    wv_push_signal(app, Signal.WebViewScriptResult {
        widget: id,
        window: app.webviews[slot].window,
        request_id: request_id,
        payload: pid,
        ok: ok,
    });
}
