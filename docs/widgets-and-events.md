# Widgets, Events & Native API Reference

---

## 1. Widget Catalog (22 Retained Widgets)

### Containers & Structural Widgets
`Panel`, `Frame`, `GroupBox`, `Spacer`, `Separator`, `TabWidget`, `ScrollArea`, `Splitter`, `StatusBar`

### Leaf Widgets (DSL Builders)

| DSL Method | Description & Features |
| --- | --- |
| `u.label(text, role = FontRole.Body)` | Single-line or wrapped (`.wrap()` / `set_word_wrap`) text label (`.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`) |
| `u.button(text, variant = Default)` | Push button with 5 variants (`.primary()`, `.secondary()`, `.danger()`, `.ghost()`) and optional `.checkable()` toggle state |
| `u.checkbox(text, checked = false)` | CheckBox emitting `Toggled` and `Clicked` |
| `u.radio(text, checked = false)` | RadioButton with automatic mutual exclusivity among siblings |
| `u.toggle(text, checked = false)` | Modern animated-style ToggleSwitch emitting `Toggled` and `Clicked` |
| `u.line_edit(placeholder = "", initial_text = "")` | Single-line horizontally scrolling text input with accurate per-window GDI/CJK/UTF-8 caret positioning, surrogate-pair emoji support, selection, Home/End/Arrows, `Ctrl+A/C/X/V` via Windows Clipboard, `.password()`, `.read_only()` |
| `u.slider(min, max, initial, step, orientation)` | Horizontal or vertical slider supporting pointer drag, mouse wheel, and arrow keys |
| `u.spin_box(min, max, initial, step, decimals)` | Numeric input with `+/-` buttons, mouse wheel, and arrow keys |
| `u.progress_bar(min, max, initial)` | Progress bar with optional percentage label (`app.set_show_percentage`) |
| `u.combo_box()` | Dropdown selector with top-level floating overlay, wheel scrolling for >8 items, `Esc` / `Space` / `Enter` support, and `.item(text)` |
| `u.list_view(item_height = 30.0)` | Virtualized scrollable list with primary text, subtext, `item_tag`, keyboard navigation with auto-scroll, and double-click activation |
| `u.canvas(min_w = 200.0, min_h = 160.0)` | Custom 2D vector & text drawing surface with local mouse and wheel events |
| `u.webview(url = "", min_w = 320.0, min_h = 240.0)` | Embedded Microsoft Edge WebView2 browser (`u.webview_html`, `u.webview_with`, JS bridge, virtual host mapping, and viewport clipping) |

### Status Bar

Docked to the bottom edge of a top-level window:

```goose
app.set_status_bar(win, "Ready");
// Update at any time (reuses pooled string capacity in place)
app.set_status_text(win, "Saved successfully");
```

### Common `Node` Modifiers (UFCS Chains)

- **Identity & Binding**: `.action(id)`, `.name("...")`, `.bind(var_id)`, `.widget()`
- **Layout**: `.stretch(s)`, `.fixed(w, h)`, `.width(w)`, `.height(h)`, `.min_size(w, h)`, `.max_size(w, h)`, `.policy(h, v)`, `.align(h, v)`, `.padding(all)`, `.spacing(sp)`, `.form_label_width(w)`, `.bounds(x, y, w, h, anchor, ref_w, ref_h)`
- **Typography**: `.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`, `.text_align(h, v)`, `.wrap(on = true)`
- **Appearance**: `.primary()`, `.secondary()`, `.danger()`, `.ghost()`, `.checkable()`, `.bg(c)`, `.fg(c)`, `.border(c, w)`, `.radius(r)`
- **State & Input**: `.tooltip("...")`, `.placeholder("...")`, `.password()`, `.read_only()`, `.enabled(bool)`, `.visible(bool)`
- **Items**: `.item(text, subtext = "", tag = 0)`, `.select(idx)`
- **Multi-Language (i18n)**: `.tr_text(key)`, `.tr_placeholder(key)`, `.tr_tooltip(key)`, `.tr_item(text_key, subtext_key = "", tag = 0)`
- **Declarative Connections**: `.connect(sig, receiver, slot, param)`, `.on_toggle_theme()`, `.on_click_close()`

---

## 2. Event Loop & `Signal` Dispatch

### Running the Event Loop

- Standard applications: `app.exec() { sig => ... };`
- With custom `Canvas` painting: `app.exec_with_canvas(paint_fn) { sig => ... };`

The loop blocks in `win32::wait_event`, keeping **idle CPU usage at 0%** and repainting only when a window's `dirty` flag is set.

### All `Signal` Variants

| Signal | When Emitted | Fields |
| --- | --- | --- |
| `Clicked` | Button / CheckBox / RadioButton / ToggleSwitch activation | `widget`, `window` |
| `DoubleClicked` | Left double-click on a widget | `widget`, `window` |
| `Toggled` | Checked state change (including deselected sibling RadioButtons) | `widget`, `window`, `checked` |
| `ValueChanged` | Slider / SpinBox value change | `widget`, `window`, `value` |
| `TextChanged` | LineEdit text modification | `widget`, `window` |
| `TextSubmitted` | `Enter` pressed in LineEdit | `widget`, `window` |
| `SelectionChanged` | ComboBox / ListView selection change | `widget`, `window`, `index` |
| `ItemActivated` | ListView double-click or `Enter` | `widget`, `window`, `index` |
| `TabChanged` | TabWidget active tab change | `widget`, `window`, `index` |
| `FocusChanged` | Widget focus gained or lost | `widget`, `window`, `focused` |
| `ActionTriggered` | Native MenuBar / ContextMenu command (`WM_COMMAND`) | `window`, `action_id` |
| `TimerFired` | Timer started with `start_timer` elapsed | `window`, `timer_id` |
| `KeyPressed` | Key press with modifier bitmask (`KMOD_SHIFT`, `KMOD_CTRL`, `KMOD_ALT`) | `window`, `widget`, `key`, `mods` |
| `CanvasMouseDown` / `Move` / `Up` / `Wheel` | Local-coordinate pointer input on a `Canvas` | `widget`, `window`, `x`, `y`, (`button` / `delta`) |
| `FilesDropped` | Files dropped onto window (requires `app.enable_drop_files(win)`) | `window`, `count` |
| `WindowResized` / `WindowClosed` | Window resize or close request | `window`, (`width`, `height`) |
| `LocaleChanged` | Active i18n locale changed via `app.set_locale(...)` | `locale_index` |
| `WebViewReady` / `WebViewInitFailed` | Async WebView2 controller initialization result | `widget`, `window`, (`hr`) |
| `WebViewNavigationStarting` / `Completed` | Navigation start and completion | `widget`, `window`, (`payload`, `user_initiated`, `redirected` / `success`, `error_status`) |
| `WebViewTitleChanged` / `SourceChanged` / `HistoryChanged` | Document title, URI, or back/forward history updates | `widget`, `window`, (`is_new_document` / `can_go_back`, `can_go_forward`) |
| `WebViewMessageReceived` | JS message posted via `window.chrome.webview.postMessage(...)` | `widget`, `window`, `payload`, `is_json` |
| `WebViewScriptResult` | Async completion of `webview_eval_js(...)` | `widget`, `window`, `request_id`, `payload`, `ok` |
| `WebViewNewWindowRequested` | Popup / new window interception (`WebViewNewWindowPolicy`) | `widget`, `window`, `payload`, `user_initiated` |

### Win32-Style Action ID Dispatch

Avoid declaring dozens of `WidgetId` variables by tagging controls with integer IDs:

```goose
let ID_SAVE = 101;
let ID_NAME = 201;

app.exec() { sig =>
    match sig {
        Clicked s => match app.action_id(s.widget) {
            ID_SAVE => {
                let name = app.text_of(win, ID_NAME);
                app.set_status_text(win, str("Saved: ", name));
            },
            _ => {},
        },
        _ => {},
    }
};
```

Helper accessors:
`app.action_id(widget)`, `app.by_id(win, id)`, `app.text_of(win, id)`, `app.set_text_of(win, id, s)`, `app.value_of(win, id)`, `app.set_value_of(win, id, v)`, `app.checked_of(win, id)`, `app.set_checked_of(win, id, b)`.

---

## 3. Declarative Signal → Slot Connections (`connect`)

Wire common reactive behaviors (such as syncing a slider with a progress bar, enabling/disabling controls, or toggling themes) declaratively without boilerplate in the event loop:

```goose
app.connect(slider_id, goose_ui::SignalKind.OnValueChange, progress_id, goose_ui::SlotAction.SetValue);
app.connect(slider_id, goose_ui::SignalKind.OnValueChange, value_lbl, goose_ui::SlotAction.SetValueLabel);
```

- **`SignalKind`**: `OnClick`, `OnToggle`, `OnValueChange`, `OnTextChange`, `OnTextSubmit`, `OnSelectionChange`, `OnTabChange`
- **`SlotAction`**: `SetVisible`, `SetVisibleInverted`, `SetEnabled`, `SetEnabledInverted`, `SetChecked`, `ToggleChecked`, `SetValue`, `SetValueLabel`, `SyncText`, `SetCurrentTab`, `ClearText`, `IncrementValue`, `CloseWindow`, `ToggleTheme`

---

## 4. Custom Drawing (`Canvas` + `Painter`)

`Canvas` widgets invoke your paint callback in local coordinates `(0, 0) .. (p.width, p.height)`. The same code runs on both `RenderBackend.Software` and `RenderBackend.Direct2D`:

```goose
fn paint_canvas(cid: goose_ui::WidgetId, p: goose_ui::Painter) {
    p.fill_rounded_rect(0.0, 0.0, p.width, p.height, 8.0, p.theme.input_bg);
    p.fill_ellipse(p.width * 0.5, p.height * 0.5, 48.0, 48.0, p.theme.accent);
    p.draw_text("Canvas", 0.0, 0.0, p.width, p.height, p.theme.accent_text,
                goose_ui::FontRole.BodyBold, goose_ui::Align.Center, goose_ui::Align.Center);
}

// Start event loop:
app.exec_with_canvas(paint_canvas) { sig =>
    // Update state on CanvasMouseDown / TimerFired, then call app.mark_dirty(win)
};
```

`Painter` primitives:
`fill_rect`, `draw_rect`, `fill_rounded_rect`, `draw_rounded_rect`, `fill_ellipse`, `draw_ellipse`, `draw_line`, `draw_text`.

---

## 5. Native Windows Integrations (`native.goose`)

- **MenuBar & Context Menus**:
  - `create_menu_bar(app, win)` / `create_popup_menu()` / `add_submenu(parent, title)`
  - `add_action(menu, action_id, text, enabled, checked)` / `add_menu_separator(menu)`
  - `set_action_enabled` / `set_action_checked` / `refresh_menu_bar` / `show_context_menu` / `destroy_menu`
- **Message Boxes**: `msg_info`, `msg_warning`, `msg_error`, `msg_question -> bool`
- **Common Dialogs**:
  - `open_file_dialog(app, win, out_path, title, filter, default_ext)`
  - `save_file_dialog(app, win, out_path, title, filter, default_ext, initial_name)`
  - `select_folder_dialog(app, win, out_path, title)`
  - `choose_color_dialog(app, win, color_ref)`
  - `input_dialog(app, win, out_text, title, prompt, initial_text)`
- **Clipboard**: `clipboard_text() -> u8[>..]`, `set_clipboard_text(text)`
- **Timers (`QTimer`)**: `start_timer(app, win, interval_ms, single_shot = false) -> u64`, `stop_timer(app, timer_id)`
- **Drag & Drop**: `app.enable_drop_files(win, true)` → query `dropped_file_count()` and `dropped_file_path(i)` on `FilesDropped`
- **Window Positioning & Constraints**:
  - Startup defaults (`App`): `set_window_start_position(WindowPosition)` (`SystemDefault`, `CenterPrimary`, `CenterMonitor`, `Manual`), `set_center_on_primary_display(enabled = true)`, `set_window_start_monitor(index)`, `set_window_start_position_manual(x, y)`, `window_start_position() -> WindowPosition`
  - Runtime positioning & sizing: `center_window(win)`, `center_window_on_monitor(win, index)`, `set_window_position(win, x, y)`, `window_position(win) -> x, y`, `set_window_min_size(win, min_w, min_h)` (`WM_GETMINMAXINFO` enforcement; render loop also yields live frames during interactive Win32 resize drags and auto-syncs Direct2D/OpenGL/GDI viewports on resize/DPI changes)
  - Work area & geometry helpers: `primary_work_area() -> win32::Rect`, `monitor_work_area(index) -> win32::Rect`, `compute_centered_pos(work, win_w, win_h) -> x, y`

---

## 6. Themes & Styling

- Built-in themes: `theme_dark()`, `theme_light()`
- Live switching: `app.set_theme(custom_theme)` / `app.toggle_theme()` (automatically syncs Windows 11 DWM dark titlebars)
- Color utilities: `rgb(r, g, b)`, `rgba(r, g, b, a)`, `color_hex(0x3B82F6, a = 1.0)`, `with_alpha(c, a)`, `lerp_color(a, b, t)`

---

## 7. Structured JSON Logging (`log.goose`)

`goose_ui` includes a pure-Goose, zero-heap structured JSON logging system powered by Goose's standard `json` module and `win32-goose`. You always specify the output path explicitly—no hardcoded log directory is assumed.

### `App`-Integrated Logging

```goose
app.log_open("logs/app.jsonl", goose_ui::LogOptions {
    min_level: goose_ui::LogLevel.Debug,
    format: goose_ui::LogFormat.JsonLines, // or LogFormat.JsonArray
    append: true,
    auto_flush: true,
    also_stderr: false,
    utc: false,
    include_process_info: true,
    create_dirs: true,
    max_file_bytes: 5 * 1024 * 1024, // 0 disables rotation
    max_backups: 3,
    log_ui_events: false,            // true logs every Signal automatically at Debug level
});

app.log_info("Application started");
app.log_warn("auth", "Token expiring soon");
app.log_error_with("io", "Failed to load asset") { f =>
    f.text("path", asset_path)
     .int("retry", 2)
     .flag("fatal", false);
    f.obj("meta") { m => m.text("backend", "software"); };
    f.arr("codes") { a => a.int(404).int(500); };
};
```

Key `App` helpers:
- Lifecycle: `log_open(path, opts?)`, `log_close()`, `log_flush()`, `log_is_open()`, `log_path()`, automatically flushed and closed by `app.destroy_all()`.
- Configuration & stats: `log_set_level(lvl)`, `log_level()`, `log_set_stderr(bool)`, `log_set_auto_flush(bool)`, `log_set_ui_events(bool)`, `log_count()`, `log_bytes_written()`.
- Emitters: `log_msg(lvl, target, msg)`, `log_with(lvl, target, msg) { f => ... }`, plus level shorthands `log_trace`, `log_debug`, `log_info`, `log_warn`, `log_error`, `log_fatal` (each supporting `(msg)`, `(target, msg)`, and `*_with(target, msg) { f => ... }`).
- Structured builders (`LogFields` / `LogArray`): `.text`, `.int`, `.uint`, `.num`, `.flag`, `.nil`, `.raw_json`, `.obj`, `.arr`, plus GUI helpers `.window_id`, `.widget_id`, `.rect`, `.color`. Filtered-out levels skip evaluating the trailing block.

### Standalone `JsonLogger` & Reading Logs

Use `goose_ui::JsonLogger` independently of `App`:

```goose
var logger = goose_ui::JsonLogger { .. };
logger.open("C:/path/to/custom.json", goose_ui::LogOptions {
    format: goose_ui::LogFormat.JsonArray,
    utc: true,
    include_process_info: false,
});
logger.info_with("worker", "Task finished") { f => f.num("ms", 12.5); };
logger.close();

let count, ok = goose_ui::each_json_log_entry("C:/path/to/custom.json") { entry =>
    print(entry.ts, " [", entry.level_text, "] ", entry.msg);
};
```

Utility functions: `log_level_name(lvl)` and `parse_log_level(s) -> LogLevel, bool`.

---

## 8. Multi-Language Support / i18n (`i18n.goose`)

`goose_ui` includes a zero-heap, live-retranslating internationalization engine with zero per-widget memory overhead when unused:

```goose
app.i18n_register_locale("en", "English");
app.i18n_register_locale("ja", "日本語");
app.set_fallback_locale("en");

app.i18n_load_json_str("en", "{\"_locale_name\":\"English\",\"ui\":{\"save\":\"Save\",\"count\":\"{n} items\"}}");
app.i18n_load_json_str("ja", "{\"_locale_name\":\"日本語\",\"ui\":{\"save\":\"保存\",\"count\":\"{n} 件\"}}");
app.i18n_load_dir("locales"); // Optional external *.json overrides or extra languages

// Auto-select based on Windows user locale (GetUserDefaultLocaleName) with fallback
app.set_system_locale("en");

// Declarative live-bound widgets in DSL
app.ui(win) { u =>
    u.tr_button("ui.save").primary().action(ID_SAVE);
    u.tr_line_edit("ui.search_ph").tr_tooltip("ui.search_tip");
};

// Switch language at runtime -> updates all bound widgets, recalculates layout,
// clears OpenGL text cache if needed, and emits Signal.LocaleChanged
app.set_locale("ja");

// Template formatting (named & positional)
let msg = app.tr_fmt("ui.count") { f => f.int("n", 42); };
```

Key APIs:
- **Catalog loading**: `i18n_register_locale`, `i18n_add`, `i18n_load_json_str`, `i18n_load_json_file`, `i18n_load_bundle_json_str`, `i18n_load_bundle_json_file`, `i18n_load_dir`, `i18n_clear`.
- **Locale control & OS detection**: `system_locale()`, `system_language()`, `set_locale(code)`, `set_system_locale(fallback)`, `set_fallback_locale(code)`, `locale()`, `locale_display_name()`, `locale_count()`, `locale_code(i)`, `locale_name_at(i)`, `has_locale(code)`, `retranslate_all()`.
- **Lookup & interpolation**: `tr(key)`, `tr_or(key, default)`, `tr_for(locale, key)`, `has_tr(key)`, `tr1`/`tr2`/`tr3`, `tr_fmt(key) { f => f.text(...).int(...).uint(...).num(...) }`.
- **Live widget bindings**: `set_tr_text`, `set_tr_placeholder`, `set_tr_tooltip`, `set_tr_window_title`, `set_tr_status_text`, `add_tr_item`, `add_tr_tab`, `clear_tr_bindings`. Manual calls to `set_text` / `set_item_text` / `set_status_text` / `set_window_title` automatically detach any prior translation binding on that target.
- **Standalone catalog**: `goose_ui::Translator` provides the full catalog, JSON/bundle/directory loader, OS detection, and formatting API independently of `App`.

---

## 9. Headless Automated Testing

Test layout geometry, pointer/keyboard interaction, and emitted `Signal`s without creating OS windows or GPU contexts (see [`test/goose_ui_test.goose`](../test/goose_ui_test.goose)):

```goose
let win = app.create_headless_window("Test", 600, 400);
// Build UI...
app.update_layout(win);

let r = app.widget_rect(btn);
app.inject_click(win, r.x + r.w * 0.5, r.y + r.h * 0.5);

var sig = goose_ui::Signal.None;
while app.next_signal(sig) {
    // Assert expected signals
}
```

Synthetic injection helpers:
`inject_mouse_move`, `inject_click`, `inject_mouse_down`, `inject_mouse_up`, `inject_mouse_wheel`, `inject_key`, `inject_char`, `inject_text`, `inject_webview_ready`, `inject_webview_navigation`, `inject_webview_title`, `inject_webview_message`, `inject_webview_script_result`.

---

## 10. Embedded WebView (`WebView2`)

`WidgetKind.WebView` embeds Microsoft Edge WebView2 directly inside any `goose_ui` layout ([`webview.goose`](../webview.goose)):

- **Zero external loader DLLs**: When `WebView2Loader.dll` is not alongside the executable, `win32-goose` discovers the installed Edge WebView2 Runtime (`EBWebView\x64\EmbeddedBrowserWebView.dll`) directly in C, keeping single-file `.exe` builds intact.
- **Zero overhead when unused**: WebView2 state lives in sparse `App.webviews` tables and loads `EmbeddedBrowserWebView.dll` lazily only when a `WebView` is created.
- **Navigation & state**: `webview_navigate`, `webview_set_html`, `webview_reload`, `webview_stop`, `webview_go_back`, `webview_go_forward`, `webview_can_go_back`, `webview_can_go_forward`, `webview_url`, `webview_title`, `webview_is_ready`, `webview_has_failed`, `webview_last_error`.
- **Bidirectional JS bridge**: `webview_eval_js` (returns `request_id` matched against `WebViewScriptResult`), `webview_add_init_script`, `webview_post_json`, `webview_post_string`, `webview_payload(s.payload)`, and `webview_payload_source(s.payload)`. Transient payload buffers are cleared automatically once drained by `app.next_signal(sig)`.
- **Theme, settings & virtual hosts**: Automatic Dark/Light scheme and background sync (`WebViewColorScheme.FollowTheme`), `webview_set_zoom`, `webview_set_muted`, `webview_is_muted`, `webview_is_playing_audio`, `webview_set_devtools_enabled` / `webview_open_devtools`, `webview_set_context_menu_enabled`, `webview_set_status_bar_enabled`, `webview_set_zoom_control_enabled`, `webview_set_accelerator_keys_enabled`, `webview_set_user_agent`, `webview_set_new_window_policy`, `webview_set_virtual_host`, `webview_clear_virtual_host`.
- **Container & airspace notes**: `sync_window_webviews` automatically hides inactive `TabWidget` / `Stack` pages and clips child `HWND`s against `ScrollArea` viewports via `SetWindowRgn`. Because WebView2 uses a native Win32 child `HWND`, overlapping `goose_ui`-painted `ComboBox` dropdowns or hover tooltips render beneath the native child `HWND` (standard Win32 airspace behavior).
