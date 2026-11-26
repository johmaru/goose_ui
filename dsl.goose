// Best-of-both-worlds UI DSL for goose_ui:
//   - SwiftUI / Jetpack Compose scoped nested layout blocks (zero runtime cost)
//   - Fluent UFCS modifier chaining (.primary().stretch(1.0).tooltip("..."))
//   - Win32-style integer action/control IDs (.action(ID_ADD)) for clean `match` dispatch
//   - Optional WinForms/Win32-style absolute placement + resize Anchors (.bounds(..., ANCHOR_*))
namespace goose_ui;

import std;
import types;
import theme;
import widget;
import tree;
import i18n;
import webview;

// Lightweight 16-byte builder cursor (compiles away to registers).
struct Ui {
    app: App&,
    parent: WidgetId,
}

// Lightweight 16-byte fluent modifier handle for a newly created widget.
struct Node {
    app: App&,
    id: WidgetId,
}

// --- Entry Points -----------------------------------------------------------

// Builds UI inside a window's root widget using a scoped trailing block.
fn ui<F>(app: App&, win: WindowId) {
    let r = app.root(win);
    guard app.valid_widget(r) else { return; }
    let u = Ui { app: app, parent: r };
    F(u);
}

// Builds UI inside any existing container widget.
fn ui_in<F>(app: App&, container: WidgetId) {
    guard app.valid_widget(container) else { return; }
    let u = Ui { app: app, parent: container };
    F(u);
}

// --- Container Self-Configuration on Ui -------------------------------------

fn self_node(u: Ui) -> Node { Node { app: u.app, id: u.parent } }
fn id(u: Ui) -> WidgetId { u.parent }

fn padding(u: Ui, all: f32) -> Ui { u.app.set_padding(u.parent, all); return u; }
fn padding_m(u: Ui, m: Margins) -> Ui { u.app.set_padding(u.parent, m); return u; }
fn spacing(u: Ui, sp: f32) -> Ui { u.app.set_spacing(u.parent, sp); return u; }
fn stretch(u: Ui, s: f32) -> Ui { u.app.set_stretch(u.parent, s); return u; }
fn fixed(u: Ui, w: f32, h: f32) -> Ui { u.app.set_fixed_size(u.parent, w, h); return u; }
fn width(u: Ui, w: f32) -> Ui { u.app.set_fixed_width(u.parent, w); return u; }
fn height(u: Ui, h: f32) -> Ui { u.app.set_fixed_height(u.parent, h); return u; }
fn min_size(u: Ui, w: f32, h: f32) -> Ui { u.app.set_min_size(u.parent, w, h); return u; }
fn max_size(u: Ui, w: f32, h: f32) -> Ui { u.app.set_max_size(u.parent, w, h); return u; }
fn policy(u: Ui, h: SizePolicy, v: SizePolicy) -> Ui { u.app.set_size_policy(u.parent, h, v); return u; }
fn bg(u: Ui, c: Color) -> Ui { u.app.set_bg(u.parent, c); return u; }
fn border(u: Ui, c: Color, w: f32 = 1.0) -> Ui { u.app.set_border(u.parent, c, w); return u; }
fn radius(u: Ui, r: f32) -> Ui { u.app.set_radius(u.parent, r); return u; }
fn action(u: Ui, control_id: i64) -> Ui { u.app.set_tag(u.parent, control_id); return u; }
fn name(u: Ui, n: const u8[:]) -> Ui { u.app.set_name(u.parent, n); return u; }
fn bind(u: Ui, out_id: WidgetId&) -> Ui { out_id = u.parent; return u; }
fn layout_kind(u: Ui, k: LayoutKind) -> Ui { u.app.set_layout(u.parent, k); return u; }
fn form_label_width(u: Ui, w: f32) -> Ui { u.app.set_form_label_width(u.parent, w); return u; }

// --- Scoped Nested Containers (Compose / SwiftUI Style) ---------------------

fn vbox<F>(u: Ui, spacing: f32 = 8.0, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_vbox(u.parent, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn hbox<F>(u: Ui, spacing: f32 = 8.0, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_hbox(u.parent, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn grid<F>(u: Ui, columns: i32 = 2, spacing: f32 = 8.0, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_grid(u.parent, columns, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn form<F>(u: Ui, label_width: f32 = 130.0, spacing: f32 = 10.0, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_form(u.parent, label_width, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn stack<F>(u: Ui, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_stack(u.parent, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

// Absolute / Win32+Anchor container panel (`LayoutKind.None`).
fn anchored_panel<F>(u: Ui, padding: f32 = 0.0) -> Node {
    let cid = u.app.add_panel(u.parent, LayoutKind.None, 0.0, padding);
    u.app.set_size_policy(cid, SizePolicy.Expanding, SizePolicy.Expanding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn frame<F>(u: Ui, layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 12.0) -> Node {
    let cid = u.app.add_frame(u.parent, layout, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn group_box<F>(u: Ui, title: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 12.0) -> Node {
    let cid = u.app.add_group_box(u.parent, title, layout, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn scroll_area<F>(u: Ui, spacing: f32 = 8.0, padding: f32 = 10.0) -> Node {
    let cid = u.app.add_scroll_area(u.parent, spacing, padding);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn splitter<F>(u: Ui, orientation: Orientation = Orientation.Horizontal, ratio: f32 = 0.35) -> Node {
    let cid = u.app.add_splitter(u.parent, orientation, ratio);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn tabs<F>(u: Ui) -> Node {
    let cid = u.app.add_tab_widget(u.parent);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn tab<F>(u: Ui, title: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 10.0, padding: f32 = 12.0) -> Node {
    let pid = u.app.add_tab(u.parent, title, layout, spacing, padding);
    F(Ui { app: u.app, parent: pid });
    return Node { app: u.app, id: pid };
}

fn tr_group_box<F>(u: Ui, title_key: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 8.0, padding: f32 = 12.0) -> Node {
    let cid = u.app.add_group_box(u.parent, "", layout, spacing, padding);
    u.app.set_tr_text(cid, title_key);
    F(Ui { app: u.app, parent: cid });
    return Node { app: u.app, id: cid };
}

fn tr_tab<F>(u: Ui, title_key: const u8[:], layout: LayoutKind = LayoutKind.VBox, spacing: f32 = 10.0, padding: f32 = 12.0) -> Node {
    let pid = u.app.add_tr_tab(u.parent, title_key, layout, spacing, padding);
    F(Ui { app: u.app, parent: pid });
    return Node { app: u.app, id: pid };
}

// --- Leaf Widget Builders on Ui ---------------------------------------------

fn spacer(u: Ui, stretch: f32 = 1.0) -> Node {
    return Node { app: u.app, id: u.app.add_spacer(u.parent, stretch) };
}

fn separator(u: Ui, orientation: Orientation = Orientation.Horizontal) -> Node {
    return Node { app: u.app, id: u.app.add_separator(u.parent, orientation) };
}

fn label(u: Ui, text: const u8[:], role: FontRole = FontRole.Body) -> Node {
    return Node { app: u.app, id: u.app.add_label(u.parent, text, role) };
}

fn button(u: Ui, text: const u8[:], variant: ButtonVariant = ButtonVariant.Default) -> Node {
    return Node { app: u.app, id: u.app.add_button(u.parent, text, variant) };
}

fn checkbox(u: Ui, text: const u8[:], checked: bool = false) -> Node {
    return Node { app: u.app, id: u.app.add_checkbox(u.parent, text, checked) };
}

fn radio(u: Ui, text: const u8[:], checked: bool = false) -> Node {
    return Node { app: u.app, id: u.app.add_radio_button(u.parent, text, checked) };
}

fn toggle(u: Ui, text: const u8[:], checked: bool = false) -> Node {
    return Node { app: u.app, id: u.app.add_toggle_switch(u.parent, text, checked) };
}

fn line_edit(u: Ui, placeholder: const u8[:] = "", initial_text: const u8[:] = "") -> Node {
    return Node { app: u.app, id: u.app.add_line_edit(u.parent, placeholder, initial_text) };
}

fn slider(
    u: Ui,
    min_val: f64 = 0.0,
    max_val: f64 = 100.0,
    initial: f64 = 0.0,
    step: f64 = 1.0,
    orientation: Orientation = Orientation.Horizontal
) -> Node {
    return Node { app: u.app, id: u.app.add_slider(u.parent, min_val, max_val, initial, step, orientation) };
}

fn spin_box(
    u: Ui,
    min_val: f64 = 0.0,
    max_val: f64 = 100.0,
    initial: f64 = 0.0,
    step: f64 = 1.0,
    decimals: i32 = 0
) -> Node {
    return Node { app: u.app, id: u.app.add_spin_box(u.parent, min_val, max_val, initial, step, decimals) };
}

fn progress_bar(u: Ui, min_val: f64 = 0.0, max_val: f64 = 100.0, initial: f64 = 0.0) -> Node {
    return Node { app: u.app, id: u.app.add_progress_bar(u.parent, min_val, max_val, initial) };
}

fn combo_box(u: Ui) -> Node {
    return Node { app: u.app, id: u.app.add_combo_box(u.parent) };
}

fn list_view(u: Ui, item_height: f32 = 30.0) -> Node {
    return Node { app: u.app, id: u.app.add_list_view(u.parent, item_height) };
}

fn canvas(u: Ui, min_w: f32 = 200.0, min_h: f32 = 160.0) -> Node {
    return Node { app: u.app, id: u.app.add_canvas(u.parent, min_w, min_h) };
}
fn webview(u: Ui, initial_url: const u8[:] = "", min_w: f32 = 320.0, min_h: f32 = 240.0) -> Node {
    return Node { app: u.app, id: u.app.add_webview(u.parent, initial_url, min_w, min_h) };
}
fn webview_html(u: Ui, initial_html: const u8[:], min_w: f32 = 320.0, min_h: f32 = 240.0) -> Node {
    return Node { app: u.app, id: u.app.add_webview_html(u.parent, initial_html, min_w, min_h) };
}
fn webview_with(u: Ui, opts: WebViewOptions) -> Node {
    return Node { app: u.app, id: u.app.add_webview_with_options(u.parent, opts) };
}

// Translated leaf widget builders (auto-retranslate when App locale changes)
fn tr_label(u: Ui, key: const u8[:], role: FontRole = FontRole.Body) -> Node {
    let id = u.app.add_label(u.parent, "", role);
    u.app.set_tr_text(id, key);
    return Node { app: u.app, id: id };
}

fn tr_button(u: Ui, key: const u8[:], variant: ButtonVariant = ButtonVariant.Default) -> Node {
    let id = u.app.add_button(u.parent, "", variant);
    u.app.set_tr_text(id, key);
    return Node { app: u.app, id: id };
}

fn tr_checkbox(u: Ui, key: const u8[:], checked: bool = false) -> Node {
    let id = u.app.add_checkbox(u.parent, "", checked);
    u.app.set_tr_text(id, key);
    return Node { app: u.app, id: id };
}

fn tr_radio(u: Ui, key: const u8[:], checked: bool = false) -> Node {
    let id = u.app.add_radio_button(u.parent, "", checked);
    u.app.set_tr_text(id, key);
    return Node { app: u.app, id: id };
}

fn tr_toggle(u: Ui, key: const u8[:], checked: bool = false) -> Node {
    let id = u.app.add_toggle_switch(u.parent, "", checked);
    u.app.set_tr_text(id, key);
    return Node { app: u.app, id: id };
}

fn tr_line_edit(u: Ui, placeholder_key: const u8[:], initial_text: const u8[:] = "") -> Node {
    let id = u.app.add_line_edit(u.parent, "", initial_text);
    if placeholder_key.len > 0 {
        u.app.set_tr_placeholder(id, placeholder_key);
    }
    return Node { app: u.app, id: id };
}

// --- Fluent UFCS Modifiers on Node ------------------------------------------

fn widget(n: Node) -> WidgetId { n.id }
fn bind(n: Node, out_id: WidgetId&) -> Node { out_id = n.id; return n; }

// Identity & Win32-style action ID
fn action(n: Node, control_id: i64) -> Node { n.app.set_tag(n.id, control_id); return n; }
fn name(n: Node, obj_name: const u8[:]) -> Node { n.app.set_name(n.id, obj_name); return n; }

// Layout & Sizing
fn stretch(n: Node, s: f32) -> Node { n.app.set_stretch(n.id, s); return n; }
fn fixed(n: Node, w: f32, h: f32) -> Node { n.app.set_fixed_size(n.id, w, h); return n; }
fn width(n: Node, w: f32) -> Node { n.app.set_fixed_width(n.id, w); return n; }
fn height(n: Node, h: f32) -> Node { n.app.set_fixed_height(n.id, h); return n; }
fn min_size(n: Node, w: f32, h: f32) -> Node { n.app.set_min_size(n.id, w, h); return n; }
fn max_size(n: Node, w: f32, h: f32) -> Node { n.app.set_max_size(n.id, w, h); return n; }
fn policy(n: Node, h: SizePolicy, v: SizePolicy) -> Node { n.app.set_size_policy(n.id, h, v); return n; }
fn align(n: Node, h: Align, v: Align = Align.Stretch) -> Node { n.app.set_align(n.id, h, v); return n; }
fn padding(n: Node, all: f32) -> Node { n.app.set_padding(n.id, all); return n; }
fn spacing(n: Node, sp: f32) -> Node { n.app.set_spacing(n.id, sp); return n; }
fn form_label_width(n: Node, w: f32) -> Node { n.app.set_form_label_width(n.id, w); return n; }

// Win32 / WinForms-style absolute placement + resize anchor
fn bounds(n: Node, x: f32, y: f32, w: f32, h: f32, anchor: u8 = ANCHOR_TOP_LEFT, ref_w: f32 = 0.0, ref_h: f32 = 0.0) -> Node {
    n.app.set_bounds(n.id, x, y, w, h, anchor, ref_w, ref_h);
    return n;
}

// Typography & Alignment
fn heading(n: Node) -> Node { n.app.set_font_role(n.id, FontRole.Heading); return n; }
fn subheading(n: Node) -> Node { n.app.set_font_role(n.id, FontRole.Subheading); return n; }
fn bold(n: Node) -> Node { n.app.set_font_role(n.id, FontRole.BodyBold); return n; }
fn caption(n: Node) -> Node { n.app.set_font_role(n.id, FontRole.Caption); return n; }
fn mono(n: Node) -> Node { n.app.set_font_role(n.id, FontRole.Mono); return n; }
fn center(n: Node) -> Node { n.app.set_text_align(n.id, Align.Center, Align.Center); return n; }
fn text_align(n: Node, h: Align, v: Align = Align.Center) -> Node { n.app.set_text_align(n.id, h, v); return n; }
fn wrap(n: Node, on: bool = true) -> Node { n.app.set_word_wrap(n.id, on); return n; }

// Button Variants & States
fn primary(n: Node) -> Node { n.app.set_button_variant(n.id, ButtonVariant.Primary); return n; }
fn secondary(n: Node) -> Node { n.app.set_button_variant(n.id, ButtonVariant.Secondary); return n; }
fn danger(n: Node) -> Node { n.app.set_button_variant(n.id, ButtonVariant.Danger); return n; }
fn ghost(n: Node) -> Node { n.app.set_button_variant(n.id, ButtonVariant.Ghost); return n; }
fn checkable(n: Node, on: bool = true) -> Node { n.app.set_checkable(n.id, on); return n; }

// Style & Content
fn bg(n: Node, c: Color) -> Node { n.app.set_bg(n.id, c); return n; }
fn fg(n: Node, c: Color) -> Node { n.app.set_fg(n.id, c); return n; }
fn border(n: Node, c: Color, w: f32 = 1.0) -> Node { n.app.set_border(n.id, c, w); return n; }
fn radius(n: Node, r: f32) -> Node { n.app.set_radius(n.id, r); return n; }
fn tooltip(n: Node, tip: const u8[:]) -> Node { n.app.set_tooltip(n.id, tip); return n; }
fn placeholder(n: Node, ph: const u8[:]) -> Node { n.app.set_placeholder(n.id, ph); return n; }
fn password(n: Node, on: bool = true) -> Node { n.app.set_password_mode(n.id, on); return n; }
fn read_only(n: Node, on: bool = true) -> Node { n.app.set_read_only(n.id, on); return n; }
fn enabled(n: Node, on: bool) -> Node { n.app.set_enabled(n.id, on); return n; }
fn visible(n: Node, on: bool) -> Node { n.app.set_visible(n.id, on); return n; }

// Items (ComboBox / ListView)
fn item(n: Node, text: const u8[:], subtext: const u8[:] = "", item_tag: i64 = 0) -> Node {
    n.app.add_item(n.id, text, subtext, item_tag);
    return n;
}
fn tr_item(n: Node, text_key: const u8[:], subtext_key: const u8[:] = "", item_tag: i64 = 0) -> Node {
    n.app.add_tr_item(n.id, text_key, subtext_key, item_tag);
    return n;
}
fn tr_text(n: Node, key: const u8[:]) -> Node { n.app.set_tr_text(n.id, key); return n; }
fn tr_placeholder(n: Node, key: const u8[:]) -> Node { n.app.set_tr_placeholder(n.id, key); return n; }
fn tr_tooltip(n: Node, key: const u8[:]) -> Node { n.app.set_tr_tooltip(n.id, key); return n; }
fn select(n: Node, idx: i32) -> Node { n.app.set_selected_index(n.id, idx); return n; }

// Inline Declarative Signal -> Slot Connections
fn connect(n: Node, sig: SignalKind, receiver: WidgetId, slot: SlotAction, param: f64 = 0.0) -> Node {
    n.app.connect(n.id, sig, receiver, slot, param);
    return n;
}
fn on_toggle_theme(n: Node) -> Node {
    n.app.connect(n.id, SignalKind.OnToggle, WIDGET_NONE, SlotAction.ToggleTheme);
    return n;
}
fn on_click_close(n: Node) -> Node {
    n.app.connect(n.id, SignalKind.OnClick, WIDGET_NONE, SlotAction.CloseWindow);
    return n;
}

// WebView2 builder modifiers
fn url(n: Node, target_url: const u8[:]) -> Node {
    n.app.webview_navigate(n.id, target_url);
    return n;
}
fn html(n: Node, markup: const u8[:]) -> Node {
    n.app.webview_set_html(n.id, markup);
    return n;
}
fn init_script(n: Node, script: const u8[:]) -> Node {
    n.app.webview_add_init_script(n.id, script);
    return n;
}
fn devtools(n: Node, enabled: bool) -> Node {
    n.app.webview_set_devtools_enabled(n.id, enabled);
    return n;
}
fn context_menu(n: Node, enabled: bool) -> Node {
    n.app.webview_set_context_menu_enabled(n.id, enabled);
    return n;
}
fn status_bar(n: Node, enabled: bool) -> Node {
    n.app.webview_set_status_bar_enabled(n.id, enabled);
    return n;
}
fn zoom_control(n: Node, enabled: bool) -> Node {
    n.app.webview_set_zoom_control_enabled(n.id, enabled);
    return n;
}
fn accelerator_keys(n: Node, enabled: bool) -> Node {
    n.app.webview_set_accelerator_keys_enabled(n.id, enabled);
    return n;
}
fn zoom(n: Node, factor: f64) -> Node {
    n.app.webview_set_zoom(n.id, factor);
    return n;
}
fn muted(n: Node, on: bool) -> Node {
    n.app.webview_set_muted(n.id, on);
    return n;
}
fn user_agent(n: Node, ua: const u8[:]) -> Node {
    n.app.webview_set_user_agent(n.id, ua);
    return n;
}
fn new_window_policy(n: Node, policy: WebViewNewWindowPolicy) -> Node {
    n.app.webview_set_new_window_policy(n.id, policy);
    return n;
}
fn color_scheme(n: Node, scheme: WebViewColorScheme) -> Node {
    n.app.webview_set_color_scheme(n.id, scheme);
    return n;
}
fn virtual_host(
    n: Node,
    host_name: const u8[:],
    folder_path: const u8[:],
    access: WebViewHostAccess = WebViewHostAccess.Allow
) -> Node {
    n.app.webview_set_virtual_host(n.id, host_name, folder_path, access);
    return n;
}
