# Architecture & Performance

`goose_ui` leverages Goose's **zero-heap, compiler-managed data-stack model** to deliver a retained-mode desktop GUI framework with minimal memory footprint and fast first-frame latency.

---

## 1. Zero-Heap `root struct App` & Generational Handles

Traditional C++ GUI frameworks (such as Qt's `QObject`) heap-allocate individual widgets, vtables, and meta-object structures. `goose_ui` instead stores all application state inside contiguous arrays in a single `root struct App` ([`widget.goose`](../widget.goose)):

```
root struct App
 ├── windows:      Window[>..]      // Window state, HWND, D2D/GDI font caches
 ├── widgets:      Widget[>..]      // Flat retained widget table
 ├── free_widgets: i64[>..<]        // Recycled widget slot indices
 ├── str_pool:     u8[>..]          // Shared byte pool referenced by StrSpan
 ├── list_items:   ListItem[>..]    // Items for ListView, ComboBox, and TabWidget
 ├── connections:  Connection[>..]  // Declarative Signal -> Slot table
 ├── timers:       TimerInfo[>..]   // Active timers
 ├── signals:      Signal[>..]      // Per-frame signal queue
 ├── focus_order:  WidgetId[>..<]   // Cached Tab traversal order
 ├── log:           LogState         // Optional user-path JSON logger state
 ├── log_path_span: StrSpan          // Pooled path in App.str_pool (0 bytes when unused)
 ├── webviews:      WebViewState[>..] // Sparse native WebView2 slots (0 entries when unused)
 ├── webview_*      payload pools    // Per-drain WebView message/result payload & string pools
 └── i18n_*         I18n tables      // Translation pool, locales, O(1) hash entries & sparse live bindings
```

### Generational Handles (`WindowId`, `WidgetId`)

Instead of raw pointers, widgets and windows are referenced by 8-byte value handles `{ index: i32, gen: u32 }`:

- `destroy_widget(id)` recursively cleans up children, returns slots to `free_widgets`, and increments `gen` on reuse.
- Passing a stale handle fails `valid_widget` / `valid_window` cleanly, preventing use-after-free bugs by construction.

---

## 2. Memory Layout Optimizations

### Shared String Pool (`App.str_pool` + 12-byte `StrSpan`)

Giving every `Widget` fixed inline buffers (e.g. `u8[..256]` × 4 fields ≈ 1 KB) wastes memory when thousands of panels, spacers, or short labels exist.

`goose_ui` stores `text`, `placeholder`, `tooltip`, `name`, and `subtext` as 12-byte `StrSpan { off, len, cap }` handles into `App.str_pool`:

- **In-place reuse**: When updating a string with `n <= s.cap`, `str_set` overwrites the existing span in place with **0 bytes** of additional pool growth (ideal for counters, status bars, and live labels).
- **Measured footprint**: 5,000 mixed controls (6,003 total widget nodes) use only **31.8 KB** in `str_pool`.

### Packed `WidgetStyle` (24 bytes)

Per-widget color overrides (`bg`, `fg`, `border`) are stored as packed `u32` RGBA values plus an 8-bit `flags` mask rather than 16-byte `Color` structs.

Combined, the measured incremental memory cost is **~350 bytes per widget** (~8.5× smaller than Qt 6 Widgets).

---

## 3. Dual Rendering Backend Architecture

| Aspect | `RenderBackend.Software` | `RenderBackend.Direct2D` |
| --- | --- | --- |
| Rendering API | Double-buffered Win32 GDI (`begin_paint` / `end_paint`) + ClearType `CreateFontA` | Direct2D (`ID2D1HwndRenderTarget`) + DirectWrite |
| Startup Footprint | **Never loads `d2d1` / `d3d11`** (avoids ~56 MB GPU driver baseline) | Initializes GPU device & swap chain |
| Font Cache | 6 `HFONT` handles per window (`GdiFontSet`) | 6 `IDWriteTextFormat` handles per window (`FontSet`, fitting `W32_MAX_D2D_FONTS = 64`) with `set_word_wrap(false)`, `set_align`, and exact DirectWrite `measure_text` |
| Clipping | Hardware GDI `SaveDC` / `IntersectClipRect` / `RestoreDC` | Hardware `PushAxisAlignedClip` / `PopAxisAlignedClip` (`d2d.push_clip` / `pop_clip`) + `D2D1_DRAW_TEXT_OPTIONS_CLIP` |
| `Canvas` Coordinates | Software translation via `Painter.ox / oy` + clip rect | GPU `d2d.push_clip` + translation via `d2d.set_transform` |
| Translucency | Pre-composited onto `theme.surface_bg` (`gdi_colorref`) | Hardware alpha blending |

---

## 4. Benchmark Methodology & Results

### Test Environment

- **Machine**: Windows 11 x64 / NVIDIA GeForce RTX 5070 Ti
- **Toolchains**: Goose v2026.4 + Clang `-O2` / Qt 6.11.1 MinGW `g++ -O2` / Python 3.14 Tkinter
- **Scenario**: Construct, lay out, and perform the first paint of `N` mixed controls (`Label`, `LineEdit`, `CheckBox`, `ProgressBar`, `Button` inside a `ScrollArea`), then query `K32GetProcessMemoryInfo` (`PROCESS_MEMORY_COUNTERS_EX`) inside each isolated process.
- **Reproduce**: `pwsh -File bench/run_bench.ps1` (sources under [`bench/`](../bench))

### Private Bytes (MB)

| Framework | Backend | 0 ctrl | 100 ctrl | 1,000 ctrl | 5,000 ctrl | Per-Widget Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | GDI + ClearType (CPU) | **9.17** | 10.38 | **10.34** | **11.25** | **~350 B** |
| **`goose_ui` (Headless)** | Pure Data Stack | 8.09 | 9.15 | 9.12 | 10.30 | ~370 B |
| **Qt 6.11.1 Widgets** | C++ Raster (CPU) | 10.05 | 9.79 | 14.11 | 27.84 | ~2,965 B (8.5×) |
| **`goose_ui` (Direct2D)** | Direct2D + DirectWrite (GPU) | **65.05** | **66.76** | **66.18** | **67.57** | **~420 B** |
| **Qt 6.11.1 Quick / QML** | Direct3D 11 RHI (GPU) | 88.37 | 104.19 | 180.85 | — | ~77 KB (~220×) |
| **Python 3.14 Tkinter** | Tcl/Tk (CPU) | 14.40 | 16.58 | 21.52 | — | ~5.9 KB (17×) |

### Working Set (MB), First-Frame Latency & Distributable Size

| Framework | 0 ctrl WS | 1,000 ctrl WS | 5,000 ctrl WS | 1,000 ctrl Time | 5,000 ctrl Time | Distributable Size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **`goose_ui` (Software)** | **21.97** | **22.30** | **24.02** | **32.7 ms** | **35.8 ms** | **386 KB** (single `.exe`) |
| **`goose_ui` (Direct2D)** | 55.18 | 56.59 | 58.08 | 216.3 ms | 197.6 ms | **386 KB** (single `.exe`) |
| **Qt 6.11.1 Widgets** | 42.29 | 48.13 | 63.86 | 317.9 ms | 380.9 ms | 32.3 MB (`.exe` + Qt/MinGW DLLs) |
| **Qt 6.11.1 Quick / QML** | 92.74 | 177.52 | — | 673.0 ms | — | > 40 MB (Qt/QML/Controls DLLs) |
| **Python 3.14 Tkinter** | 31.81 | 51.31 | — | 1,435.7 ms | — | Python + Tcl/Tk runtime |

### Module Graph

```
goose_ui.goose (public entry point)
 ├── types.goose    (geometry, handles, enums, Signal, ANCHOR_*)
 ├── theme.goose    (Theme, packed WidgetStyle, UTF-8 text metrics)
 ├── widget.goose   (Widget, Window, ListItem, TimerInfo, root struct App)
 ├── tree.goose     (lifecycle, window positioning, str_pool, font caches, add_*/set_*, connect)
 ├── log.goose      (structured JSON logging, rotation, JsonLogger, log reader)
 ├── webview.goose  (WebView2 wrapper, layout/clip sync, JS bridge payloads, inject_webview_*)
 ├── layout.goose   (two-pass layout engine & Anchor absolute positioning)
 ├── painter.goose  (Software GDI / Direct2D dual painter & widget renderers)
 ├── events.goose   (hit testing, focus, input editing, event loop, inject_*)
 ├── native.goose   (Win32 menus, dialogs, clipboard, timers, drag & drop)
 ├── i18n.goose     (zero-heap multi-language catalogs, JSON loaders, live bindings)
 └── dsl.goose      (scoped nested DSL: Ui / Node & .tr_* builders)
```
