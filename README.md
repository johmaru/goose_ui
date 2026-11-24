# goose_ui

A **zero-heap, dual-backend retained-mode GUI framework** for the [Goose](https://github.com/aardappel/goose) programming language, built purely in Goose on top of the [`win32-goose`](https://github.com/johmaru/win32-goose) git submodule (**Software GDI + ClearType** and **Direct2D + DirectWrite GPU**).

## Highlights

- **Zero heap allocations & zero extra C code** — All windows, widgets, pooled strings (`str_pool`), list items, connections, timers, and signals live inside a single Goose `root struct App` backed by compiler-managed data stacks (~350 bytes/widget + exact string bytes in `str_pool`).
- **Dual Rendering Backends (`RenderBackend.Software` & `RenderBackend.Direct2D`)** — Switch between ultra-lightweight double-buffered **GDI + ClearType** (~9.2 MB Private RAM, ~36 ms first paint for 5,000 controls, zero GPU driver overhead) and hardware-accelerated **Direct2D + DirectWrite** GPU rendering via `app.init(true, RenderBackend.Software)` or `app.set_backend(...)`.
- **Best-of-both-worlds UI Authoring (`dsl.goose`)** — Combine SwiftUI / Jetpack Compose-style scoped nested layouts (`app.ui(win) { u => ... }`), fluent UFCS modifier chaining, Win32-style integer action IDs (`.action(ID_*)` + `app.action_id` / `app.text_of`), declarative `connect` bindings, and optional Win32 / WinForms-style absolute positioning with resize `Anchor`s (`u.anchored_panel()` + `.bounds(..., ANCHOR_*)`).
- **Two-pass Qt-style layout engine** — Intrinsic `size_hint` measurement + top-down arrangement:
  - `VBox`, `HBox` (proportional `stretch` & `SizePolicy`), `Grid`, `Form`, `Stack`
  - `Splitter` (draggable horizontal/vertical panes), `ScrollArea`, `TabWidget`, `GroupBox`, `Frame`, `Panel`, `Spacer`, `Separator`, docked `StatusBar`, and `LayoutKind.None` (`Anchor`)
- **21 Retained Widgets with Full UTF-8 / CJK Support** — Hover/pressed/disabled states, focus rings, Tab/Shift+Tab keyboard navigation, and hover tooltips:
  - `Label`, `Button` (5 variants + checkable toggle), `CheckBox`, `RadioButton` (auto-exclusive), `ToggleSwitch`
  - `LineEdit` (UTF-8 & surrogate-pair emoji input, selection, Home/End/Arrows, Copy/Cut/Paste via Windows Clipboard, password mode, placeholder)
  - `Slider` (horizontal/vertical, drag/wheel/arrows), `SpinBox`, `ProgressBar`
  - `ComboBox` (floating top-level dropdown overlay), `ListView` (virtualized scrolling, keyboard nav, double-click activation)
  - `Canvas` (custom `QPainter`-style 2D vector & text drawing surface inside any layout, working on both GDI and Direct2D)
- **Native Windows 11 Integration** — DWM dark titlebar synced with live Dark/Light theme switching, rounded corners, native Win32 MenuBar & Context Menus, Common Dialogs (Open/Save/Folder/Color/Input/MessageBox), Clipboard, `QTimer`-style timers, and Drag & Drop files.
- **Structured JSON Logging (`log.goose`)** — User-specified output path (auto-creating parent directories), `JsonLines` (NDJSON) and `JsonArray` formats, size-based file rotation, fluent `LogFields`/`LogArray` builders, `App`-integrated & standalone `JsonLogger` APIs, optional automatic `Signal` tracing, and `each_json_log_entry`.

## Documentation

| Document | Contents |
| --- | --- |
| [Getting Started (`docs/getting-started.md`)](docs/getting-started.md) | Prerequisites, submodule setup, backend selection, minimal app lifecycle, and standalone `.exe` builds |
| [UI DSL & Layout Guide (`docs/dsl-and-layout.md`)](docs/dsl-and-layout.md) | Scoped nested DSL, all layout containers, two-pass layout rules, Win32/WinForms-style `Anchor` absolute placement, and low-level API |
| [Widgets, Events & Native API (`docs/widgets-and-events.md`)](docs/widgets-and-events.md) | All 21 widgets, fluent modifiers, `Signal` dispatch, Win32 action IDs, declarative `connect`, `Canvas`/`Painter`, native dialogs/menus, and headless testing |
| [Architecture & Performance (`docs/architecture.md`)](docs/architecture.md) | Zero-heap `root struct App`, generational handles, `str_pool` + `StrSpan`, Software GDI / Direct2D dual backends, and benchmark methodology |
| [Developer & Agent Guide (`Agent.md`)](Agent.md) | Maintenance invariants, Goose v2026.4 compiler caveats, and verification commands |

## Qt / Win32 → goose_ui Concept Mapping

| Qt / Win32 | `goose_ui` |
| --- | --- |
| `QApplication` | `root struct App` (`app.init()`, `app.exec() { sig => ... }`) |
| `QMainWindow` | `app.create_window(...)`, `app.create_menu_bar(...)`, `app.set_status_bar(...)` |
| `QWidget` / `QObject` | `WidgetId` generational handle + parent-child tree + `destroy_widget` / `find_by_name` |
| `QVBoxLayout` / `QHBoxLayout` | `u.vbox(...) { ... }` / `u.hbox(...) { ... }` (or `add_vbox` / `add_hbox`) |
| `QGridLayout` / `QFormLayout` / `QStackedLayout` | `u.grid(...)` / `u.form(...)` / `u.stack()` |
| `QSplitter` / `QScrollArea` / `QTabWidget` | `u.splitter(...)` / `u.scroll_area(...)` / `u.tabs() { t => t.tab(...) { ... }; }` |
| Win32 Control IDs (`WM_COMMAND`) | `.action(ID_*)` + `app.action_id(s.widget)` + `app.by_id` / `app.text_of` / `app.set_text_of` |
| WinForms `Anchor` Absolute Layout | `u.anchored_panel()` + `.bounds(x, y, w, h, ANCHOR_*)` |
| `QObject::connect` | `app.connect(sender, SignalKind, receiver, SlotAction)` / `.on_toggle_theme()` + `Signal` dispatch |
| `QPainter` | `Canvas` widget + `Painter` in `app.exec_with_canvas(paint_fn) { sig => ... }` |
| `QPalette` / `QStyle` | `Theme` (`theme_dark()`, `theme_light()`, `app.set_theme(...)`, `.bg()`/`.fg()`/`.border()`) |
| `QMenuBar` / `QMenu` / `QDialog` / `QTimer` | `create_menu_bar`, `open_file_dialog`, `choose_color_dialog`, `input_dialog`, `msg_*`, `start_timer` |

## Quick Start

Clone with submodules:

```powershell
git clone --recursive https://github.com/johmaru/goose_ui.git
# Or if already cloned:
git submodule update --init --recursive
```

Run tests and interactive examples (instant JIT via `goose run`, or standalone native binary via `goose build`):

```powershell
# Run automated test suite (headless layout/state/signal tests + Win32 GDI/D2D smoke tests)
goose run --debug test/goose_ui_test.goose

# Interactive examples
goose run examples/counter.goose
goose run examples/todo_app.goose
goose run examples/kitchen_sink.goose

# Build standalone native Windows executable (~386 KB single .exe)
goose build examples/kitchen_sink.goose
```

## Minimal Example (Scoped DSL + Win32-style Action IDs)

```goose
import std;
import win32 from "../win32-goose";
import goose_ui from "..";

let ID_INC = 101;
let ID_VAL = 200;

fn main() {
    var app = goose_ui::App { .. };
    // RenderBackend.Software (GDI + ClearType, ~9-11 MB RAM) or RenderBackend.Direct2D (GPU)
    app.init(true, goose_ui::RenderBackend.Software);

    let win = app.create_window("Hello goose_ui", 400, 240);

    app.ui(win) { u =>
        u.padding(18.0).spacing(12.0);
        u.hbox(8.0) { hdr =>
            hdr.label("Counter").heading().stretch(1.0);
            hdr.toggle("Dark", true).on_toggle_theme();
        };
        u.label("Count: 0").heading().center().stretch(1.0).action(ID_VAL);
        u.button("+1").primary().action(ID_INC);
    };

    var count = 0;
    app.show_window(win);

    app.exec() { sig =>
        match sig {
            Clicked s => match app.action_id(s.widget) {
                ID_INC => {
                    count += 1;
                    app.set_text_of(win, ID_VAL, str("Count: ", count));
                },
                _ => {},
            },
            _ => {},
        }
    };
}
```

## Benchmarks (vs Qt 6.11.1 & Python Tkinter)

Measured in isolated processes on **Windows 11 x64** (NVIDIA GeForce RTX 5070 Ti, **Goose v2026.4 + Clang `-O2`**, **Qt 6.11.1 MinGW `g++ -O2`**, **Python 3.14 Tkinter**) using `K32GetProcessMemoryInfo` (`PROCESS_MEMORY_COUNTERS_EX`) right after constructing, laying out, and rendering `N` mixed controls (`Label`, `LineEdit`, `CheckBox`, `ProgressBar`, `Button` inside a `ScrollArea`).

### Private Bytes (Committed Process RAM, MB)

| Framework | Backend | 0 controls | 100 controls | 1,000 controls | 5,000 controls | Per-Widget Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | GDI + ClearType (CPU) | **9.17 MB** | 10.38 MB | **10.34 MB** | **11.25 MB** | **~350 B** |
| **`goose_ui` (Headless)** | Pure Data Stack | 8.09 MB | 9.15 MB | 9.12 MB | 10.30 MB | ~370 B |
| **Qt 6.11.1 Widgets** | C++ Raster (CPU) | 10.05 MB | 9.79 MB | 14.11 MB | 27.84 MB | ~2,965 B (8.5×) |
| **`goose_ui` (Direct2D)** | Direct2D + DirectWrite (GPU) | **65.05 MB** | **66.76 MB** | **66.18 MB** | **67.57 MB** | **~420 B** |
| **Qt 6.11.1 Quick / QML** | Direct3D 11 RHI (GPU) | 88.37 MB | 104.19 MB | 180.85 MB | — | ~77 KB (~220×) |
| **Python 3.14 Tkinter** | Tcl/Tk (CPU) | 14.40 MB | 16.58 MB | 21.52 MB | — | ~5.9 KB (17×) |

### Working Set (Resident RAM), First-Frame Latency & Deployment Size

| Framework | 0 ctrl WS | 1,000 ctrl WS | 5,000 ctrl WS | 1,000 ctrl Time | 5,000 ctrl Time | Distributable Size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | **21.97 MB** | **22.30 MB** | **24.02 MB** | **32.7 ms** | **35.8 ms** | **386 KB** (single `.exe`) |
| **`goose_ui` (Direct2D)** | 55.18 MB | 56.59 MB | 58.08 MB | 216.3 ms | 197.6 ms | **386 KB** (single `.exe`) |
| **Qt 6.11.1 Widgets** | 42.29 MB | 48.13 MB | 63.86 MB | 317.9 ms | 380.9 ms | 32.3 MB (`exe` + Qt/MinGW DLLs) |
| **Qt 6.11.1 Quick / QML** | 92.74 MB | 177.52 MB | — | 673.0 ms | — | > 40 MB (Qt/QML/Controls DLLs) |
| **Python 3.14 Tkinter** | 31.81 MB | 51.31 MB | — | 1,435.7 ms | — | Python + Tcl/Tk runtime |

Key takeaways:
- **CPU vs CPU (`goose_ui` Software vs Qt 6 Widgets):** At 5,000 controls, `goose_ui` uses **2.5× less Private RAM**, **2.7× less Working Set**, **8.5× less RAM per widget**, and reaches first paint **10.6× faster** (`35.8 ms` vs `380.9 ms`).
- **GPU vs GPU (`goose_ui` Direct2D vs Qt 6 Quick):** The ~56 MB base difference between `Software` and `Direct2D` is the OS/GPU driver context (`d2d1.dll` / `d3d11.dll` / NVIDIA). Against Qt 6 Quick (also GPU-accelerated), `goose_ui` uses **2.7× less Private RAM**, **3.1× less Working Set**, and renders **3.1× faster** at 1,000 controls.
- **Zero-heap contiguous storage:** All 6,003 widget nodes + 31.8 KB of pooled text in `App.str_pool` build and lay out in **2.3 ms** (headless) with zero heap allocations and **88× smaller** standalone binary footprint than Qt 6.

Reproduce locally:

```powershell
pwsh -File bench/run_bench.ps1
```

## Repository Layout

- `goose_ui.goose` / `goose_ui.build` — Goose package entry point and build configuration
- `types.goose` — Geometry, `Color`, handles (`WindowId`, `WidgetId`), `RenderBackend`, `StrSpan`, `ANCHOR_*`, enums, `Signal`, `Connection`
- `theme.goose` — Dark & Light themes, compact packed `WidgetStyle`, UTF-8 text width metrics
- `widget.goose` — Retained `Widget`, `ListItem`, `Window`, `TimerInfo`, and `root struct App` (with `str_pool`)
- `tree.goose` — Window & widget lifecycle, string pool, GDI/D2D font caches, constructors, property getters/setters, Win32-style ID lookups, `connect`
- `log.goose` — Structured JSON logging (`JsonLines` / `JsonArray`, rotation, `LogFields`, `JsonLogger`, `App` integration, `each_json_log_entry`)
- `layout.goose` — Two-pass Qt-style layout engine (`measure_widget` / `layout_widget`) + `Anchor` absolute positioning
- `painter.goose` — Dual-backend `Painter` (Software GDI + ClearType & Direct2D + DirectWrite), widget renderers, overlays & tooltips
- `events.goose` — Hit testing, focus traversal, LineEdit/Slider/Splitter/List/Tab interaction, event loop, synthetic test injection
- `native.goose` — Win32 MenuBar, Context Menus, Common Dialogs, MessageBox, Clipboard, Timers, Drop files
- `dsl.goose` — SwiftUI/Compose-style scoped nested UI builder (`app.ui(win) { u => ... }`), fluent modifiers, Win32 action IDs, and `Anchor` placement
- `win32-goose/` — Git submodule ([`johmaru/win32-goose`](https://github.com/johmaru/win32-goose))
- `docs/` — Guides and API references
- `examples/` — `counter.goose`, `todo_app.goose`, `kitchen_sink.goose`
- `bench/` — Reproducible memory & latency benchmarks (`goose_ui_bench.goose`, `qt6_bench.cpp`, `qt6_quick_bench.cpp`, `tk_bench.py`, `run_bench.ps1`)
- `test/goose_ui_test.goose` — Automated test suite
