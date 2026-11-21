# UI DSL & Layout Guide

`goose_ui` combines a **SwiftUI / Jetpack Compose-style scoped nested DSL**, **Win32-style integer action IDs**, and optional **WinForms / Win32-style `Anchor` absolute positioning** (implemented in [`dsl.goose`](../dsl.goose) and [`layout.goose`](../layout.goose)).

---

## 1. Scoped Nested DSL Basics

Use `app.ui(win) { u => ... }` to describe the widget hierarchy directly with lexical nesting:

- `Ui { app: App&, parent: WidgetId }` (16-byte value handle): current container builder cursor
- `Node { app: App&, id: WidgetId }` (16-byte value handle): fluent modifier handle for a newly created widget

Both compile down to registers with zero runtime allocation overhead.

```goose
let ID_INPUT = 100;
let ID_ADD   = 101;
let ID_LIST  = 102;

app.ui(win) { u =>
    u.padding(16.0).spacing(10.0);

    u.hbox(8.0) { row =>
        row.line_edit("Enter a task...").stretch(1.0).action(ID_INPUT);
        row.button("Add").primary().action(ID_ADD);
    };

    u.list_view(34.0).stretch(1.0).action(ID_LIST);
};
```

To dynamically append children into an existing container `WidgetId`, use `app.ui_in(container) { u => ... }`.

### Referencing Created Widgets

Choose whichever style fits your workflow:

1. **Win32-style action IDs (recommended)**: Attach `.action(ID_*)` and inspect `app.action_id(s.widget)` or use `app.by_id(win, ID_*)`, `app.text_of(win, ID_*)`, `app.set_text_of(win, ID_*, ...)`.
2. **Variable binding**: Declare `var my_btn = goose_ui::WIDGET_NONE;` and chain `.bind(my_btn)` (or extract the `WidgetId` directly via `.widget()`).
3. **Name lookup**: Attach `.name("submit_btn")` and look it up via `app.find_by_name(win, "submit_btn")`.

---

## 2. Layout Containers (DSL Methods)

Every container accepts a trailing block and returns its own `Node`, so you can chain `.stretch(1.0)`, `.fixed(w, h)`, `.bind(...)`, etc. directly after the closing brace.

| DSL Method | Description | Default Arguments |
| --- | --- | --- |
| `u.vbox(spacing, padding) { v => ... }` | Vertical box layout (`LayoutKind.VBox`) | `spacing = 8.0, padding = 0.0` |
| `u.hbox(spacing, padding) { h => ... }` | Horizontal box layout (`LayoutKind.HBox`) | `spacing = 8.0, padding = 0.0` |
| `u.grid(columns, spacing, padding) { g => ... }` | Equal-width N-column grid (`LayoutKind.Grid`) | `columns = 2, spacing = 8.0, padding = 0.0` |
| `u.form(label_width, spacing, padding) { f => ... }` | Two-column label + field form (`LayoutKind.Form`, pairs consecutive children) | `label_width = 130.0, spacing = 10.0, padding = 0.0` |
| `u.stack(padding) { s => ... }` | Stacked page container (`LayoutKind.Stack`, shows only `selected_index`) | `padding = 0.0` |
| `u.frame(layout, spacing, padding) { f => ... }` | Card / container with surface background and subtle border | `layout = VBox, spacing = 8.0, padding = 12.0` |
| `u.group_box(title, layout, spacing, padding) { g => ... }` | Titled group container | `layout = VBox, spacing = 8.0, padding = 12.0` |
| `u.scroll_area(spacing, padding) { sc => ... }` | Vertically scrollable viewport with wheel & scrollbar support | `spacing = 8.0, padding = 10.0` |
| `u.splitter(orientation, ratio) { sp => ... }` | Two-pane container with a draggable divider | `orientation = Horizontal, ratio = 0.35` |
| `u.tabs() { t => t.tab("Title") { p => ... }; }` | Tabbed container (`TabWidget` + per-tab `Panel` pages) | `layout = VBox, spacing = 10.0, padding = 12.0` |
| `u.anchored_panel(padding) { a => ... }` | Win32 / WinForms-style absolute positioning + `Anchor` panel (`LayoutKind.None`) | `padding = 0.0` |

### Configuring the Current Container (`Ui` Methods)

You can configure the current container at the top of its block:

```goose
u.padding(16.0).spacing(10.0).bg(goose_ui::color_hex(0x1E222F)).radius(8.0);
```

Available `Ui` methods:
`padding`, `padding_m`, `spacing`, `stretch`, `fixed`, `width`, `height`, `min_size`, `bg`, `border`, `radius`, `action`, `name`, `bind`, `layout_kind`, `self_node`, `id`.

---

## 3. Two-Pass Layout Engine

`goose_ui`'s layout engine (`update_layout(win)`) runs in two passes, similar to Qt:

1. **Measure pass (`measure_widget`)**: Computes bottom-up intrinsic `size_hint` from text metrics, `padding`, `spacing`, `min_size`, `max_size`, and `fixed_w` / `fixed_h`.
2. **Arrange pass (`layout_widget`)**: Distributes final bounding rectangles (`rect` / `content_rect`) top-down from parent to children.

### Sizing & Alignment Modifiers

| Modifier | Purpose |
| --- | --- |
| `.stretch(weight)` | Shares remaining `VBox`/`HBox` space proportionally (e.g. `1.0` vs `2.0` gives a 1:2 split) |
| `.fixed(w, h)` / `.width(w)` / `.height(h)` | Sets fixed dimensions (and `SizePolicy.Fixed`) |
| `.min_size(w, h)` / `.max_size(w, h)` | Minimum and maximum size constraints (applied on both main and cross axes) |
| `.policy(h, v)` | Explicit `SizePolicy` (`Fixed`, `Minimum`, `Preferred`, `Expanding`) |
| `.align(h, v)` | Alignment inside parent cell (`Align.Start`, `Center`, `End`, `Stretch`) |
| `u.spacer(stretch)` | Flexible empty space (useful for right-aligning button rows) |
| `u.separator(orientation)` | Horizontal or vertical divider line |

```goose
// Common pattern: right-aligned dialog buttons
u.hbox(8.0) { bar =>
    bar.spacer(1.0);
    bar.button("Cancel").secondary();
    bar.button("Save").primary();
};
```

---

## 4. Win32 / WinForms-Style Absolute Positioning & `Anchor`s

For dialogs or inspectors where exact pixel coordinates are preferable, use `.bounds(x, y, w, h, anchor)` inside `u.anchored_panel()`:

```goose
u.anchored_panel() { dlg =>
    // Pinned to top-left
    dlg.label("Host:").bounds(16.0, 20.0, 100.0, 28.0, goose_ui::ANCHOR_TOP_LEFT);

    // Stretches horizontally while preserving left/right margins
    dlg.line_edit("localhost:8080")
       .bounds(124.0, 18.0, 240.0, 32.0, goose_ui::ANCHOR_H_STRETCH)
       .action(ID_HOST);

    // Stays pinned to the bottom-right corner on resize
    dlg.button("OK").primary()
       .bounds(276.0, 140.0, 88.0, 32.0, goose_ui::ANCHOR_BOTTOM_RIGHT)
       .action(ID_OK);
}.stretch(1.0);
```

### `ANCHOR_*` Bitmasks

| Constant | Bitmask | Resize Behavior |
| --- | --- | --- |
| `ANCHOR_NONE` | `0` | Static position & size (does not shift or stretch on resize) |
| `ANCHOR_TOP_LEFT` (default) | `LEFT \| TOP` | Fixed offset from top-left |
| `ANCHOR_TOP_RIGHT` | `TOP \| RIGHT` | Fixed offset from top-right |
| `ANCHOR_BOTTOM_LEFT` | `LEFT \| BOTTOM` | Fixed offset from bottom-left |
| `ANCHOR_BOTTOM_RIGHT` | `RIGHT \| BOTTOM` | Fixed offset from bottom-right |
| `ANCHOR_H_STRETCH` | `LEFT \| TOP \| RIGHT` | Fixed top; width stretches with parent |
| `ANCHOR_V_STRETCH` | `LEFT \| TOP \| BOTTOM` | Fixed left; height stretches with parent |
| `ANCHOR_ALL` | `LEFT \| TOP \| RIGHT \| BOTTOM` | Stretches in both directions preserving all margins |

> **Reference size (`ref_w`, `ref_h`)**: When `ref_w` / `ref_h` are omitted (`0.0`), the layout engine lazily captures the parent container's initial inner dimensions on the first layout pass (accounting for padding and docked `StatusBar`). Pass explicit design dimensions such as `.bounds(x, y, w, h, anchor, 400.0, 220.0)` when you want a fixed reference frame.

---

## 5. Interoperability with the Low-Level Qt-Style API

The DSL is a zero-cost wrapper around the `add_*` / `set_*` functions in [`tree.goose`](../tree.goose). You can mix both styles freely, e.g. when creating or destroying widgets dynamically at runtime:

```goose
let root = app.root(win);
let row = app.add_hbox(root, 8.0, 0.0);
let btn = app.add_button(row, "Click", goose_ui::ButtonVariant.Primary);
app.set_stretch(btn, 1.0);

// Dynamic teardown (recursively cleans up children, ListItems, and Connections)
app.destroy_widget(row);
```
