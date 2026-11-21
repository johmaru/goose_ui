# Widgets, Events & Native API Reference

---

## 1. Widget Catalog (21 Retained Widgets)

### Containers & Structural Widgets
`Panel`, `Frame`, `GroupBox`, `Spacer`, `Separator`, `TabWidget`, `ScrollArea`, `Splitter`, `StatusBar`

### Leaf Widgets (DSL Builders)

| DSL Method | Description & Features |
| --- | --- |
| `u.label(text, role = FontRole.Body)` | Single-line text label (`.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`) |
| `u.button(text, variant = Default)` | Push button with 5 variants (`.primary()`, `.secondary()`, `.danger()`, `.ghost()`) and optional `.checkable()` toggle state |
| `u.checkbox(text, checked = false)` | CheckBox emitting `Toggled` and `Clicked` |
| `u.radio(text, checked = false)` | RadioButton with automatic mutual exclusivity among siblings |
| `u.toggle(text, checked = false)` | Modern animated-style ToggleSwitch emitting `Toggled` and `Clicked` |
| `u.line_edit(placeholder = "", initial_text = "")` | Single-line text input with UTF-8 / CJK / emoji (surrogate pair) support, selection, Home/End/Arrows, `Ctrl+A/C/X/V` via Windows Clipboard, `.password()`, `.read_only()` |
| `u.slider(min, max, initial, step, orientation)` | Horizontal or vertical slider supporting pointer drag, mouse wheel, and arrow keys |
| `u.spin_box(min, max, initial, step, decimals)` | Numeric input with `+/-` buttons, mouse wheel, and arrow keys |
| `u.progress_bar(min, max, initial)` | Progress bar with optional percentage label (`app.set_show_percentage`) |
| `u.combo_box()` | Dropdown selector with top-level floating overlay, wheel scrolling for >8 items, `Esc` / `Space` / `Enter` support, and `.item(text)` |
| `u.list_view(item_height = 30.0)` | Virtualized scrollable list with primary text, subtext, `item_tag`, keyboard navigation with auto-scroll, and double-click activation |
| `u.canvas(min_w = 200.0, min_h = 160.0)` | Custom 2D vector & text drawing surface with local mouse and wheel events |

### Status Bar

Docked to the bottom edge of a top-level window:

```goose
app.set_status_bar(win, "Ready");
// Update at any time (reuses pooled string capacity in place)
app.set_status_text(win, "Saved successfully");
```

### Common `Node` Modifiers (UFCS Chains)

- **Identity & Binding**: `.action(id)`, `.name("...")`, `.bind(var_id)`, `.widget()`
- **Layout**: `.stretch(s)`, `.fixed(w, h)`, `.width(w)`, `.height(h)`, `.min_size(w, h)`, `.max_size(w, h)`, `.policy(h, v)`, `.align(h, v)`, `.padding(all)`, `.spacing(sp)`, `.bounds(x, y, w, h, anchor, ref_w, ref_h)`
- **Typography**: `.heading()`, `.subheading()`, `.bold()`, `.caption()`, `.mono()`, `.center()`, `.text_align(h, v)`
- **Appearance**: `.primary()`, `.secondary()`, `.danger()`, `.ghost()`, `.checkable()`, `.bg(c)`, `.fg(c)`, `.border(c, w)`, `.radius(r)`
- **State & Input**: `.tooltip("...")`, `.placeholder("...")`, `.password()`, `.read_only()`, `.enabled(bool)`, `.visible(bool)`
- **Items**: `.item(text, subtext = "", tag = 0)`, `.select(idx)`
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

---

## 6. Themes & Styling

- Built-in themes: `theme_dark()`, `theme_light()`
- Live switching: `app.set_theme(custom_theme)` / `app.toggle_theme()` (automatically syncs Windows 11 DWM dark titlebars)
- Color utilities: `rgb(r, g, b)`, `rgba(r, g, b, a)`, `color_hex(0x3B82F6, a = 1.0)`, `with_alpha(c, a)`, `lerp_color(a, b, t)`

---

## 7. Headless Automated Testing

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
`inject_mouse_move`, `inject_click`, `inject_mouse_down`, `inject_mouse_up`, `inject_mouse_wheel`, `inject_key`, `inject_char`, `inject_text`.
