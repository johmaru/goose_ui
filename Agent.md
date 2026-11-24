# Agent.md — goose_ui Developer & Maintenance Guide

This repository contains **`goose_ui`**, a **retained-mode, zero-heap GUI framework** for the Goose programming language (v2026.4+). It builds purely in Goose on top of the [`win32-goose`](https://github.com/johmaru/win32-goose) git submodule without introducing any additional C code.

---

## 1. Architecture & Invariants

- **Fix root causes in `win32-goose/` when needed**: Keep `goose_ui` itself pure Goose with no extra C files under `goose_ui/`. However, when a bug or missing low-level Win32/Direct2D/OpenGL primitive originates in the `win32-goose/` submodule, **fix or add it directly in `win32-goose/`** rather than relying on fragile workarounds in `goose_ui/`, and run `win32-goose/test/win32_test.goose` (`goose run --debug` and native `goose build`) alongside `goose_ui`'s test suite.
- **Package config (`goose_ui.build`)**: Keep `main_thread_only = true;` and `exclude = ["win32-goose", "examples", "test", "bench"];`.
- **Root file import convention**: External entry files (`examples/`, `test/`, `bench/`, user apps) must explicitly import both transitive and direct packages:
  ```goose
  import win32 from "../win32-goose";
  import goose_ui from "..";
  ```
- **Zero-heap design (`root struct App`)**:
  - All state (`windows`, `widgets`, `free_widgets`, `str_pool`, `list_items`, `connections`, `timers`, `signals`, `focus_order`) lives in independent data stacks owned by `root struct App`.
  - Due to Goose v1 constraints, another `root struct` cannot be nested by value inside `App`, so `App` owns `[>..]` / `[>..<]` arrays directly.
- **Keep memory layout compact**:
  - Store `Widget` / `ListItem` strings (`text`, `placeholder`, `tooltip`, `name`, `subtext`) in `App.str_pool` via 12-byte `StrSpan` handles; never reintroduce large inline `u8[..N]` buffers (~350 B/widget, 0-byte in-place updates within existing capacity).
  - Keep `WidgetStyle` compact with packed `u32` RGBA values and bit flags.

---

## 2. Dual Rendering Backend Rules

- **`RenderBackend.Software` (Double-buffered GDI + ClearType)**:
  - **Never call `d2d_create`** on this path so the ~56 MB GPU driver baseline is avoided (~9.2 MB empty window, ~11.3 MB at 5,000 controls, ~36 ms first paint).
  - Fonts are created via `gdi32` `CreateFontA` (`CLEARTYPE_QUALITY = 5`), text uses `DT_NOPREFIX`, and scroll/canvas regions use `SaveDC` / `IntersectClipRect` / `RestoreDC`.
- **`RenderBackend.Direct2D` (Direct2D + DirectWrite GPU)**:
  - `win32-goose` caps global D2D fonts at `W32_MAX_D2D_FONTS = 64`; stay at 6 fonts per window (`FontSet`), disable DirectWrite word wrapping (`set_word_wrap(false)`) for single-line controls (paired with `D2D1_DRAW_TEXT_OPTIONS_CLIP` in `win32-goose`), switch alignment via `set_align` right before `draw_text`, and measure text directly with `d2d.measure_text`.
  - Hardware clipping uses `d2d.push_clip` / `d2d.pop_clip` (`PushAxisAlignedClip` / `PopAxisAlignedClip`) for `ScrollArea`, `ListView`, and `Canvas`.
- **Backend parity**: Keep `Painter` primitives, hardware clip stacks (`d2d.push_clip` in D2D, `SaveDC`/`IntersectClipRect` in GDI, `gl2d.push_clip` in OpenGL), and `Canvas` local coordinate translation consistent across all backends.

---

## 3. UI Authoring Style

- **Recommended style (`dsl.goose`)**:
  - Scoped nested DSL (`app.ui(win) { u => ... }` + 16-byte `Ui` / `Node` UFCS chains)
  - Win32-style action IDs (`.action(ID_*)` → `match app.action_id(s.widget)`, `app.by_id` / `app.text_of` / `app.set_text_of`)
  - Declarative `app.connect(...)` / `.on_toggle_theme()` for reactive bindings
- **Absolute positioning escape hatch**: Use `u.anchored_panel()` (`LayoutKind.None`) + `.bounds(x, y, w, h, ANCHOR_*)` for pixel-exact dialogs with resize anchors.
- Maintain the low-level Qt-style API (`add_*` / `set_*`) for backwards compatibility and dynamic tree mutations.

---

## 4. Goose v2026.4 Compiler & Language Caveats

Important language details encountered while building this repository:

1. **`pad` is a reserved keyword**: Used for struct padding; use `padding` or `pd` for identifiers.
2. **Truncating float→int casts require `as!`**: Under `--debug`, `float as i32` / `as i64` aborts if a fractional part exists. Always use `as!` for intentional truncation.
3. **No redundant widening casts**: Casting `i32 -> f32`, `f32 -> f64`, or `u8 -> i64` explicitly emits warnings. Always maintain **0 errors / 0 warnings**.
4. **Multiple return values with `match`**: `return match x { ... }` cannot return multiple values; return explicitly inside each arm (`return a, b;`).
5. **Enum wildcard is `_`**: Any other identifier is parsed as an enum variant name.
6. **Function values (higher-order functions)**:
   - Function values are only allowed as compile-time generic parameters, never runtime parameters.
   - When a function takes two callbacks (e.g. `exec_with_canvas<OnPaint, OnSignal>(app: App&)`), pass the first by name and the second as a trailing block: `app.exec_with_canvas(paint_fn) { sig => ... };`.
   - `continue` cannot be used inside a trailing block outside a loop.
7. **Recursive functions (`recursive fn`)**: Require explicit parameter/return types and must not keep local growable arrays (`[>..]` / `[>..<]`) alive across recursive calls.
8. **TinyCC codegen workaround**: Passing unit enum variants directly to an enum parameter can fail in TinyCC (`cannot convert '..._p' to '...'`); internal dispatchers such as `run_connections` use integer codes (`signal_kind_code`).
9. **Win32 event coverage**: `win32-goose`'s `w32_wndproc` forwards mouse, keyboard, `WM_CHAR`, `WM_SIZE`, `WM_PAINT`, `WM_COMMAND`, `WM_TIMER`, `WM_DROPFILES`, and `WM_DPICHANGED` (`WM_NOTIFY` / `WM_HSCROLL` are not forwarded). Double-click timing is handled in Goose using `tick_count_ms()`.

---

## 5. Verification & Benchmark Commands

After any code change, verify **0 errors / 0 warnings**, JIT `--debug` execution, and native Clang builds:

```powershell
# Type-check all entry points
goose check test/goose_ui_test.goose
goose check examples/counter.goose
goose check examples/todo_app.goose
goose check examples/kitchen_sink.goose
goose check bench/goose_ui_bench.goose

# Run automated test suite with debug checks
goose run --debug test/goose_ui_test.goose

# Native Clang build & run
goose build test/goose_ui_test.goose && .\test\goose_ui_test.exe

# Memory & startup benchmarks (vs Qt 6.11.1 Widgets / Quick / Python Tkinter)
pwsh -File bench/run_bench.ps1
```

Delete generated build artifacts (`*.exe`, `bench/results.json`) before committing.

---

## 6. Documentation Sync Rules

Whenever public APIs, DSL builders, widgets, backends, or benchmark numbers change, keep these files in sync (in English):
- `README.md` — Project overview, quick start, benchmark tables, documentation index
- `docs/getting-started.md` — Setup, backend selection, build commands
- `docs/dsl-and-layout.md` — Nested DSL, layout containers, two-pass layout, `Anchor` absolute placement
- `docs/widgets-and-events.md` — All 21 widgets, `Signal`, `connect`, `Canvas`/`Painter`, Win32 integrations, headless testing
- `docs/architecture.md` — `root struct App`, `str_pool`, dual backends, benchmark details
