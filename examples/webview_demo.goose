// Interactive WebView2 demo for goose_ui.
// Run:  goose run examples/webview_demo.goose
// Build: goose build examples/webview_demo.goose
import std;
import json;
import win32 from "../win32-goose";
import goose_ui from "..";

let ID_BACK: i64       = 100;
let ID_FORWARD: i64    = 101;
let ID_RELOAD: i64     = 102;
let ID_URL: i64        = 103;
let ID_GO: i64         = 104;
let ID_ZOOM_OUT: i64   = 105;
let ID_ZOOM_RESET: i64 = 106;
let ID_ZOOM_IN: i64    = 107;
let ID_DEVTOOLS: i64   = 108;

let ID_TABS: i64       = 120;
let ID_MSG_INPUT: i64  = 130;
let ID_SEND_JSON: i64  = 131;
let ID_EVAL_JS: i64    = 132;
let ID_BRIDGE_LOG: i64 = 133;
let ID_EVAL_OUT: i64   = 134;

fn active_webview(
    app: const goose_ui::App&,
    tabs: goose_ui::WidgetId,
    wv_bridge: goose_ui::WidgetId,
    wv_vhost: goose_ui::WidgetId,
    wv_browser: goose_ui::WidgetId
) -> goose_ui::WidgetId {
    let idx = app.selected_index(tabs);
    if idx == 1 { return wv_vhost; }
    if idx == 2 { return wv_browser; }
    return wv_bridge;
}

fn sync_toolbar_state(
    app: goose_ui::App&,
    win: goose_ui::WindowId,
    tabs: goose_ui::WidgetId,
    wv_bridge: goose_ui::WidgetId,
    wv_vhost: goose_ui::WidgetId,
    wv_browser: goose_ui::WidgetId
) {
    let cur = active_webview(app, tabs, wv_bridge, wv_vhost, wv_browser);
    app.set_enabled(app.by_id(win, ID_BACK), app.webview_can_go_back(cur));
    app.set_enabled(app.by_id(win, ID_FORWARD), app.webview_can_go_forward(cur));
    let u = app.webview_url(cur);
    if u.len > 0 {
        app.set_text_of(win, ID_URL, u);
    } else {
        app.set_text_of(win, ID_URL, "about:blank");
    }
    let zp = (app.webview_zoom(cur) * 100.0 + 0.5) as! i32;
    app.set_text_of(win, ID_ZOOM_RESET, str(zp, "%"));
}

fn main() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Direct2D);
    app.set_window_start_position(goose_ui::WindowPosition.CenterPrimary);

    let tmp = win32::temp_dir();
    let sep = if tmp.len > 0 && (tmp[tmp.len - 1] == '\\' || tmp[tmp.len - 1] == '/') { "" } else { "\\" };
    let vhost_dir = str(tmp, sep, "goose_ui_wv_demo_vhost_", win32::GetCurrentProcessId());
    let vhost_index = str(vhost_dir, "\\index.html");
    win32::create_directory(vhost_dir);
    let _ok_v = win32::write_file_bytes(vhost_index, """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Goose Virtual Host</title>
  <style>
    :root { color-scheme: light dark; font-family: "Segoe UI", sans-serif; }
    body { margin: 28px; line-height: 1.5; }
    .card { border: 1px solid rgba(128,128,128,0.35); border-radius: 10px; padding: 18px; max-width: 620px; }
    code { padding: 2px 6px; border-radius: 4px; background: rgba(128,128,128,0.18); }
  </style>
</head>
<body>
  <div class="card">
    <h2>Virtual Host Mapping (https://goose-demo.local)</h2>
    <p>This page is served directly from a local folder without an HTTP server using <code>webview_set_virtual_host</code>.</p>
    <button onclick="window.chrome.webview.postMessage({ source: 'vhost', at: Date.now() })">
      Send message from virtual host
    </button>
  </div>
</body>
</html>
""");

    let win = app.create_window("goose_ui — WebView2 Demo", 1080, 740);
    let avail = goose_ui::webview_is_available();
    let ver = goose_ui::webview_runtime_version();
    if avail {
        app.set_status_bar(win, str("WebView2 Runtime ", ver, " — Ready"));
    } else {
        app.set_status_bar(win, "WebView2 Runtime not found on this machine");
    }

    let bridge_html = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Goose ⇔ WebView2 Bridge</title>
  <style>
    :root { color-scheme: light dark; font-family: "Segoe UI", sans-serif; }
    body { margin: 24px; }
    .card { border: 1px solid rgba(128,128,128,0.35); border-radius: 10px; padding: 18px; }
    button { padding: 8px 14px; border-radius: 6px; border: 1px solid rgba(128,128,128,0.4); cursor: pointer; font-weight: 600; }
    pre { margin-top: 12px; padding: 10px; border-radius: 6px; background: rgba(128,128,128,0.15); overflow-x: auto; }
  </style>
</head>
<body>
  <div class="card">
    <h2>Goose ⇔ JavaScript Bidirectional Bridge</h2>
    <p id="init-status">Checking init script...</p>
    <button id="btn-ping">Post JSON to Goose</button>
    <pre id="inbox">Waiting for Goose messages...</pre>
  </div>
  <script>
    let clicks = 0;
    document.getElementById('init-status').textContent =
      'Init script active: ' + Boolean(window.__gooseBridgeVersion) + ' (v' + (window.__gooseBridgeVersion || 0) + ')';
    document.getElementById('btn-ping').addEventListener('click', () => {
      clicks += 1;
      window.chrome.webview.postMessage({ type: 'ui_ping', clicks: clicks, title: document.title });
    });
    window.chrome.webview.addEventListener('message', (ev) => {
      document.getElementById('inbox').textContent =
        'From Goose: ' + (typeof ev.data === 'string' ? ev.data : JSON.stringify(ev.data, null, 2));
    });
  </script>
</body>
</html>
""";

    var w_tabs = goose_ui::WIDGET_NONE;
    var wv_bridge = goose_ui::WIDGET_NONE;
    var wv_vhost = goose_ui::WIDGET_NONE;
    var wv_browser = goose_ui::WIDGET_NONE;

    app.ui(win) { u =>
        u.padding(10.0).spacing(8.0);

        // Top Navigation Toolbar
        u.hbox(6.0, 0.0) { bar =>
            bar.button("Back").secondary().width(64.0).enabled(false).action(ID_BACK);
            bar.button("Forward").secondary().width(76.0).enabled(false).action(ID_FORWARD);
            bar.button("Reload").secondary().width(72.0).action(ID_RELOAD);
            bar.line_edit("https://...", "about:blank").stretch(1.0).action(ID_URL);
            bar.button("Go").primary().width(56.0).action(ID_GO);
            bar.button("-").secondary().width(32.0).action(ID_ZOOM_OUT);
            bar.button("100%").secondary().width(58.0).action(ID_ZOOM_RESET);
            bar.button("+").secondary().width(32.0).action(ID_ZOOM_IN);
            bar.button("DevTools").secondary().width(86.0).action(ID_DEVTOOLS);
            bar.toggle("Dark", true).on_toggle_theme();
        };

        // Main Tabbed Workspace
        u.tabs() { t =>
            t.stretch(1.0).bind(w_tabs).action(ID_TABS);

            t.tab("Bridge (HTML + JS)", goose_ui::LayoutKind.VBox, 8.0, 8.0) { p0 =>
                p0.splitter(goose_ui::Orientation.Horizontal, 0.64) { sp =>
                    sp.stretch(1.0);
                    sp.webview_html(bridge_html, 360.0, 280.0)
                      .init_script("window.__gooseBridgeVersion = 1;")
                      .devtools(true)
                      .stretch(1.0)
                      .bind(wv_bridge);

                    sp.frame(goose_ui::LayoutKind.VBox, 8.0, 12.0) { side =>
                        side.label("Goose Host Inspector").heading();
                        side.label("Send payload or evaluate JavaScript in the active WebView:").caption().wrap();
                        side.line_edit("Message text...", "Hello from Goose UI!").action(ID_MSG_INPUT);
                        side.hbox(8.0, 0.0) { btns =>
                            btns.button("Post JSON to JS").primary().stretch(1.0).action(ID_SEND_JSON);
                            btns.button("Eval document.title").secondary().stretch(1.0).action(ID_EVAL_JS);
                        };
                        side.separator();
                        side.label("Last WebMessage from JS:").bold();
                        side.label("(none yet)").mono().wrap().height(90.0).action(ID_BRIDGE_LOG);
                        side.label("Last Eval Result:").bold();
                        side.label("(none yet)").mono().wrap().height(64.0).action(ID_EVAL_OUT);
                        side.spacer(1.0);
                    };
                };
            };

            t.tab("Virtual Host (.local)", goose_ui::LayoutKind.VBox, 0.0, 8.0) { p1 =>
                p1.webview("", 360.0, 280.0)
                  .virtual_host("goose-demo.local", vhost_dir, goose_ui::WebViewHostAccess.Allow)
                  .url("https://goose-demo.local/index.html")
                  .stretch(1.0)
                  .bind(wv_vhost);
            };

            t.tab("Browser (example.com)", goose_ui::LayoutKind.VBox, 0.0, 8.0) { p2 =>
                p2.webview("https://example.com", 360.0, 280.0)
                  .new_window_policy(goose_ui::WebViewNewWindowPolicy.BlockAndNotify)
                  .status_bar(true)
                  .stretch(1.0)
                  .bind(wv_browser);
            };
        };
    };

    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
    app.show_window(win);

    var last_eval_req: u64 = 0;

    app.exec() { sig =>
        match sig {
            Clicked s => {
                let aid = app.action_id(s.widget);
                let cur = active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser);
                if aid == ID_BACK {
                    app.webview_go_back(cur);
                } else if aid == ID_FORWARD {
                    app.webview_go_forward(cur);
                } else if aid == ID_RELOAD {
                    app.webview_reload(cur);
                } else if aid == ID_GO {
                    app.webview_navigate(cur, app.text_of(win, ID_URL));
                } else if aid == ID_ZOOM_OUT {
                    app.webview_set_zoom(cur, app.webview_zoom(cur) - 0.1);
                    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
                } else if aid == ID_ZOOM_RESET {
                    app.webview_set_zoom(cur, 1.0);
                    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
                } else if aid == ID_ZOOM_IN {
                    app.webview_set_zoom(cur, app.webview_zoom(cur) + 0.1);
                    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
                } else if aid == ID_DEVTOOLS {
                    app.webview_open_devtools(cur);
                } else if aid == ID_SEND_JSON {
                    var msg_json: u8[>..] = [];
                    msg_json.append("{\"from\":\"goose_ui\",\"msg\":");
                    json::format_string(msg_json, app.text_of(win, ID_MSG_INPUT));
                    msg_json.push('}');
                    app.webview_post_json(wv_bridge, msg_json);
                } else if aid == ID_EVAL_JS {
                    last_eval_req = app.webview_eval_js(cur, "document.title");
                }
            },
            TextSubmitted s => {
                if app.action_id(s.widget) == ID_URL {
                    let cur = active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser);
                    app.webview_navigate(cur, app.text_of(win, ID_URL));
                }
            },
            TabChanged s => {
                if goose_ui::eq(s.widget, w_tabs) {
                    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
                }
            },
            WebViewReady s => {
                if goose_ui::eq(s.widget, active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser)) {
                    app.set_status_text(win, str("WebView2 Ready (v", ver, ")"));
                }
            },
            WebViewInitFailed s => {
                app.set_status_text(win, str("WebView2 failed hr=", s.hr, " ", app.webview_last_error(s.widget)));
            },
            WebViewNavigationStarting s => {
                let u = app.webview_payload(s.payload);
                if goose_ui::eq(s.widget, active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser)) {
                    app.set_text_of(win, ID_URL, u);
                    app.set_status_text(win, str("Loading: ", u));
                }
            },
            WebViewNavigationCompleted s => {
                let cur = active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser);
                if goose_ui::eq(s.widget, cur) {
                    sync_toolbar_state(app, win, w_tabs, wv_bridge, wv_vhost, wv_browser);
                    if s.success {
                        app.set_status_text(win, str("Loaded: ", app.webview_url(cur)));
                    } else {
                        app.set_status_text(win, str("Navigation error (", s.error_status, ")"));
                    }
                }
            },
            WebViewHistoryChanged s => {
                if goose_ui::eq(s.widget, active_webview(app, w_tabs, wv_bridge, wv_vhost, wv_browser)) {
                    app.set_enabled(app.by_id(win, ID_BACK), s.can_go_back);
                    app.set_enabled(app.by_id(win, ID_FORWARD), s.can_go_forward);
                }
            },
            WebViewMessageReceived s => {
                let txt = app.webview_payload(s.payload);
                app.set_text_of(win, ID_BRIDGE_LOG, txt);
            },
            WebViewScriptResult s => {
                if s.request_id == last_eval_req || last_eval_req == 0 {
                    app.set_text_of(win, ID_EVAL_OUT, app.webview_payload(s.payload));
                }
            },
            WebViewNewWindowRequested s => {
                app.set_status_text(win, str("Blocked popup: ", app.webview_payload(s.payload)));
            },
            _ => {},
        }
    };

    win32::delete_file(vhost_index);
    win32::remove_directory(vhost_dir);
}
