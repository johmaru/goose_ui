// Core geometric, identifier, policy, widget kind, and signal types for goose_ui.
namespace goose_ui;

import std;
import win32 from "./win32-goose";

// --- Identifiers & Handles --------------------------------------------------

struct WindowId {
    index: i32 = -1,
    gen: u32 = 0,
}

struct WidgetId {
    index: i32 = -1,
    gen: u32 = 0,
}

let WINDOW_NONE = WindowId { index: -1, gen: 0 };
let WIDGET_NONE = WidgetId { index: -1, gen: 0 };

fn is_valid(id: WindowId) -> bool { id.index >= 0 && id.gen != 0 }
fn is_valid(id: WidgetId) -> bool { id.index >= 0 && id.gen != 0 }

fn eq(a: WindowId, b: WindowId) -> bool { a.index == b.index && a.gen == b.gen }
fn eq(a: WidgetId, b: WidgetId) -> bool { a.index == b.index && a.gen == b.gen }

// --- Geometry ---------------------------------------------------------------

struct PointF {
    x: f32 = 0.0,
    y: f32 = 0.0,
}

struct SizeF {
    w: f32 = 0.0,
    h: f32 = 0.0,
}

struct RectF {
    x: f32 = 0.0,
    y: f32 = 0.0,
    w: f32 = 0.0,
    h: f32 = 0.0,
}

struct Margins {
    left: f32 = 0.0,
    top: f32 = 0.0,
    right: f32 = 0.0,
    bottom: f32 = 0.0,
}

fn rect(x: f32, y: f32, w: f32, h: f32) -> RectF { RectF { x, y, w, h } }
fn size(w: f32, h: f32) -> SizeF { SizeF { w, h } }
fn margins(all: f32) -> Margins { Margins { left: all, top: all, right: all, bottom: all } }
fn margins_xy(h: f32, v: f32) -> Margins { Margins { left: h, top: v, right: h, bottom: v } }
fn margins_ltrb(l: f32, t: f32, r: f32, b: f32) -> Margins { Margins { left: l, top: t, right: r, bottom: b } }

fn right(r: RectF) -> f32 { r.x + r.w }
fn bottom(r: RectF) -> f32 { r.y + r.h }

fn contains(r: RectF, px: f32, py: f32) -> bool {
    return px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h;
}

fn inset(r: RectF, m: Margins) -> RectF {
    let nw = r.w - m.left - m.right;
    let nh = r.h - m.top - m.bottom;
    return RectF {
        x: r.x + m.left,
        y: r.y + m.top,
        w: if nw > 0.0 { nw } else { 0.0 },
        h: if nh > 0.0 { nh } else { 0.0 },
    };
}

fn intersect(a: RectF, b: RectF) -> RectF {
    let x0 = if a.x > b.x { a.x } else { b.x };
    let y0 = if a.y > b.y { a.y } else { b.y };
    let x1 = if a.right() < b.right() { a.right() } else { b.right() };
    let y1 = if a.bottom() < b.bottom() { a.bottom() } else { b.bottom() };
    let w = x1 - x0;
    let h = y1 - y0;
    return RectF {
        x: x0,
        y: y0,
        w: if w > 0.0 { w } else { 0.0 },
        h: if h > 0.0 { h } else { 0.0 },
    };
}

fn clamp_f32(v: f32, lo: f32, hi: f32) -> f32 {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}

fn clamp_f64(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}

// --- Color ------------------------------------------------------------------

struct Color {
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 1.0,
}

let COLOR_TRANSPARENT = Color { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

fn rgb(r: u8, g: u8, b: u8) -> Color {
    return Color { r: r / 255.0, g: g / 255.0, b: b / 255.0, a: 1.0 };
}

fn rgba(r: u8, g: u8, b: u8, a: f32) -> Color {
    return Color { r: r / 255.0, g: g / 255.0, b: b / 255.0, a: a };
}

fn color_hex(hex: u32, a: f32 = 1.0) -> Color {
    let r = ((hex >> 16) & 0xFF) as! u8;
    let g = ((hex >> 8) & 0xFF) as! u8;
    let b = (hex & 0xFF) as! u8;
    return Color { r: r / 255.0, g: g / 255.0, b: b / 255.0, a: a };
}

fn with_alpha(c: Color, a: f32) -> Color {
    return Color { r: c.r, g: c.g, b: c.b, a: a };
}

fn lerp_color(a: Color, b: Color, t: f32) -> Color {
    let k = clamp_f32(t, 0.0, 1.0);
    return Color {
        r: a.r + (b.r - a.r) * k,
        g: a.g + (b.g - a.g) * k,
        b: a.b + (b.b - a.b) * k,
        a: a.a + (b.a - a.a) * k,
    };
}

fn to_d2d(c: Color) -> win32::ColorF {
    return win32::ColorF { r: c.r, g: c.g, b: c.b, a: c.a };
}

fn to_colorref(c: Color) -> u32 {
    let r = (clamp_f32(c.r, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    let g = (clamp_f32(c.g, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    let b = (clamp_f32(c.b, 0.0, 1.0) * 255.0 + 0.5) as! u8;
    return win32::rgb(r, g, b);
}

fn from_colorref(cr: u32) -> Color {
    let r = (cr & 0xFF) as! u8;
    let g = ((cr >> 8) & 0xFF) as! u8;
    let b = ((cr >> 16) & 0xFF) as! u8;
    return rgb(r, g, b);
}

fn pack_rgba(c: Color) -> u32 {
    let r = (clamp_f32(c.r, 0.0, 1.0) * 255.0 + 0.5) as! u32;
    let g = (clamp_f32(c.g, 0.0, 1.0) * 255.0 + 0.5) as! u32;
    let b = (clamp_f32(c.b, 0.0, 1.0) * 255.0 + 0.5) as! u32;
    let a = (clamp_f32(c.a, 0.0, 1.0) * 255.0 + 0.5) as! u32;
    return r | (g << 8) | (b << 16) | (a << 24);
}

fn unpack_rgba(v: u32) -> Color {
    let r = (v & 0xFF) as! u8;
    let g = ((v >> 8) & 0xFF) as! u8;
    let b = ((v >> 16) & 0xFF) as! u8;
    let a = ((v >> 24) & 0xFF) as! u8;
    return Color { r: r / 255.0, g: g / 255.0, b: b / 255.0, a: a / 255.0 };
}

// --- Rendering Backend & Shared String Pool Span ----------------------------

enum RenderBackend {
    Software, // Ultra-light double-buffered GDI + ClearType (no GPU driver overhead)
    Direct2D, // Hardware-accelerated Direct2D + DirectWrite GPU rendering
    OpenGL,   // Hardware-accelerated OpenGL 3.3 Core SDF + GPU VRAM atlas rendering
}

// Startup window placement policy configured on App before creating windows.
enum WindowPosition {
    SystemDefault, // OS default placement (CW_USEDEFAULT)
    CenterPrimary, // Centered inside the primary (main) display work area (excluding taskbar)
    CenterMonitor, // Centered inside a specific monitor's work area (index via set_window_start_monitor)
    Manual,        // Explicit top-left screen coordinates (via set_window_start_position_manual)
}

let WIN_POS_DEFAULT: i32 = 0;
let WIN_POS_CENTER_PRIMARY: i32 = 1;
let WIN_POS_CENTER_MONITOR: i32 = 2;
let WIN_POS_MANUAL: i32 = 3;

// Compact 12-byte handle into App.str_pool (replaces large inline u8[..N] arrays).
struct StrSpan {
    off: i32 = 0,
    len: i32 = 0,
    cap: i32 = 0,
}

// --- Layout & Widget Policy Enums -------------------------------------------

enum LayoutKind {
    None,
    VBox,
    HBox,
    Grid,
    Form,
    Stack,
}

enum Align {
    Start,
    Center,
    End,
    Stretch,
}

enum SizePolicy {
    Fixed,
    Minimum,
    Preferred,
    Expanding,
}

enum Orientation {
    Horizontal,
    Vertical,
}

enum WidgetKind {
    Panel,
    Frame,
    GroupBox,
    Spacer,
    Separator,
    Label,
    Button,
    CheckBox,
    RadioButton,
    ToggleSwitch,
    LineEdit,
    Slider,
    SpinBox,
    ProgressBar,
    ComboBox,
    ListView,
    TabWidget,
    ScrollArea,
    Splitter,
    StatusBar,
    Canvas,
    WebView,
}

enum ButtonVariant {
    Default,
    Primary,
    Secondary,
    Danger,
    Ghost,
}

enum FontRole {
    Body,
    BodyBold,
    Heading,
    Subheading,
    Caption,
    Mono,
}

enum CursorShape {
    Arrow,
    Hand,
    IBeam,
    SizeWE,
    SizeNS,
}

// Key modifier bitmasks.
let KMOD_SHIFT: u32 = 1;
let KMOD_CTRL: u32 = 2;
let KMOD_ALT: u32 = 4;

// WinForms / Win32-style Anchor bitmasks for LayoutKind.None absolute positioning.
let ANCHOR_NONE: u8 = 0;
let ANCHOR_LEFT: u8 = 1;
let ANCHOR_TOP: u8 = 2;
let ANCHOR_RIGHT: u8 = 4;
let ANCHOR_BOTTOM: u8 = 8;
let ANCHOR_TOP_LEFT: u8 = 3;      // LEFT | TOP
let ANCHOR_TOP_RIGHT: u8 = 6;     // TOP | RIGHT
let ANCHOR_BOTTOM_LEFT: u8 = 9;   // LEFT | BOTTOM
let ANCHOR_BOTTOM_RIGHT: u8 = 12; // RIGHT | BOTTOM
let ANCHOR_H_STRETCH: u8 = 7;     // LEFT | TOP | RIGHT
let ANCHOR_V_STRETCH: u8 = 11;    // LEFT | TOP | BOTTOM
let ANCHOR_ALL: u8 = 15;          // LEFT | TOP | RIGHT | BOTTOM

// Mouse button constants.
let MOUSE_LEFT: i32 = 1;
let MOUSE_RIGHT: i32 = 2;
let MOUSE_MIDDLE: i32 = 3;

// --- Qt-style Signals & Declarative Connections -----------------------------

enum Signal {
    None,
    Clicked { widget: WidgetId, window: WindowId },
    DoubleClicked { widget: WidgetId, window: WindowId },
    Toggled { widget: WidgetId, window: WindowId, checked: bool },
    ValueChanged { widget: WidgetId, window: WindowId, value: f64 },
    TextChanged { widget: WidgetId, window: WindowId },
    TextSubmitted { widget: WidgetId, window: WindowId },
    SelectionChanged { widget: WidgetId, window: WindowId, index: i32 },
    ItemActivated { widget: WidgetId, window: WindowId, index: i32 },
    TabChanged { widget: WidgetId, window: WindowId, index: i32 },
    FocusChanged { widget: WidgetId, window: WindowId, focused: bool },
    ActionTriggered { window: WindowId, action_id: u32 },
    TimerFired { window: WindowId, timer_id: u64 },
    KeyPressed { window: WindowId, widget: WidgetId, key: u32, mods: u32 },
    CanvasMouseDown { widget: WidgetId, window: WindowId, x: f32, y: f32, button: i32 },
    CanvasMouseMove { widget: WidgetId, window: WindowId, x: f32, y: f32 },
    CanvasMouseLeave { widget: WidgetId, window: WindowId },
    CanvasMouseUp { widget: WidgetId, window: WindowId, x: f32, y: f32, button: i32 },
    CanvasWheel { widget: WidgetId, window: WindowId, x: f32, y: f32, delta: i32 },
    FilesDropped { window: WindowId, count: i32 },
    WindowResized { window: WindowId, width: i32, height: i32 },
    WindowClosed { window: WindowId },
    LocaleChanged { locale_index: i32 },
    WebViewReady { widget: WidgetId, window: WindowId },
    WebViewInitFailed { widget: WidgetId, window: WindowId, hr: i32 },
    WebViewNavigationStarting { widget: WidgetId, window: WindowId, payload: i32, user_initiated: bool, redirected: bool },
    WebViewNavigationCompleted { widget: WidgetId, window: WindowId, success: bool, error_status: i32 },
    WebViewTitleChanged { widget: WidgetId, window: WindowId },
    WebViewSourceChanged { widget: WidgetId, window: WindowId, is_new_document: bool },
    WebViewHistoryChanged { widget: WidgetId, window: WindowId, can_go_back: bool, can_go_forward: bool },
    WebViewMessageReceived { widget: WidgetId, window: WindowId, payload: i32, is_json: bool },
    WebViewScriptResult { widget: WidgetId, window: WindowId, request_id: u64, payload: i32, ok: bool },
    WebViewNewWindowRequested { widget: WidgetId, window: WindowId, payload: i32, user_initiated: bool },
}

enum SignalKind {
    OnClick,
    OnToggle,
    OnValueChange,
    OnTextChange,
    OnTextSubmit,
    OnSelectionChange,
    OnTabChange,
}

enum SlotAction {
    SetVisible,
    SetVisibleInverted,
    SetEnabled,
    SetEnabledInverted,
    SetChecked,
    ToggleChecked,
    SetValue,
    SetValueLabel,
    SyncText,
    SetCurrentTab,
    ClearText,
    IncrementValue,
    CloseWindow,
    ToggleTheme,
}

struct Connection {
    sender: WidgetId = WIDGET_NONE,
    signal: SignalKind = SignalKind.OnClick,
    receiver: WidgetId = WIDGET_NONE,
    slot: SlotAction = SlotAction.SetEnabled,
    param_f64: f64 = 0.0,
    alive: bool = true,
}

// --- Native Menu Wrapper ----------------------------------------------------

struct MenuHandle {
    raw: win32::Hmenu = win32::Hmenu {},
}

fn is_valid(m: MenuHandle) -> bool { m.raw.is_valid() }

// --- JSON Logging Types -----------------------------------------------------

enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Fatal,
    Off,
}

enum LogFormat {
    JsonLines, // NDJSON: one RFC 8259 JSON object per line (default, append-friendly, crash-safe)
    JsonArray, // Single valid RFC 8259 JSON array `[ ... ]` maintained on every write
}

struct LogOptions {
    min_level: LogLevel = LogLevel.Info,
    format: LogFormat = LogFormat.JsonLines,
    append: bool = true,
    auto_flush: bool = true,
    also_stderr: bool = false,
    utc: bool = false,
    include_process_info: bool = true,
    create_dirs: bool = true,
    max_file_bytes: i64 = 0,
    max_backups: i32 = 3,
    log_ui_events: bool = false,
}

struct LogState {
    file: win32::Hfile = win32::Hfile {},
    min_level_rank: i32 = 2, // LogLevel.Info
    format_code: i32 = 0,    // 0 = JsonLines, 1 = JsonArray
    auto_flush: bool = true,
    also_stderr: bool = false,
    utc: bool = false,
    include_process_info: bool = true,
    ui_events: bool = false,
    has_array_entries: bool = false,
    max_file_bytes: i64 = 0,
    max_backups: i32 = 3,
    written_bytes: i64 = 0,
    array_end_pos: i64 = 0,
    seq: u64 = 0,
}

struct LogEntryView {
    ts: const u8[:] = "",
    seq: i64 = 0,
    level: LogLevel = LogLevel.Info,
    level_text: const u8[:] = "",
    target: const u8[:] = "",
    msg: const u8[:] = "",
    pid: i64 = 0,
    tid: i64 = 0,
    raw_json: const u8[:] = "",
}

// --- Multi-Language (i18n) Types --------------------------------------------

let I18N_TARGET_WIDGET_TEXT: u8 = 0;
let I18N_TARGET_WIDGET_PLACEHOLDER: u8 = 1;
let I18N_TARGET_WIDGET_TOOLTIP: u8 = 2;
let I18N_TARGET_LIST_ITEM_TEXT: u8 = 3;
let I18N_TARGET_LIST_ITEM_SUBTEXT: u8 = 4;
let I18N_TARGET_WINDOW_TITLE: u8 = 5;
let I18N_TARGET_STATUS_BAR: u8 = 6;

struct I18nLocale {
    code: StrSpan = StrSpan {},
    display_name: StrSpan = StrSpan {},
    parent_idx: i32 = -1,
}

struct I18nEntry {
    locale_idx: i32 = -1,
    key_hash: u64 = 0,
    key: StrSpan = StrSpan {},
    val: StrSpan = StrSpan {},
}

struct I18nBinding {
    alive: bool = true,
    target_kind: u8 = 0,
    window: WindowId = WINDOW_NONE,
    widget: WidgetId = WIDGET_NONE,
    item_uid: u64 = 0,
    key: StrSpan = StrSpan {},
}

// --- WebView2 Widget Types --------------------------------------------------

enum WebViewNewWindowPolicy {
    BlockAndNotify,
    NavigateSelf,
    OpenExternal,
    AllowPopup,
}

enum WebViewColorScheme {
    FollowTheme,
    Auto,
    Light,
    Dark,
}

enum WebViewHostAccess {
    Deny,
    Allow,
    DenyCors,
}

struct WebViewOptions {
    url: const u8[:] = "",
    html: const u8[:] = "",
    user_data_dir: const u8[:] = "",
    additional_args: const u8[:] = "",
    devtools: bool = true,
    context_menu: bool = true,
    status_bar: bool = false,
    zoom_control: bool = true,
    accelerator_keys: bool = true,
    new_window_policy: WebViewNewWindowPolicy = WebViewNewWindowPolicy.BlockAndNotify,
    color_scheme: WebViewColorScheme = WebViewColorScheme.FollowTheme,
    min_w: f32 = 320.0,
    min_h: f32 = 240.0,
}

struct WebViewState {
    alive: bool = false,
    widget: WidgetId = WIDGET_NONE,
    window: WindowId = WINDOW_NONE,
    handle: win32::WebView = win32::WebView {},
    ready: bool = false,
    failed: bool = false,
    last_hr: i32 = 0,
    can_go_back: bool = false,
    can_go_forward: bool = false,
    zoom: f64 = 1.0,
    color_scheme_code: i32 = 0, // 0=FollowTheme, 1=Auto, 2=Light, 3=Dark
    new_window_policy_code: i32 = 0,
    devtools: bool = true,
    context_menu: bool = true,
    status_bar: bool = false,
    zoom_control: bool = true,
    accelerator_keys: bool = true,
    muted: bool = false,
    effective_visible: bool = false,
    clipped_rect: RectF = RectF {},
    url: StrSpan = StrSpan {},
    title: StrSpan = StrSpan {},
    last_message: StrSpan = StrSpan {},
    last_script_result: StrSpan = StrSpan {},
    last_error: StrSpan = StrSpan {},
    user_data_dir: StrSpan = StrSpan {},
}

struct WebViewPayload {
    text: StrSpan = StrSpan {},
    aux: StrSpan = StrSpan {},
}
