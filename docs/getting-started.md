# Getting Started with goose_ui

`goose_ui` is a pure-Goose, zero-heap retained-mode GUI framework for the Goose programming language (v2026.4+). Built on top of the [`win32-goose`](https://github.com/johmaru/win32-goose) git submodule, it supports switching between two rendering backends: **Software GDI + ClearType** and **Direct2D + DirectWrite (GPU)**.

---

## 1. Prerequisites

- **OS**: Windows 10 / 11 (x64)
- **Goose compiler**: v2026.4 or later (`goose` available on `PATH`)
- **Clang (optional, for native builds)**: Required when compiling standalone `.exe` binaries with `goose build` (`goose run` uses the built-in TinyCC JIT with no extra toolchain)

---

## 2. Clone & Verify

`win32-goose` is included as a git submodule:

```powershell
git clone --recursive https://github.com/johmaru/goose_ui.git
# Or if already cloned:
git submodule update --init --recursive
```

Run the automated test suite and the three interactive examples:

```powershell
# Automated test suite (JIT with debug assertions & bounds checks)
goose run --debug test/goose_ui_test.goose

# Interactive examples
goose run examples/counter.goose       # Software GDI: Counter
goose run examples/todo_app.goose      # Software GDI: Todo manager + native menu bar
goose run examples/kitchen_sink.goose  # Direct2D GPU: All widgets + Canvas animation
```

---

## 3. Creating a New Application

### Import Convention

Because of Goose's package dependency resolution rules, external root files (such as your own `main.goose`) must import **both `win32-goose` and `goose_ui`**:

```goose
import std;
import win32 from "./path/to/goose_ui/win32-goose";
import goose_ui from "./path/to/goose_ui";
```

Inside this repository (`examples/`, `test/`, `bench/`), use relative paths:

```goose
import std;
import win32 from "../win32-goose";
import goose_ui from "..";
```

### Minimal Application Lifecycle

```goose
fn main() {
    // 1. Create the root App state container (zero heap allocations)
    var app = goose_ui::App { .. };

    // 2. Initialize: (dark_theme, backend)
    app.init(true, goose_ui::RenderBackend.Software);

    // 3. Create a top-level window
    let win = app.create_window("My App", 640, 420);

    // 4. Build the UI tree with the scoped nested DSL
    app.ui(win) { u =>
        u.padding(16.0).spacing(10.0);
        u.label("Hello, goose_ui!").heading();
        u.button("Close").primary().on_click_close();
    };

    // 5. Show the window and enter the event loop (0% idle CPU)
    app.show_window(win);
    app.exec() { sig =>
        match sig {
            _ => {},
        }
    };
}
```

---

## 4. Choosing a Rendering Backend

`goose_ui` lets you choose between two rendering backends without changing any widget code:

| Backend | Configuration | Memory (Private) | First Frame | Best For |
| --- | --- | --- | --- | --- |
| **`RenderBackend.Software`** | `app.init(true, goose_ui::RenderBackend.Software)` | **~9.2–11.3 MB** | **~36 ms** | Utility tools, settings dialogs, editors, dashboards, fast startup & low memory |
| **`RenderBackend.Direct2D`** | `app.init(true, goose_ui::RenderBackend.Direct2D)` (default) | ~65–68 MB *(GPU driver baseline)* | ~200 ms | Anti-aliased vector curves, alpha blending, animated `Canvas` surfaces |

You can also select a backend per window:

```goose
let win = app.create_window_with_backend(
    "GPU Canvas", 900, 600, true, goose_ui::RenderBackend.Direct2D
);
```

---

## 5. Building a Standalone Native `.exe`

`goose build` produces a self-contained Windows executable (~386 KB) with zero external runtime DLLs:

```powershell
# Type-check (verify 0 errors and 0 warnings)
goose check examples/counter.goose

# Compile standalone native binary with Clang -O2
goose build examples/counter.goose
.\examples\counter.exe
```

---

## Next Steps

- [UI DSL & Layout Guide](dsl-and-layout.md) — Scoped nested DSL, all layout containers, and `Anchor` absolute placement
- [Widgets, Events & Native API](widgets-and-events.md) — All 21 widgets, events, native dialogs, and `Canvas`
- [Architecture & Performance](architecture.md) — Zero-heap design and Qt 6 comparison benchmarks
