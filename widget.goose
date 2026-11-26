// Retained-mode widget, window, item, and App root-struct definitions.
// All variable-length text is stored in App.str_pool via compact 12-byte StrSpans,
// keeping each Widget node compact (~240 bytes) with zero heap allocations.
namespace goose_ui;

import std;
import win32 from "./win32-goose";
import types;
import theme;

// --- Retained Widget Node ---------------------------------------------------

struct Widget {
    alive: bool = false,
    gen: u32 = 1,
    kind: WidgetKind = WidgetKind.Panel,
    window: WindowId = WINDOW_NONE,

    // Tree links
    parent: WidgetId = WIDGET_NONE,
    first_child: WidgetId = WIDGET_NONE,
    last_child: WidgetId = WIDGET_NONE,
    prev_sibling: WidgetId = WIDGET_NONE,
    next_sibling: WidgetId = WIDGET_NONE,
    child_count: i32 = 0,

    // Identity & user metadata (strings live in App.str_pool)
    name: StrSpan = StrSpan {},
    tag: i64 = 0,

    // Visibility & interactive state
    visible: bool = true,
    enabled: bool = true,
    focusable: bool = false,
    cursor: CursorShape = CursorShape.Arrow,

    // Layout configuration (QLayout / QSizePolicy)
    layout: LayoutKind = LayoutKind.None,
    align_h: Align = Align.Stretch,
    align_v: Align = Align.Stretch,
    policy_h: SizePolicy = SizePolicy.Preferred,
    policy_v: SizePolicy = SizePolicy.Preferred,
    stretch: f32 = 0.0,
    spacing: f32 = 8.0,
    padding: Margins = Margins {},
    min_size: SizeF = SizeF {},
    max_size: SizeF = SizeF { w: 100000.0, h: 100000.0 },
    fixed_w: f32 = -1.0,
    fixed_h: f32 = -1.0,
    grid_cols: i32 = 2,
    form_label_width: f32 = 130.0,
    orientation: Orientation = Orientation.Horizontal,

    // Computed geometry (set by layout engine)
    size_hint: SizeF = SizeF {},
    rect: RectF = RectF {},
    content_rect: RectF = RectF {},

    // Optional Win32/WinForms-style absolute placement & resize anchoring (used in LayoutKind.None)
    abs_rect: RectF = RectF {},
    abs_ref: SizeF = SizeF {},
    anchor: u8 = 0,
    has_abs_bounds: bool = false,

    // Text & Typography (pooled in App.str_pool: 0 bytes when unused)
    text: StrSpan = StrSpan {},
    placeholder: StrSpan = StrSpan {},
    tooltip: StrSpan = StrSpan {},
    font_role: FontRole = FontRole.Body,
    text_align_h: Align = Align.Start,
    text_align_v: Align = Align.Center,
    word_wrap: bool = false,

    // Widget-specific state
    variant: ButtonVariant = ButtonVariant.Default,
    checkable: bool = false,
    checked: bool = false,
    read_only: bool = false,
    password_mode: bool = false,
    show_percentage: bool = true,

    // Numeric range (Slider, SpinBox, ProgressBar)
    value: f64 = 0.0,
    min_value: f64 = 0.0,
    max_value: f64 = 100.0,
    step: f64 = 1.0,
    decimals: i32 = 0,

    // Selection / Tabs / Lists
    selected_index: i32 = -1,
    hovered_item: i32 = -1,
    item_height: f32 = 30.0,
    tab_bar_height: f32 = 36.0,

    // Scroll & Splitter state
    scroll_y: f32 = 0.0,
    scroll_max_y: f32 = 0.0,
    split_ratio: f32 = 0.35,
    splitter_size: f32 = 6.0,

    // LineEdit cursor & selection
    caret: i32 = 0,
    sel_anchor: i32 = 0,
    text_scroll_x: f32 = 0.0,
    text_scroll_byte: i32 = 0,

    // Compact style override
    style: WidgetStyle = WidgetStyle {},
}

// Item belonging to a ListView, ComboBox, or TabWidget (strings pooled in App.str_pool).
struct ListItem {
    alive: bool = true,
    uid: u64 = 0,
    owner: WidgetId = WIDGET_NONE,
    text: StrSpan = StrSpan {},
    subtext: StrSpan = StrSpan {},
    tag: i64 = 0,
    page: WidgetId = WIDGET_NONE,
}

// Font cache for Direct2D backend.
struct FontSet {
    body: win32::D2dFont = win32::D2dFont {},
    body_bold: win32::D2dFont = win32::D2dFont {},
    heading: win32::D2dFont = win32::D2dFont {},
    subheading: win32::D2dFont = win32::D2dFont {},
    caption: win32::D2dFont = win32::D2dFont {},
    mono: win32::D2dFont = win32::D2dFont {},
}

// Font cache for Software GDI backend (ClearType Segoe UI & Consolas).
struct GdiFontSet {
    body: win32::Hfont = win32::Hfont {},
    body_bold: win32::Hfont = win32::Hfont {},
    heading: win32::Hfont = win32::Hfont {},
    subheading: win32::Hfont = win32::Hfont {},
    caption: win32::Hfont = win32::Hfont {},
    mono: win32::Hfont = win32::Hfont {},
}

// Font cache for OpenGL 3.3 backend (uploaded into GPU VRAM GL_R8 atlas).
struct Gl2dFontSet {
    body: win32::Gl2dFont = win32::Gl2dFont {},
    body_bold: win32::Gl2dFont = win32::Gl2dFont {},
    heading: win32::Gl2dFont = win32::Gl2dFont {},
    subheading: win32::Gl2dFont = win32::Gl2dFont {},
    caption: win32::Gl2dFont = win32::Gl2dFont {},
    mono: win32::Gl2dFont = win32::Gl2dFont {},
}

// Top-level Window state.
struct Window {
    alive: bool = false,
    gen: u32 = 1,
    headless: bool = false,
    backend: RenderBackend = RenderBackend.Direct2D,
    hwnd: win32::Hwnd = win32::Hwnd {},
    d2d: win32::D2dTarget = win32::D2dTarget {},
    gl2d: win32::Gl2dTarget = win32::Gl2dTarget {},
    fonts: FontSet = FontSet {},
    gdi_fonts: GdiFontSet = GdiFontSet {},
    gl2d_fonts: Gl2dFontSet = Gl2dFontSet {},
    metric_dc: win32::Hdc = win32::Hdc {},
    metric_fonts: GdiFontSet = GdiFontSet {},
    menu_bar: win32::Hmenu = win32::Hmenu {},

    title: StrSpan = StrSpan {},
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 800,
    height: i32 = 600,
    dpi: u32 = 96,
    visible: bool = false,
    auto_close: bool = true,
    dirty: bool = true,
    layout_dirty: bool = true,

    root_widget: WidgetId = WIDGET_NONE,
    status_bar: WidgetId = WIDGET_NONE,

    // Per-window interaction state
    hovered: WidgetId = WIDGET_NONE,
    pressed: WidgetId = WIDGET_NONE,
    focused: WidgetId = WIDGET_NONE,
    captured: WidgetId = WIDGET_NONE,
    open_combo: WidgetId = WIDGET_NONE,
    open_combo_hover: i32 = -1,
    open_combo_scroll: i32 = 0,

    // Mouse tracking & double-click detection
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    mouse_down: bool = false,
    last_click_ms: u64 = 0,
    last_click_x: f32 = 0.0,
    last_click_y: f32 = 0.0,
    last_click_widget: WidgetId = WIDGET_NONE,
    last_click_item: i32 = -1,
    hover_since_ms: u64 = 0,
    tooltip_timer_active: bool = false,
    tooltip_visible: bool = false,

    // UTF-16 high surrogate buffer for WM_CHAR emoji input
    pending_surrogate: u32 = 0,
}

// Timer bookkeeping (QTimer equivalent).
struct TimerInfo {
    alive: bool = false,
    window: WindowId = WINDOW_NONE,
    timer_id: u64 = 0,
    interval_ms: u32 = 1000,
    single_shot: bool = false,
}

// --- Application Root Struct (QApplication) ---------------------------------
// Holds all independently growing tables on Goose data stacks with zero heap
// allocations. Declare as `var app = gui::App { .. };` and pass by reference.
root struct App {
    initialized: bool = false,
    running: bool = false,
    quit_on_last_window_closed: bool = true,
    backend: RenderBackend = RenderBackend.Direct2D,
    window_pos_mode: i32 = WIN_POS_DEFAULT,
    window_pos_x: i32 = 0,
    window_pos_y: i32 = 0,
    window_pos_monitor: i32 = 0,
    theme: Theme = Theme {},
    next_timer_id: u64 = 1,
    active_cursor: CursorShape = CursorShape.Arrow,
    connection_depth: i32 = 0,

    windows: Window[>..] = [],
    widgets: Widget[>..] = [],
    free_widgets: i64[>..<] = [],
    str_pool: u8[>..] = [],
    list_items: ListItem[>..] = [],
    connections: Connection[>..] = [],
    timers: TimerInfo[>..] = [],
    signals: Signal[>..] = [],
    signal_head: i64 = 0,
    focus_order: WidgetId[>..<] = [],
    log: LogState = LogState {},
    log_path_span: StrSpan = StrSpan {},

    // Multi-language (i18n) state & sparse live widget bindings
    next_list_item_uid: u64 = 1,
    i18n_active: i32 = -1,
    i18n_fallback: i32 = -1,
    i18n_pool: u8[>..] = [],
    i18n_locales: I18nLocale[>..] = [],
    i18n_entries: I18nEntry[>..] = [],
    i18n_buckets: i32[>..<] = [],
    i18n_bindings: I18nBinding[>..] = [],

    // Sparse WebView2 widget table (0 bytes per non-WebView Widget)
    webviews: WebViewState[>..] = [],
    webview_payloads: WebViewPayload[>..] = [],
    webview_msg_pool: u8[>..] = [],
    webview_default_data_dir: StrSpan = StrSpan {},
}
