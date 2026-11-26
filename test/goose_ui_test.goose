// Automated test suite for goose_ui (layout math, widget tree lifecycle,
// generational handles, hit testing, input state machines, UTF-8 LineEdit,
// Qt-style Signal/Slot declarative connections, and real Win32+D2D smoke test).
//
// Run with:   goose run test/goose_ui_test.goose
// Build with: goose build test/goose_ui_test.goose
import std;
import json;
import win32 from "../win32-goose";
import goose_ui from "..";

fn approx(a: f32, b: f32, eps: f32 = 1.0) -> bool {
    let d = a - b;
    return d >= -eps && d <= eps;
}

fn test_tree_and_handles() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("TreeTest", 800, 600);
    assert(app.valid_window(win));
    let root = app.root(win);
    assert(app.valid_widget(root));

    let box1 = app.add_vbox(root, 8.0, 10.0);
    app.set_name(box1, "main_box");
    let b1 = app.add_button(box1, "OK");
    let b2 = app.add_button(box1, "Cancel");
    app.set_name(b2, "cancel_btn");

    assert(goose_ui::eq(app.find_by_name(win, "main_box"), box1));
    assert(goose_ui::eq(app.find_by_name(win, "cancel_btn"), b2));
    assert(!app.valid_widget(app.find_by_name(win, "missing")));

    // Destroy box1 -> must recursively destroy b1 and b2
    app.destroy_widget(box1);
    assert(!app.valid_widget(box1));
    assert(!app.valid_widget(b1));
    assert(!app.valid_widget(b2));

    // Re-allocate slots -> generational handle must NOT alias old destroyed handle
    let fresh = app.add_button(root, "New");
    assert(app.valid_widget(fresh));
    assert(!app.valid_widget(b1));
    assert(!goose_ui::eq(fresh, b1));

    app.destroy_all();
    print("[OK] widget tree, find_by_name, recursive destroy & generational handles");
}

fn test_layouts() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("LayoutTest", 600, 400);
    let sb = app.set_status_bar(win, "Status");
    let root = app.root(win);
    app.set_padding(root, 10.0);
    app.set_spacing(root, 10.0);

    // HBox with 1 fixed (100px) + 2 stretched (1:2 ratio)
    let row = app.add_hbox(root, 10.0);
    app.set_fixed_height(row, 40.0);
    let f1 = app.add_button(row, "Fixed");
    app.set_fixed_width(f1, 100.0);
    let s1 = app.add_button(row, "S1");
    app.set_stretch(s1, 1.0);
    let s2 = app.add_button(row, "S2");
    app.set_stretch(s2, 2.0);

    // Splitter (50/50)
    let sp = app.add_splitter(root, goose_ui::Orientation.Horizontal, 0.5);
    app.set_stretch(sp, 1.0);
    let p_left = app.add_panel(sp, goose_ui::LayoutKind.Grid, 8.0, 0.0);
    let g1 = app.add_button(p_left, "G1");
    let g2 = app.add_button(p_left, "G2");
    let g3 = app.add_button(p_left, "G3");
    let g4 = app.add_button(p_left, "G4");

    let p_right = app.add_form(sp, 100.0, 8.0, 0.0);
    let fl = app.add_label(p_right, "Name:");
    let fe = app.add_line_edit(p_right, "type");

    app.update_layout(win, true);

    // StatusBar docked at bottom (26px high)
    let r_sb = app.widget_rect(sb);
    assert(approx(r_sb.y, 374.0) && approx(r_sb.h, 26.0) && approx(r_sb.w, 600.0));

    // HBox inner width = 600 - 20 = 580; fixed = 100; gaps = 20 -> remaining = 460 -> s1 = 153.33, s2 = 306.67
    let rf1 = app.widget_rect(f1);
    let rs1 = app.widget_rect(s1);
    let rs2 = app.widget_rect(s2);
    assert(approx(rf1.w, 100.0));
    assert(approx(rs1.w, 153.33, 1.5));
    assert(approx(rs2.w, 306.67, 1.5));
    assert(approx(rs1.x, rf1.x + rf1.w + 10.0));
    assert(approx(rs2.x, rs1.x + rs1.w + 10.0));

    // Grid 2x2: g1 & g2 on row 0, g3 & g4 on row 1
    let rg1 = app.widget_rect(g1);
    let rg2 = app.widget_rect(g2);
    let rg3 = app.widget_rect(g3);
    let rg4 = app.widget_rect(g4);
    assert(approx(rg1.y, rg2.y));
    assert(rg2.x > rg1.x + rg1.w);
    assert(rg3.y > rg1.y + rg1.h);
    assert(approx(rg3.y, rg4.y));

    // Form layout: label width 100, field starts after label + spacing
    let rfl = app.widget_rect(fl);
    let rfe = app.widget_rect(fe);
    assert(approx(rfl.w, 100.0));
    assert(approx(rfe.x, rfl.x + 100.0 + 8.0));

    app.destroy_all();
    print("[OK] VBox, HBox stretch, Grid, Form, Splitter & StatusBar layout engine");
}

fn test_widgets_and_signals() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("InteractionTest", 700, 500);
    let root = app.root(win);
    app.set_padding(root, 12.0);
    app.set_spacing(root, 8.0);

    let btn = app.add_button(root, "Click Me");
    let chk = app.add_checkbox(root, "Enable", true);
    let sw = app.add_toggle_switch(root, "Dark", true);
    let r_row = app.add_hbox(root, 8.0);
    let rad1 = app.add_radio_button(r_row, "A", true);
    let rad2 = app.add_radio_button(r_row, "B", false);
    let sld = app.add_slider(root, 0.0, 100.0, 20.0, 5.0);
    let spn = app.add_spin_box(root, 0.0, 100.0, 20.0, 5.0, 0);
    let pb = app.add_progress_bar(root, 0.0, 100.0, 20.0);
    let ed = app.add_line_edit(root, "placeholder", "");
    let lbl = app.add_label(root, "");

    // Declarative connections
    app.connect(chk, goose_ui::SignalKind.OnToggle, btn, goose_ui::SlotAction.SetEnabled);
    app.connect(sld, goose_ui::SignalKind.OnValueChange, pb, goose_ui::SlotAction.SetValue);
    app.connect(sld, goose_ui::SignalKind.OnValueChange, spn, goose_ui::SlotAction.SetValue);
    app.connect(ed, goose_ui::SignalKind.OnTextChange, lbl, goose_ui::SlotAction.SyncText);
    app.connect(sw, goose_ui::SignalKind.OnToggle, goose_ui::WIDGET_NONE, goose_ui::SlotAction.ToggleTheme);

    app.update_layout(win, true);

    // 1. Button click
    let rb = app.widget_rect(btn);
    app.inject_click(win, rb.x + rb.w * 0.5, rb.y + rb.h * 0.5);
    var got_click = false;
    var sig = goose_ui::Signal.None;
    while app.next_signal(sig) {
        match sig {
            Clicked s => { if goose_ui::eq(s.widget, btn) { got_click = true; } },
            _ => {},
        }
    }
    assert(got_click);

    // 2. CheckBox toggle disables button via declarative connect
    let rc = app.widget_rect(chk);
    app.inject_click(win, rc.x + 10.0, rc.y + rc.h * 0.5);
    assert(!app.is_checked(chk));
    assert(!app.is_enabled(btn));

    // Clicking disabled button must NOT emit Clicked
    while app.next_signal(sig) {}
    app.inject_click(win, rb.x + rb.w * 0.5, rb.y + rb.h * 0.5);
    var disabled_clicked = false;
    while app.next_signal(sig) {
        match sig {
            Clicked s => { if goose_ui::eq(s.widget, btn) { disabled_clicked = true; } },
            _ => {},
        }
    }
    assert(!disabled_clicked);

    // 3. ToggleSwitch toggles theme dark -> light
    assert(app.is_dark_theme());
    let rsw = app.widget_rect(sw);
    app.inject_click(win, rsw.x + 20.0, rsw.y + rsw.h * 0.5);
    assert(!app.is_dark_theme());

    // 4. RadioButton auto-exclusivity
    assert(app.is_checked(rad1) && !app.is_checked(rad2));
    let rr2 = app.widget_rect(rad2);
    app.inject_click(win, rr2.x + 10.0, rr2.y + rr2.h * 0.5);
    assert(!app.is_checked(rad1) && app.is_checked(rad2));

    // 5. Slider wheel + arrow syncs ProgressBar and SpinBox via connect()
    let rsld = app.widget_rect(sld);
    app.inject_mouse_wheel(win, rsld.x + rsld.w * 0.5, rsld.y + rsld.h * 0.5, 120);
    assert(app.value(sld) == 25.0);
    assert(app.value(pb) == 25.0);
    assert(app.value(spn) == 25.0);

    // SpinBox '+' button click
    let rspn = app.widget_rect(spn);
    app.inject_click(win, rspn.x + rspn.w - 10.0, rspn.y + rspn.h * 0.5);
    assert(app.value(spn) == 30.0);

    // 6. LineEdit UTF-8 typing, Backspace, Left, Insert, Ctrl+A, Enter, Live SyncText
    let red = app.widget_rect(ed);
    app.inject_click(win, red.x + 10.0, red.y + red.h * 0.5);
    app.inject_text(win, "Hello 日本語!");
    assert(app.text(ed) == "Hello 日本語!");
    assert(app.text(lbl) == "Hello 日本語!");

    // Backspace deletes '!' then '語' (full 3-byte UTF-8 char!)
    app.inject_key(win, win32::VK_BACK);
    app.inject_key(win, win32::VK_BACK);
    assert(app.text(ed) == "Hello 日本");

    // Ctrl+A then replace all
    app.inject_key(win, 'A', goose_ui::KMOD_CTRL);
    app.inject_text(win, "Goose");
    assert(app.text(ed) == "Goose");

    while app.next_signal(sig) {}
    app.inject_key(win, win32::VK_RETURN);
    var submitted = false;
    while app.next_signal(sig) {
        match sig {
            TextSubmitted s => { if goose_ui::eq(s.widget, ed) { submitted = true; } },
            _ => {},
        }
    }
    assert(submitted);

    app.destroy_all();
    print("[OK] interactive widgets, UTF-8 LineEdit & declarative Signal/Slot connections");
}

fn test_combo_list_tabs_focus() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("ComplexTest", 640, 480);
    let root = app.root(win);
    app.set_padding(root, 10.0);
    app.set_spacing(root, 8.0);

    let tabs = app.add_tab_widget(root);
    app.set_stretch(tabs, 1.0);
    let p0 = app.add_tab(tabs, "First");
    let p1 = app.add_tab(tabs, "Second");

    let cb = app.add_combo_box(p0);
    app.add_item(cb, "Alpha");
    app.add_item(cb, "Beta");
    app.add_item(cb, "Gamma");

    let lv = app.add_list_view(p0, 28.0);
    app.set_stretch(lv, 1.0);
    for i: i32 in 0..10 {
        app.add_item(lv, str("Row ", i));
    }

    let b_p1 = app.add_button(p1, "Page 2 Button");

    app.update_layout(win, true);

    // Tab 0 active -> page 1 button has empty rect
    assert(app.widget_rect(b_p1).w == 0.0);
    assert(app.widget_rect(cb).w > 0.0);

    // Open ComboBox and select "Gamma" (index 2)
    let rcb = app.widget_rect(cb);
    app.inject_click(win, rcb.x + 20.0, rcb.y + rcb.h * 0.5);
    let pop = goose_ui::combo_popup_rect(app, cb);
    assert(pop.w > 0.0 && pop.h > 0.0);
    app.inject_click(win, pop.x + 20.0, pop.y + 4.0 + 2.0 * 28.0 + 10.0);
    assert(app.selected_index(cb) == 2);

    // ListView click row 1, then VK_DOWN -> row 2
    let rlv = app.widget_rect(lv);
    app.inject_click(win, rlv.x + 20.0, rlv.y + 4.0 + 28.0 + 10.0);
    assert(app.selected_index(lv) == 1);
    app.inject_key(win, win32::VK_DOWN);
    assert(app.selected_index(lv) == 2);

    // Switch to Tab 1 by clicking tab header #1
    let th1 = goose_ui::tab_header_rect(app, tabs, 1);
    app.inject_click(win, th1.x + th1.w * 0.5, th1.y + th1.h * 0.5);
    app.update_layout(win);
    assert(app.current_tab(tabs) == 1);
    assert(app.widget_rect(b_p1).w > 0.0);

    // Tab key focuses b_p1
    app.inject_key(win, win32::VK_TAB);
    assert(goose_ui::eq(app.windows[win.index].focused, b_p1));

    app.destroy_all();
    print("[OK] ComboBox popup, ListView keyboard nav, TabWidget switching & focus traversal");
}

fn test_real_win32_d2d_smoke() {
    var app = goose_ui::App { .. };
    app.init(true);
    let win = app.create_window("goose_ui Smoke Test", 480, 320);
    assert(app.valid_window(win));

    let mbar = app.create_menu_bar(win);
    let sub = goose_ui::add_submenu(mbar, "&File");
    assert(goose_ui::add_action(sub, 1, "&Quit"));
    app.refresh_menu_bar(win);

    app.set_status_bar(win, "Smoke test status");
    let root = app.root(win);
    app.set_padding(root, 12.0);
    app.add_label(root, "Direct2D Render Check", goose_ui::FontRole.Heading);
    app.add_button(root, "Primary", goose_ui::ButtonVariant.Primary);
    let c = app.add_canvas(root, 120.0, 80.0);
    app.set_stretch(c, 1.0);

    // Render without showing on screen (set visible flag for D2D draw pass test)
    app.windows[win.index].visible = true;
    var canvas_painted = false;
    app.render_window_with(win) { cid, p =>
        if goose_ui::eq(cid, c) {
            p.fill_ellipse(p.width * 0.5, p.height * 0.5, 24.0, 24.0, p.theme.accent);
            canvas_painted = true;
        }
    };
    assert(canvas_painted);

    // Switch theme live and re-render
    app.toggle_theme();
    assert(!app.is_dark_theme());
    app.render_window(win);

    app.destroy_all();
    print("[OK] real Win32 + Direct2D + DirectWrite window, menu bar, Canvas & theme render");
}

fn test_software_gdi_and_str_pool() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Software);
    let win = app.create_window("goose_ui Software GDI Test", 480, 320);
    assert(app.valid_window(win));

    let root = app.root(win);
    app.set_padding(root, 12.0);
    let lbl = app.add_label(root, "Software GDI ClearType", goose_ui::FontRole.Heading);
    let ed = app.add_line_edit(root, "Placeholder", "Initial");
    app.add_button(root, "Primary", goose_ui::ButtonVariant.Primary);
    app.add_checkbox(root, "Check", true);
    app.add_toggle_switch(root, "Toggle", true);
    app.add_progress_bar(root, 0.0, 100.0, 65.0);
    let c = app.add_canvas(root, 120.0, 60.0);
    app.set_stretch(c, 1.0);

    // Verify string pool in-place reuse (updating text shorter than capacity grows pool by 0 bytes)
    let ed_cap_before = app.str_pool.len;
    app.set_text(ed, "Short");
    assert(app.text(ed) == "Short");
    assert(app.str_pool.len == ed_cap_before);

    // Verify rendering on Software GDI backend (no Direct2D target created)
    assert(!app.windows[win.index].d2d.is_valid());
    app.windows[win.index].visible = true;
    var canvas_painted = false;
    app.render_window_with(win) { cid, p =>
        if goose_ui::eq(cid, c) {
            p.fill_rounded_rect(8.0, 8.0, p.width - 16.0, p.height - 16.0, 6.0, p.theme.accent);
            p.draw_text("GDI Canvas", 12.0, 10.0, 140.0, 22.0, p.theme.accent_text);
            canvas_painted = true;
        }
    };
    assert(canvas_painted);

    app.toggle_theme();
    app.set_text(lbl, "Light Software GDI");
    app.render_window(win);

    app.destroy_all();
    print("[OK] Software GDI + ClearType backend & zero-alloc string pool reuse");
}

fn test_opengl_backend_render() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.OpenGL);
    let win = app.create_window("goose_ui OpenGL 3.3 Test", 480, 320);
    assert(app.valid_window(win));
    assert(app.windows[win.index].gl2d.is_valid());
    assert(!app.windows[win.index].d2d.is_valid());

    let root = app.root(win);
    app.set_padding(root, 12.0);
    app.add_label(root, "OpenGL 3.3 GPU + 日本語アトラス", goose_ui::FontRole.Heading);
    app.add_button(root, "Primary", goose_ui::ButtonVariant.Primary);
    let sc = app.add_scroll_area(root);
    app.set_stretch(sc, 1.0);
    let c = app.add_canvas(sc, 160.0, 90.0);

    app.windows[win.index].visible = true;
    var canvas_painted = false;
    var px: u32 = 0;
    app.render_window_with(win) { cid, p =>
        if goose_ui::eq(cid, c) {
            p.fill_rounded_rect(4.0, 4.0, p.width - 8.0, p.height - 8.0, 6.0, goose_ui::rgb(34, 211, 238));
            p.draw_text("OpenGL 日本語 Canvas", 12.0, 10.0, 140.0, 24.0, goose_ui::rgb(15, 23, 42));
            let r = app.widget_rect(c);
            let canvas_x = (r.x + 40.0) as! i32;
            let canvas_y = (r.y + 40.0) as! i32;
            // Read back before end_draw() swaps buffers on GL_BACK.
            assert(p.gl2d.readback_pixel(canvas_x, canvas_y, px));
            canvas_painted = true;
        }
    };
    assert(canvas_painted);

    let rch = px & 0xFF;
    let gch = (px >> 8) & 0xFF;
    let bch = (px >> 16) & 0xFF;
    assert(rch <= 45 && gch >= 200 && bch >= 225);

    app.toggle_theme();
    app.render_window(win);

    app.destroy_all();
    print("[OK] OpenGL 3.3 Core SDF + GPU VRAM atlas backend (RenderBackend.OpenGL)");
}

fn test_dsl_and_win32_anchors() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("DSL & Anchor Test", 500, 300);

    let ID_TITLE = 1001;
    let ID_GO = 1002;
    let ID_SEARCH = 1003;
    let ID_LIST = 1004;

    var btn_go = goose_ui::WIDGET_NONE;

    app.ui(win) { u =>
        u.anchored_panel() { f =>
            f.label("Find:").bounds(16.0, 16.0, 60.0, 28.0, goose_ui::ANCHOR_TOP_LEFT, 500.0, 300.0).action(ID_TITLE);
            f.line_edit("Query...").bounds(84.0, 16.0, 310.0, 28.0, goose_ui::ANCHOR_H_STRETCH, 500.0, 300.0).action(ID_SEARCH);
            f.button("Go").primary().bounds(404.0, 16.0, 80.0, 28.0, goose_ui::ANCHOR_TOP_RIGHT, 500.0, 300.0).action(ID_GO).bind(btn_go);
            f.list_view().bounds(16.0, 56.0, 468.0, 228.0, goose_ui::ANCHOR_ALL, 500.0, 300.0).item("One").item("Two").select(0).action(ID_LIST);
        };
    };

    // Initial 500x300 layout
    app.update_layout(win, true);
    let r_go0 = app.widget_rect(btn_go);
    let r_ed0 = app.widget_rect(app.by_id(win, ID_SEARCH));
    let r_lv0 = app.widget_rect(app.by_id(win, ID_LIST));
    assert(approx(r_go0.x, 404.0) && approx(r_go0.w, 80.0));
    assert(approx(r_ed0.w, 310.0));
    assert(approx(r_lv0.w, 468.0) && approx(r_lv0.h, 228.0));

    // Resize window +200 width, +100 height -> anchors must follow automatically!
    app.windows[win.index].width = 700;
    app.windows[win.index].height = 400;
    app.update_layout(win, true);
    let r_go1 = app.widget_rect(btn_go);
    let r_ed1 = app.widget_rect(app.by_id(win, ID_SEARCH));
    let r_lv1 = app.widget_rect(app.by_id(win, ID_LIST));
    assert(approx(r_go1.x, 604.0) && approx(r_go1.w, 80.0)); // pinned to right edge
    assert(approx(r_ed1.w, 510.0));                          // stretched horizontally by +200
    assert(approx(r_lv1.w, 668.0) && approx(r_lv1.h, 328.0));// stretched both ways (+200, +100)

    // Win32-style ID text accessors + click dispatch via action_id
    app.set_text_of(win, ID_TITLE, "Search:");
    assert(app.text_of(win, ID_TITLE) == "Search:");
    app.inject_click(win, r_go1.x + 20.0, r_go1.y + 14.0);
    var got_go = false;
    var sig = goose_ui::Signal.None;
    while app.next_signal(sig) {
        match sig {
            Clicked s => { if app.action_id(s.widget) == ID_GO { got_go = true; } },
            _ => {},
        }
    }
    assert(got_go);

    app.destroy_all();
    print("[OK] Scoped DSL, Win32 action IDs & WinForms-style Anchor resize layout");
}

fn test_regressions_canvas_and_visibility() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Software);
    let win = app.create_window("Canvas Visibility Regression", 520, 360);
    assert(app.valid_window(win));

    // Re-creating menu bar must replace previous menu cleanly without leak/crash
    let mb1 = app.create_menu_bar(win);
    let _f1 = goose_ui::add_submenu(mb1, "&File");
    let mb2 = app.create_menu_bar(win);
    let _f2 = goose_ui::add_submenu(mb2, "&Edit");
    app.refresh_menu_bar(win);

    let root = app.root(win);
    let tabs = app.add_tab_widget(root);
    app.set_stretch(tabs, 1.0);
    let p0 = app.add_tab(tabs, "Tab & Zero");
    let p1 = app.add_tab(tabs, "Canvas Tab");

    // ScrollArea with single tall VBox child (must remain traversable and render safely)
    let sc = app.add_scroll_area(p0, 6.0, 8.0);
    app.set_stretch(sc, 1.0);
    let tall_box = app.add_vbox(sc, 6.0, 4.0);
    for i: i32 in 0..15 {
        app.add_label(tall_box, str("Item & ", i));
    }

    let cv_wrap = app.add_vbox(p1, 4.0, 4.0);
    app.set_stretch(cv_wrap, 1.0);
    let cv = app.add_canvas(cv_wrap, 120.0, 80.0);
    app.set_stretch(cv, 1.0);

    app.windows[win.index].visible = true;

    // 1. Activate Tab 1 -> Canvas must paint
    app.set_current_tab(tabs, 1);
    var painted_count: i32 = 0;
    app.render_window_with(win) { cid, p =>
        if goose_ui::eq(cid, cv) {
            p.fill_rect(0.0, 0.0, p.width, p.height, p.theme.accent);
            painted_count += 1;
        }
    };
    assert(painted_count == 1);

    // 2. Switch back to Tab 0 -> inactive tab's Canvas MUST NOT paint
    app.set_current_tab(tabs, 0);
    painted_count = 0;
    app.render_window_with(win) { cid, _p =>
        if goose_ui::eq(cid, cv) { painted_count += 1; }
    };
    assert(painted_count == 0);
    assert(app.widget_rect(cv).w == 0.0 && app.widget_rect(cv).h == 0.0);

    // 3. Switch to Tab 1 but hide Canvas's parent container -> Canvas MUST NOT paint
    app.set_current_tab(tabs, 1);
    app.set_visible(cv_wrap, false);
    painted_count = 0;
    app.render_window_with(win) { cid, _p =>
        if goose_ui::eq(cid, cv) { painted_count += 1; }
    };
    assert(painted_count == 0);

    app.destroy_all();
    print("[OK] inactive tab / hidden ancestor Canvas culling, ScrollArea & menu lifecycle");
}

fn test_regressions_inputs_and_signals() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("InputRegressions", 720, 520);
    let root = app.root(win);
    app.set_padding(root, 10.0);
    app.set_spacing(root, 8.0);

    // 1. ListView dynamic add_item scroll_max_y update, padding guard, keyboard scroll follow, compaction
    let lv = app.add_list_view(root, 28.0);
    app.set_fixed_height(lv, 100.0);
    app.update_layout(win, true);
    assert(app.widgets[lv.index].scroll_max_y == 0.0);

    for i: i32 in 0..20 {
        app.add_item(lv, str("Row ", i));
    }
    app.update_layout(win); // non-forced: add_item must have marked layout dirty
    assert(app.widgets[lv.index].scroll_max_y > 0.0);

    // Top padding click (y = r.y + 1.0) must NOT select row 0
    let rlv = app.widget_rect(lv);
    app.inject_click(win, rlv.x + 20.0, rlv.y + 1.0);
    assert(app.selected_index(lv) == -1);

    // Select row 0, then press VK_DOWN 10 times -> scroll_y must auto-follow
    app.inject_click(win, rlv.x + 20.0, rlv.y + 12.0);
    assert(app.selected_index(lv) == 0);
    for _ in 0..10 {
        app.inject_key(win, win32::VK_DOWN);
    }
    assert(app.selected_index(lv) == 10);
    assert(app.widgets[lv.index].scroll_y > 0.0);

    // Clear items must compact list_items tail
    app.clear_items(lv);
    assert(app.list_items.len == 0);

    // 2. ComboBox > 8 items scroll, top padding guard, keyboard hover sync
    let cb = app.add_combo_box(root);
    for i: i32 in 0..12 {
        app.add_item(cb, str("Option ", i));
    }
    app.update_layout(win, true);
    let rcb = app.widget_rect(cb);
    app.inject_click(win, rcb.x + 20.0, rcb.y + rcb.h * 0.5);
    assert(goose_ui::eq(app.windows[win.index].open_combo, cb));
    let pop = goose_ui::combo_popup_rect(app, cb);

    // Clicking top 4px padding inside popup must NOT select item 0 or close popup unexpectedly
    app.set_selected_index(cb, 2);
    app.inject_click(win, pop.x + 20.0, pop.y + 1.0);
    assert(app.selected_index(cb) == 2);

    // Scroll popup down by 3 items and click visible row 7 -> selects item 10
    app.inject_mouse_wheel(win, pop.x + 20.0, pop.y + 40.0, -120);
    app.inject_mouse_wheel(win, pop.x + 20.0, pop.y + 40.0, -120);
    app.inject_mouse_wheel(win, pop.x + 20.0, pop.y + 40.0, -120);
    assert(app.windows[win.index].open_combo_scroll == 3);
    app.inject_click(win, pop.x + 20.0, pop.y + 4.0 + 7.0 * 28.0 + 10.0);
    assert(app.selected_index(cb) == 10);

    // Open again via VK_SPACE and check VK_UP syncs open_combo_hover
    app.set_focus(win, cb);
    app.inject_key(win, win32::VK_SPACE);
    assert(goose_ui::eq(app.windows[win.index].open_combo, cb));
    app.inject_key(win, win32::VK_UP);
    assert(app.selected_index(cb) == 9);
    assert(app.windows[win.index].open_combo_hover == 9);
    app.inject_key(win, win32::VK_ESCAPE);

    // 3. LineEdit UTF-8 set_text caret safety, Ctrl+F7/F9 non-misfire, password click accuracy
    let ed = app.add_line_edit(root, "", "abcdef");
    app.update_layout(win, true);
    app.set_focus(win, ed);
    app.widgets[ed.index].caret = 4;
    app.widgets[ed.index].sel_anchor = 4;
    app.set_text(ed, "日本語");
    assert(app.widgets[ed.index].caret == 9); // snapped/reset to valid UTF-8 end
    app.inject_text(win, "!");
    assert(app.text(ed) == "日本語!");

    // Ctrl+F7 (0x76 == 'v') and Ctrl+F9 (0x78 == 'x') must NOT trigger cut/paste
    app.inject_key(win, 'A', goose_ui::KMOD_CTRL);
    app.inject_key(win, win32::VK_F9, goose_ui::KMOD_CTRL);
    assert(app.text(ed) == "日本語!");

    // Password mode click positioning uses '*' width rather than CJK width
    app.set_password_mode(ed, true);
    app.set_text(ed, "日本語");
    let red = app.widget_rect(ed);
    let star_w = goose_ui::password_char_width(app.theme.font_size_body, false);
    app.inject_click(win, red.x + 9.0 + star_w * 1.1, red.y + red.h * 0.5);
    assert(app.widgets[ed.index].caret == 3); // 2nd char boundary (3 bytes)

    // 4. DoubleClicked signal & triple-click reset
    let dbl_btn = app.add_button(root, "Dbl");
    app.update_layout(win, true);
    let rd = app.widget_rect(dbl_btn);
    var sig = goose_ui::Signal.None;
    while app.next_signal(sig) {}
    app.inject_click(win, rd.x + 10.0, rd.y + 10.0);
    app.inject_click(win, rd.x + 10.0, rd.y + 10.0);
    app.inject_click(win, rd.x + 10.0, rd.y + 10.0);
    var dbl_count: i32 = 0;
    while app.next_signal(sig) {
        match sig {
            DoubleClicked s => { if goose_ui::eq(s.widget, dbl_btn) { dbl_count += 1; } },
            _ => {},
        }
    }
    assert(dbl_count == 1);

    // 5. RadioButton deselected sibling emits Toggled(false) and fires connections
    let rbox = app.add_hbox(root, 6.0);
    let r1 = app.add_radio_button(rbox, "R1", true);
    let r2 = app.add_radio_button(rbox, "R2", false);
    let linked_panel = app.add_label(root, "Linked to R1");
    app.connect(r1, goose_ui::SignalKind.OnToggle, linked_panel, goose_ui::SlotAction.SetVisible);
    app.update_layout(win, true);
    while app.next_signal(sig) {}
    let rr2 = app.widget_rect(r2);
    app.inject_click(win, rr2.x + 10.0, rr2.y + rr2.h * 0.5);
    assert(!app.is_checked(r1) && app.is_checked(r2));
    assert(!app.is_visible(linked_panel));
    var r1_off_sig = false;
    while app.next_signal(sig) {
        match sig {
            Toggled s => { if goose_ui::eq(s.widget, r1) && !s.checked { r1_off_sig = true; } },
            _ => {},
        }
    }
    assert(r1_off_sig);

    // 6. Canvas right-click emits both CanvasMouseDown and CanvasMouseUp
    let cv = app.add_canvas(root, 80.0, 40.0);
    app.set_fixed_height(cv, 40.0);
    app.update_layout(win, true);
    let rcv = app.widget_rect(cv);
    while app.next_signal(sig) {}
    app.inject_mouse_down(win, rcv.x + 10.0, rcv.y + 10.0, goose_ui::MOUSE_RIGHT);
    app.inject_mouse_up(win, rcv.x + 10.0, rcv.y + 10.0, goose_ui::MOUSE_RIGHT);
    var got_rdown = false;
    var got_rup = false;
    while app.next_signal(sig) {
        match sig {
            CanvasMouseDown s => { if goose_ui::eq(s.widget, cv) && s.button == goose_ui::MOUSE_RIGHT { got_rdown = true; } },
            CanvasMouseUp s => { if goose_ui::eq(s.widget, cv) && s.button == goose_ui::MOUSE_RIGHT { got_rup = true; } },
            _ => {},
        }
    }
    assert(got_rdown && got_rup);

    // 7. IncrementValue chains to downstream SetValueLabel
    let inc_btn = app.add_button(root, "+10");
    let sld = app.add_slider(root, 0.0, 100.0, 40.0, 1.0);
    let vlbl = app.add_label(root, "40");
    app.connect(sld, goose_ui::SignalKind.OnValueChange, vlbl, goose_ui::SlotAction.SetValueLabel);
    app.connect(inc_btn, goose_ui::SignalKind.OnClick, sld, goose_ui::SlotAction.IncrementValue, 10.0);
    app.update_layout(win, true);
    let rib = app.widget_rect(inc_btn);
    app.inject_click(win, rib.x + 10.0, rib.y + 10.0);
    assert(app.value(sld) == 50.0);
    assert(app.text(vlbl) == "50");

    // 8. UTF-8 helper bounds safety
    assert(goose_ui::utf8_prev_char("", 3) == 0);
    assert(goose_ui::utf8_next_char("abc", -5) == 0);

    app.destroy_all();

    // 9. Reverse Shift+Tab from index 0 wraps safely; ListView & Canvas clear hover on leave
    {
        var app2 = goose_ui::App { .. };
        let w2 = app2.create_headless_window("FocusHoverReg", 420, 320);
        let r2_root = app2.root(w2);
        let b0 = app2.add_button(r2_root, "First");
        let b1 = app2.add_button(r2_root, "Second");
        let lv2 = app2.add_list_view(r2_root, 26.0);
        app2.set_fixed_height(lv2, 90.0);
        app2.add_item(lv2, "Item A");
        app2.add_item(lv2, "Item B");
        let cv2 = app2.add_canvas(r2_root, 120.0, 50.0);
        app2.set_fixed_height(cv2, 50.0);
        app2.update_layout(w2, true);

        app2.set_focus(w2, b0);
        app2.inject_key(w2, win32::VK_TAB, goose_ui::KMOD_SHIFT);
        assert(goose_ui::eq(app2.windows[w2.index].focused, cv2));
        app2.inject_key(w2, win32::VK_TAB, goose_ui::KMOD_SHIFT);
        assert(goose_ui::eq(app2.windows[w2.index].focused, lv2));

        let rlv2 = app2.widget_rect(lv2);
        app2.inject_mouse_move(w2, rlv2.x + 12.0, rlv2.y + 10.0);
        assert(app2.widgets[lv2.index].hovered_item == 0);

        let rcv2 = app2.widget_rect(cv2);
        app2.inject_mouse_move(w2, rcv2.x + 10.0, rcv2.y + 10.0);
        assert(app2.widgets[lv2.index].hovered_item == -1);

        while app2.next_signal(sig) {}
        let rb0 = app2.widget_rect(b0);
        app2.inject_mouse_move(w2, rb0.x + 10.0, rb0.y + 10.0);
        var saw_leave = false;
        while app2.next_signal(sig) {
            match sig {
                CanvasMouseLeave s => { if goose_ui::eq(s.widget, cv2) { saw_leave = true; } },
                _ => {},
            }
        }
        assert(saw_leave);
        let _unused = b1;
        app2.destroy_all();
    }

    print("[OK] ListView/ComboBox/LineEdit/Radio/Canvas/DoubleClick/IncrementValue regressions");
}

fn test_regressions_layout_and_pools() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("LayoutRegressions", 500, 326);
    let _sb = app.set_status_bar(win, "Docked"); // 26px -> root height = 300px
    let root = app.root(win);

    // 1. Anchored panel with omitted ref_w/ref_h must capture inner size (500x300), not window (500x326)
    let ap = app.add_panel(root, goose_ui::LayoutKind.None, 0.0, 0.0);
    app.set_size_policy(ap, goose_ui::SizePolicy.Expanding, goose_ui::SizePolicy.Expanding);
    let br_btn = app.add_button(ap, "OK");
    app.set_bounds(br_btn, 400.0, 260.0, 80.0, 28.0, goose_ui::ANCHOR_BOTTOM_RIGHT);
    let none_btn = app.add_button(ap, "Static");
    app.set_bounds(none_btn, 10.0, 10.0, 70.0, 28.0, goose_ui::ANCHOR_NONE);
    app.update_layout(win, true);

    assert(approx(app.widget_rect(br_btn).y, 260.0));
    assert(approx(app.widget_rect(none_btn).x, 10.0) && approx(app.widget_rect(none_btn).w, 70.0));
    assert(app.widgets[none_btn.index].anchor == goose_ui::ANCHOR_NONE);

    // Resize window +50 height -> br_btn moves +50, none_btn stays put
    app.windows[win.index].height = 376;
    app.update_layout(win, true);
    assert(approx(app.widget_rect(br_btn).y, 310.0));
    assert(approx(app.widget_rect(none_btn).y, 10.0));

    // 2. fixed_w + stretch must not steal extra space from stretched sibling; max_size clamps cross-axis
    let hrow = app.add_hbox(root, 10.0);
    let fixed_stretched = app.add_button(hrow, "Fix");
    app.set_stretch(fixed_stretched, 1.0);
    app.set_fixed_width(fixed_stretched, 100.0);
    let flex = app.add_button(hrow, "Flex");
    app.set_stretch(flex, 1.0);

    let max_btn = app.add_button(root, "Capped");
    app.set_max_size(max_btn, 120.0, 40.0);

    // 3. GroupBox set_padding preserves title clearance
    let gb = app.add_group_box(root, "Title");
    app.set_padding(gb, 16.0);
    let gb_child = app.add_label(gb, "Inside");

    // 4. Splitter with hidden first child still positions handle via split_ratio
    let sp = app.add_splitter(root, goose_ui::Orientation.Horizontal, 0.4);
    app.set_fixed_height(sp, 60.0);
    let sp0 = app.add_panel(sp);
    let _sp1 = app.add_panel(sp);
    app.set_visible(sp0, false);

    // 5. TabWidget focus clearing on switch & remove_item destroying page cleanly
    let tw = app.add_tab_widget(root);
    app.set_fixed_height(tw, 80.0);
    let tp0 = app.add_tab(tw, "P0");
    let tp1 = app.add_tab(tw, "P1");
    let tp0_ed = app.add_line_edit(tp0, "", "abc");
    let tp1_btn = app.add_button(tp1, "Tab1Btn");

    app.update_layout(win, true);

    assert(approx(app.widget_rect(fixed_stretched).w, 100.0));
    assert(approx(app.widget_rect(flex).w, 390.0)); // 500 - 100 - 10
    assert(approx(app.widget_rect(max_btn).w, 120.0));
    assert(app.widget_rect(gb_child).y >= app.widget_rect(gb).y + 34.0);

    let hrc = goose_ui::splitter_handle_rect(app, sp);
    assert(hrc.x > 150.0); // ~200px, not warped to x = -2

    // Focus on Tab 0 input -> switching to Tab 1 clears focus
    app.set_focus(win, tp0_ed);
    assert(goose_ui::eq(app.windows[win.index].focused, tp0_ed));
    app.set_current_tab(tw, 1);
    assert(!app.valid_widget(app.windows[win.index].focused));

    // Removing Tab 0 destroys tp0 and maps tp1 to tab index 0
    assert(app.remove_item(tw, 0));
    assert(!app.valid_widget(tp0));
    assert(app.current_tab(tw) == 0);
    app.update_layout(win, true);
    assert(app.widget_rect(tp1_btn).w > 0.0);

    // Disabling focused widget clears focus
    app.set_focus(win, tp1_btn);
    assert(goose_ui::eq(app.windows[win.index].focused, tp1_btn));
    app.set_enabled(tp1_btn, false);
    assert(!app.valid_widget(app.windows[win.index].focused));

    // Timer slot reuse
    let t1 = app.start_timer(win, 100);
    let cap_after_1 = app.timers.len;
    app.stop_timer(t1);
    let _t2 = app.start_timer(win, 100);
    assert(app.timers.len == cap_after_1);

    app.destroy_all();
    print("[OK] layout constraints, Splitter/GroupBox/Anchor/TabWidget & pool reuse regressions");
}

fn count_lines_and_validate_json(path: const u8[:]) -> i64 {
    var content: u8[>..] = [];
    assert(win32::read_file_bytes(path, content));
    var count: i64 = 0;
    var pos: i64 = 0;
    while pos < content.len {
        var nl = pos;
        while nl < content.len && content[nl] != '\n' {
            nl += 1;
        }
        let line = trim(content[pos..nl]);
        pos = if nl < content.len { nl + 1 } else { nl };
        if line.len == 0 { continue; }
        var doc: json::Node[>..] = [];
        var decoded: u8[>..] = [];
        let root, _err = json::parse(line, doc, decoded);
        assert(root != null);
        count += 1;
    }
    return count;
}

fn test_json_logging() {
    let raw_tmp = win32::temp_dir();
    let sep = if raw_tmp.len > 0 && (raw_tmp[raw_tmp.len - 1] == '\\' || raw_tmp[raw_tmp.len - 1] == '/') { "" } else { "\\" };
    let base_dir = str(raw_tmp, sep, "goose_ui_log_test_", win32::GetCurrentProcessId());
    let nested_dir = str(base_dir, "\\nested");
    let utf8_dir = str(nested_dir, "\\日本語");

    let path_jsonl = str(utf8_dir, "\\app.jsonl");
    let path_switch = str(base_dir, "\\switched.jsonl");
    let path_arr = str(base_dir, "\\events.json");
    let path_rot = str(base_dir, "\\rotate.jsonl");
    let path_standalone = str(base_dir, "\\standalone.jsonl");
    let path_ui = str(base_dir, "\\ui_events.jsonl");

    // 1. Level parsing & formatting helpers
    let lvl_w, ok_w = goose_ui::parse_log_level("WARN");
    assert(ok_w && goose_ui::log_level_name(lvl_w) == "warn");
    let lvl_e, ok_e = goose_ui::parse_log_level("  Error ");
    assert(ok_e && goose_ui::log_level_name(lvl_e) == "error");
    let _lvl_bad, ok_bad = goose_ui::parse_log_level("bogus");
    assert(!ok_bad);

    // 2. Invalid path & create_dirs=false checks
    var app = goose_ui::App { .. };
    assert(!app.log_open(""));
    assert(!app.log_open(str(base_dir, "\\")));
    assert(!app.log_open(str(base_dir, "\\missing_sub\\blocked.jsonl"), goose_ui::LogOptions { create_dirs: false }));
    assert(!app.log_is_open());

    // 3. User-specified nested UTF-8 path (JsonLines), filtering, escaping & fields
    assert(app.log_open(path_jsonl, goose_ui::LogOptions { append: false }));
    assert(app.log_is_open());
    assert(app.log_path() == path_jsonl);
    assert(goose_ui::log_level_name(app.log_level()) == "info");

    var skipped_called = false;
    assert(!app.log_trace("dropped trace"));
    assert(!app.log_debug("dbg", "dropped debug"));
    assert(!app.log_debug_with("dbg", "dropped with") { f =>
        skipped_called = true;
        f.text("k", "v");
    });
    assert(!skipped_called);
    assert(app.log_count() == 0);

    assert(app.log_info("net", "Line1\n\"quoted\"\\日本語"));
    assert(app.log_warn_with("ui", "empty fields") { _f => });

    let dummy_win = goose_ui::WindowId { index: 1, gen: 2 };
    let dummy_wid = goose_ui::WidgetId { index: 3, gen: 4 };
    assert(app.log_error_with("render", "complex payload") { f =>
        f.text("user", "あいう\"\\")
         .int("count", -42)
         .uint("uval", 99)
         .num("ratio", 1.5)
         .flag("ok", true)
         .nil("extra")
         .raw_json("raw", "{\"k\":1}")
         .window_id("win", dummy_win)
         .widget_id("wid", dummy_wid)
         .rect("box", goose_ui::rect(1.0, 2.0, 30.0, 40.0))
         .color("fg", goose_ui::rgb(255, 128, 0));
        f.obj("meta") { m =>
            m.text("backend", "software").int("ver", 2);
        };
        f.arr("tags") { a =>
            a.text("ui").int(7).uint(8).num(2.5).flag(false).nil().raw_json("{\"r\":true}");
            a.obj() { o => o.text("nested", "yes"); };
            a.arr() { sub => sub.int(1).int(2); };
        };
    });

    app.log_set_level(goose_ui::LogLevel.Trace);
    assert(app.log_trace_with("tr", "trace msg") { f => f.int("v", 1); });
    assert(app.log_warn("warn msg"));
    assert(app.log_fatal("fatal msg"));
    assert(app.log_fatal_with("ft", "fatal with") { f => f.flag("aborting", false); });
    assert(app.log_msg(goose_ui::LogLevel.Debug, "core", "generic msg"));
    assert(app.log_with(goose_ui::LogLevel.Info, "core", "generic with") { f => f.text("mode", "ok"); });
    assert(app.log_flush());
    assert(app.log_count() == 9);
    assert(app.log_bytes_written() > 0);

    // Parse and validate every emitted JsonLines line
    assert(count_lines_and_validate_json(path_jsonl) == 9);
    var line_idx: i64 = 0;
    let r_cnt, r_ok = goose_ui::each_json_log_entry(path_jsonl) { e =>
        var doc: json::Node[>..] = [];
        var decoded: u8[>..] = [];
        let root, _err = json::parse(e.raw_json, doc, decoded);
        assert(root != null);
        if line_idx == 0 {
            assert(e.seq == 1);
            assert(e.level_text == "info");
            assert(e.target == "net");
            assert(e.msg == "Line1\n\"quoted\"\\日本語");
            assert(e.pid > 0 && e.tid > 0);
            assert(e.ts.len == 23);
        } else if line_idx == 1 {
            assert(e.level_text == "warn");
            assert(json::member(root, "fields") == null);
        } else if line_idx == 2 {
            assert(e.level_text == "error");
            let flds = json::member(root, "fields");
            assert(flds != null);
            let u_s, u_ok = json::as_string(json::member(flds, "user"));
            assert(u_ok && u_s == "あいう\"\\");
            let c_v, c_ok = json::as_i64(json::member(flds, "count"));
            assert(c_ok && c_v == -42);
            let ratio_v, ratio_ok = json::as_f64(json::member(flds, "ratio"));
            assert(ratio_ok && ratio_v == 1.5);
            let ok_v, ok_flag = json::as_bool(json::member(flds, "ok"));
            assert(ok_flag && ok_v);
            let meta_n = json::member(flds, "meta");
            let bk_s, bk_ok = json::as_string(json::member(meta_n, "backend"));
            assert(bk_ok && bk_s == "software");
            let raw_n = json::member(flds, "raw");
            let rk_v, rk_ok = json::as_i64(json::member(raw_n, "k"));
            assert(rk_ok && rk_v == 1);
        }
        line_idx += 1;
    };
    assert(r_ok && r_cnt == 9);

    // 4. Reopen aliasing safety, append vs overwrite, and runtime path switching
    assert(app.log_open(app.log_path(), goose_ui::LogOptions { append: true }));
    assert(app.log_info("appended line"));
    assert(count_lines_and_validate_json(path_jsonl) == 10);

    assert(app.log_open(path_jsonl, goose_ui::LogOptions { append: false }));
    assert(app.log_info("overwritten line"));
    assert(count_lines_and_validate_json(path_jsonl) == 1);

    assert(app.log_open(path_switch, goose_ui::LogOptions { append: false }));
    assert(app.log_path() == path_switch);
    assert(app.log_info("switched file"));
    app.log_close();
    assert(!app.log_is_open());
    assert(app.log_open(path_switch));
    assert(app.log_info("default append"));
    app.log_close();
    assert(count_lines_and_validate_json(path_switch) == 2);

    // 5. LogFormat.JsonArray (empty, multi-entry, and reopen append)
    assert(app.log_open(path_arr, goose_ui::LogOptions {
        format: goose_ui::LogFormat.JsonArray,
        append: false,
    }));
    var arr_buf: u8[>..] = [];
    assert(win32::read_file_bytes(path_arr, arr_buf));
    var arr_doc0: json::Node[>..] = [];
    var arr_dec0: u8[>..] = [];
    let arr_root0, _e0 = json::parse(arr_buf, arr_doc0, arr_dec0);
    assert(arr_root0 != null);
    match arr_root0.val {
        Arr a => { assert(a.count == 0); },
        _ => { assert(false); },
    }

    assert(app.log_info("arr1", "first"));
    assert(app.log_warn_with("arr2", "second") { f => f.int("n", 2); });
    app.log_close();

    // Reopen existing JsonArray with append = true
    assert(app.log_open(path_arr, goose_ui::LogOptions {
        format: goose_ui::LogFormat.JsonArray,
        append: true,
    }));
    assert(app.log_error("arr3", "third"));
    app.log_close();

    arr_buf.clear();
    assert(win32::read_file_bytes(path_arr, arr_buf));
    var arr_doc1: json::Node[>..] = [];
    var arr_dec1: u8[>..] = [];
    let arr_root1, _e1 = json::parse(arr_buf, arr_doc1, arr_dec1);
    assert(arr_root1 != null);
    match arr_root1.val {
        Arr a => { assert(a.count == 3); },
        _ => { assert(false); },
    }
    let arr_cnt, arr_ok = goose_ui::each_json_log_entry(path_arr) { e =>
        assert(e.msg == "first" || e.msg == "second" || e.msg == "third");
    };
    assert(arr_ok && arr_cnt == 3);

    // 6. Size-based file rotation
    assert(app.log_open(path_rot, goose_ui::LogOptions {
        append: false,
        max_file_bytes: 240,
        max_backups: 2,
    }));
    for i: i32 in 0..10 {
        assert(app.log_info("rot", str("rotation entry number ", i, " payload")));
    }
    app.log_close();
    assert(win32::file_exists(path_rot));
    assert(win32::file_exists(str(path_rot, ".1")));
    assert(win32::file_exists(str(path_rot, ".2")));
    assert(!win32::file_exists(str(path_rot, ".3")));
    assert(count_lines_and_validate_json(path_rot) > 0);
    assert(count_lines_and_validate_json(str(path_rot, ".1")) > 0);
    assert(count_lines_and_validate_json(str(path_rot, ".2")) > 0);

    // 7. Standalone JsonLogger (utc=true, include_process_info=false)
    var jl = goose_ui::JsonLogger { .. };
    assert(jl.open(path_standalone, goose_ui::LogOptions {
        min_level: goose_ui::LogLevel.Trace,
        append: false,
        utc: true,
        include_process_info: false,
    }));
    assert(jl.is_open() && jl.log_path() == path_standalone);
    jl.set_stderr(false);
    jl.set_auto_flush(true);
    jl.set_level(goose_ui::LogLevel.Trace);
    assert(goose_ui::log_level_name(jl.level()) == "trace");
    assert(jl.trace("t"));
    assert(jl.debug("d"));
    assert(jl.info("tag", "i"));
    assert(jl.warn("w"));
    assert(jl.error("e"));
    assert(jl.fatal("f"));
    assert(jl.info_with("tag", "iw") { f => f.int("x", 1); });
    assert(jl.write(goose_ui::LogLevel.Warn, "wt", "wm"));
    assert(jl.write_with(goose_ui::LogLevel.Error, "et", "em") { f => f.flag("b", true); });
    assert(jl.flush());
    assert(jl.entry_count() == 9);
    assert(jl.bytes_written() > 0);
    jl.close();
    assert(!jl.is_open());

    var checked_utc = false;
    let jl_cnt, jl_ok = goose_ui::each_json_log_entry(path_standalone) { e =>
        if !checked_utc {
            assert(e.ts.len > 0 && e.ts[e.ts.len - 1] == 'Z');
            var doc: json::Node[>..] = [];
            var decoded: u8[>..] = [];
            let root, _err = json::parse(e.raw_json, doc, decoded);
            assert(root != null);
            assert(json::member(root, "pid") == null);
            assert(json::member(root, "tid") == null);
            checked_utc = true;
        }
    };
    assert(jl_ok && jl_cnt == 9 && checked_utc);

    // 8. Automatic UI event logging (log_ui_events=true) & destroy_all() auto-close
    var ui_app = goose_ui::App { .. };
    assert(ui_app.log_open(path_ui, goose_ui::LogOptions {
        min_level: goose_ui::LogLevel.Debug,
        append: false,
        log_ui_events: true,
    }));
    ui_app.log_set_stderr(false);
    ui_app.log_set_auto_flush(true);
    ui_app.log_set_ui_events(true);

    let win = ui_app.create_headless_window("LogUITest", 400, 300);
    let root = ui_app.root(win);
    let btn = ui_app.add_button(root, "Save");
    ui_app.set_name(btn, "save_btn");
    ui_app.set_tag(btn, 777);
    ui_app.update_layout(win, true);

    let rbtn = ui_app.widget_rect(btn);
    ui_app.inject_click(win, rbtn.x + rbtn.w * 0.5, rbtn.y + rbtn.h * 0.5);

    ui_app.destroy_all();
    assert(!ui_app.log_is_open());

    var saw_clicked = false;
    let ui_cnt, ui_ok = goose_ui::each_json_log_entry(path_ui) { e =>
        if e.target == "goose_ui.signal" && e.msg == "Clicked" {
            var doc: json::Node[>..] = [];
            var decoded: u8[>..] = [];
            let root_n, _err = json::parse(e.raw_json, doc, decoded);
            assert(root_n != null);
            let flds = json::member(root_n, "fields");
            let wn, wn_ok = json::as_string(json::member(flds, "widget_name"));
            let aid, aid_ok = json::as_i64(json::member(flds, "action_id"));
            if wn_ok && wn == "save_btn" && aid_ok && aid == 777 {
                saw_clicked = true;
            }
        }
    };
    assert(ui_ok && ui_cnt >= 1 && saw_clicked);

    // 9. Clean up temp test files and directories
    win32::delete_file(path_jsonl);
    win32::delete_file(path_switch);
    win32::delete_file(path_arr);
    win32::delete_file(path_rot);
    win32::delete_file(str(path_rot, ".1"));
    win32::delete_file(str(path_rot, ".2"));
    win32::delete_file(path_standalone);
    win32::delete_file(path_ui);
    win32::remove_directory(utf8_dir);
    win32::remove_directory(nested_dir);
    win32::remove_directory(base_dir);

    print("[OK] JSON logging (JsonLines, JsonArray, fields, rotation, UI events, reader)");
}

fn test_i18n() {
    let sys_loc = goose_ui::system_locale();
    let sys_lang = goose_ui::system_language();
    assert(sys_loc.len > 0 && sys_lang.len > 0);

    let tmp = win32::temp_dir();
    let sep = if tmp.len > 0 && (tmp[tmp.len - 1] == '\\' || tmp[tmp.len - 1] == '/') { "" } else { "\\" };
    let base_dir = str(tmp, sep, "goose_ui_i18n_test_", win32::GetCurrentProcessId());
    let locales_dir = str(base_dir, "\\locales");
    let en_path = str(locales_dir, "\\en.json");
    let fr_path = str(locales_dir, "\\fr.json");
    let bundle_path = str(base_dir, "\\bundle.json");
    let log_path = str(base_dir, "\\i18n_events.jsonl");
    assert(goose_ui::ensure_parent_dirs(str(locales_dir, "\\_")));

    var app = goose_ui::App { .. };
    assert(app.log_open(log_path, goose_ui::LogOptions {
        min_level: goose_ui::LogLevel.Debug,
        append: false,
        log_ui_events: true,
    }));

    // 1. Locale registration, BCP-47 normalization, and hierarchical fallback
    let idx_en = app.i18n_register_locale("EN", "English");
    let idx_ja = app.i18n_register_locale("ja", "日本語");
    let idx_ja_jp = app.i18n_register_locale("ja_jp", "日本語 (日本)");
    assert(idx_en == 0 && idx_ja == 1 && idx_ja_jp == 2);
    assert(app.locale_code(idx_ja_jp) == "ja-JP");
    assert(app.locale_name_at(idx_ja_jp) == "日本語 (日本)");
    assert(app.set_fallback_locale("en"));
    assert(app.fallback_locale() == "en");

    assert(app.i18n_add("en", "only.en", "English Fallback"));
    assert(app.i18n_add("ja", "shared.ja", "親日本語"));
    assert(app.i18n_add("ja-JP", "regional.jp", "地域設定"));
    assert(app.set_locale("ja-JP"));
    assert(app.locale() == "ja-JP");
    assert(app.tr("regional.jp") == "地域設定");
    assert(app.tr("shared.ja") == "親日本語");          // ja-JP -> ja parent fallback
    assert(app.tr("only.en") == "English Fallback"); // ja-JP -> ja -> en fallback
    assert(app.tr("missing.key") == "missing.key");
    assert(app.tr_or("missing.key", "Default") == "Default");
    assert(!app.has_tr("missing.key") && app.has_tr("shared.ja"));

    // 2. Flat & nested JSON, metadata, bundle JSON, external file & dir loading
    assert(app.i18n_load_json_str("en", """
        {
          "_locale_name": "English (US)",
          "win": { "title": "App EN" },
          "status": { "ready": "Ready" },
          "ui": {
            "hello": "Hello",
            "btn": "OK",
            "chk": "Accept",
            "tog": "Dark Mode",
            "grp": "Group",
            "ph": "Search...",
            "tip": "Tooltip EN",
            "tab1": "Tab One",
            "tab2": "Tab Two",
            "item_a": "Alpha",
            "item_b": "Beta",
            "sub_b": "Sub B"
          },
          "fmt": {
            "pos": "{0} + {1} = {2}",
            "named": "{user} launched {game} ({fps} fps, #{num}) {{literal}}"
          },
          "meta_num": 42,
          "meta_flag": true
        }
    """));
    assert(app.locale_name_at(idx_en) == "English (US)");
    assert(app.tr_for("en", "ui.hello") == "Hello");
    assert(app.tr_for("en", "meta_num") == "42");
    assert(app.tr_for("en", "meta_flag") == "true");

    assert(app.i18n_load_json_str("ja", """
        {
          "_meta": { "name": "日本語" },
          "win": { "title": "アプリ JP" },
          "status": { "ready": "準備完了" },
          "ui": {
            "hello": "こんにちは世界",
            "btn": "確定する",
            "chk": "同意する",
            "tog": "ダークモード",
            "grp": "グループ",
            "ph": "検索してください...",
            "tip": "ツールチップ JP",
            "tab1": "タブ1",
            "tab2": "タブ2番目",
            "item_a": "アルファ",
            "item_b": "ベータ",
            "sub_b": "サブB"
          },
          "fmt": {
            "named": "{game} を {user} が起動 (#{num}, {fps} fps) {{literal}}"
          }
        }
    """));

    assert(win32::write_file_bytes(bundle_path, """
        {
          "en": { "bundle": { "k": "From Bundle EN" } },
          "ja": { "bundle": { "k": "バンドル JP" } }
        }
    """));
    assert(app.i18n_load_bundle_json_file(bundle_path));
    assert(app.tr_for("ja", "bundle.k") == "バンドル JP");

    assert(win32::write_file_bytes(en_path, "{\"ui\":{\"hello\":\"Hello Override\"}}"));
    assert(win32::write_file_bytes(fr_path, "{\"_locale_name\":\"Français\",\"ui\":{\"hello\":\"Bonjour\"}}"));
    assert(app.i18n_load_dir(locales_dir) == 2);
    assert(app.has_locale("fr"));
    assert(app.tr_for("en", "ui.hello") == "Hello Override");
    assert(app.tr_for("fr", "ui.hello") == "Bonjour");
    assert(app.tr_for("fr", "ui.btn") == "OK"); // fallback to en

    // 3. Positional & named template formatting
    assert(app.set_locale("en"));
    assert(app.tr3("fmt.pos", "1", "2", "3") == "1 + 2 = 3");
    let fmt_en = app.tr_fmt("fmt.named") { f =>
        f.text("user", "Yu").text("game", "Goose").num("fps", 144.5, 1).int("num", 7);
    };
    assert(fmt_en == "Yu launched Goose (144.5 fps, #7) {literal}");

    assert(app.set_locale("ja"));
    let fmt_ja = app.tr_fmt("fmt.named") { f =>
        f.text("user", "Yu").text("game", "Goose").num("fps", 144.5, 1).int("num", 7);
    };
    assert(fmt_ja == "Goose を Yu が起動 (#7, 144.5 fps) {literal}");

    // 4. Live UI re-translation, layout recalculation, item compaction & detaching
    var win = app.create_headless_window("", 720, 480);
    app.set_tr_window_title(win, "win.title");
    app.set_tr_status_text(win, "status.ready");

    var w_lbl = goose_ui::WIDGET_NONE;
    var w_btn = goose_ui::WIDGET_NONE;
    var w_chk = goose_ui::WIDGET_NONE;
    var w_tog = goose_ui::WIDGET_NONE;
    var w_grp = goose_ui::WIDGET_NONE;
    var w_ed = goose_ui::WIDGET_NONE;
    var w_cb = goose_ui::WIDGET_NONE;
    var w_lv = goose_ui::WIDGET_NONE;
    var w_tabs = goose_ui::WIDGET_NONE;
    var w_manual = goose_ui::WIDGET_NONE;
    var w_temp = goose_ui::WIDGET_NONE;

    assert(app.set_locale("en"));
    app.ui(win) { u =>
        u.padding(12.0).spacing(8.0);
        u.tr_label("ui.hello").bind(w_lbl);
        u.tr_button("ui.btn").align(goose_ui::Align.Start).tr_tooltip("ui.tip").bind(w_btn);
        u.tr_checkbox("ui.chk", true).bind(w_chk);
        u.tr_toggle("ui.tog", false).bind(w_tog);
        u.tr_group_box("ui.grp") { g =>
            g.self_node().bind(w_grp);
            g.tr_line_edit("ui.ph").bind(w_ed);
            g.tr_label("ui.hello").bind(w_temp);
        };
        u.combo_box()
            .tr_item("ui.item_a")
            .tr_item("ui.item_b")
            .bind(w_cb);
        u.list_view(30.0)
            .tr_item("ui.item_a")
            .tr_item("ui.item_b", "ui.sub_b")
            .bind(w_lv);
        u.tabs() { t =>
            t.self_node().bind(w_tabs);
            t.tr_tab("ui.tab1") { _p => };
            t.tr_tab("ui.tab2") { _p => };
        };
        u.tr_label("ui.hello").bind(w_manual);
    };

    app.update_layout(win, true);
    let btn_w_en = app.widget_rect(w_btn).w;
    assert(app.str_view(app.windows[win.index].title) == "App EN");
    assert(app.text(app.windows[win.index].status_bar) == "Ready");
    assert(app.text(w_lbl) == "Hello Override");
    assert(app.text(w_btn) == "OK");
    assert(app.str_view(app.widgets[w_btn.index].tooltip) == "Tooltip EN");
    assert(app.str_view(app.widgets[w_ed.index].placeholder) == "Search...");
    assert(app.item_text(w_cb, 0) == "Alpha" && app.item_text(w_cb, 1) == "Beta");
    assert(app.item_text(w_lv, 1) == "Beta" && app.item_subtext(w_lv, 1) == "Sub B");
    assert(app.item_text(w_tabs, 0) == "Tab One" && app.item_text(w_tabs, 1) == "Tab Two");

    // Remove item 0 from ListView (compacts/shifts index 1 -> 0) and manually overwrite w_manual
    assert(app.remove_item(w_lv, 0));
    app.set_text(w_manual, "Custom Manual Text");
    app.destroy_widget(w_temp);

    // Drain prior signals before switching locale
    var sig = goose_ui::Signal.None;
    while app.next_signal(sig) {}

    // Switch to Japanese -> all remaining bound widgets auto-retranslate & layout grows
    assert(app.set_locale("ja"));
    app.update_layout(win, true);
    let btn_w_ja = app.widget_rect(w_btn).w;
    assert(btn_w_ja > btn_w_en);
    assert(app.str_view(app.windows[win.index].title) == "アプリ JP");
    assert(app.text(app.windows[win.index].status_bar) == "準備完了");
    assert(app.text(w_lbl) == "こんにちは世界");
    assert(app.text(w_btn) == "確定する");
    assert(app.text(w_chk) == "同意する");
    assert(app.text(w_tog) == "ダークモード");
    assert(app.text(w_grp) == "グループ");
    assert(app.str_view(app.widgets[w_ed.index].placeholder) == "検索してください...");
    assert(app.str_view(app.widgets[w_btn.index].tooltip) == "ツールチップ JP");
    assert(app.item_text(w_cb, 0) == "アルファ" && app.item_text(w_cb, 1) == "ベータ");
    assert(app.item_text(w_lv, 0) == "ベータ" && app.item_subtext(w_lv, 0) == "サブB");
    assert(app.item_text(w_tabs, 0) == "タブ1" && app.item_text(w_tabs, 1) == "タブ2番目");
    assert(app.text(w_manual) == "Custom Manual Text"); // Detached by manual set_text

    var saw_locale_sig = false;
    while app.next_signal(sig) {
        match sig {
            LocaleChanged lc => {
                if lc.locale_index == idx_ja { saw_locale_sig = true; }
            },
            _ => {},
        }
    }
    assert(saw_locale_sig);

    // 5. Standalone Translator test
    var tr = goose_ui::Translator { .. };
    assert(tr.load_dir(locales_dir) == 2);
    assert(tr.set_locale("fr"));
    assert(tr.tr("ui.hello") == "Bonjour");
    assert(tr.set_system_locale("en"));
    assert(tr.locale().len > 0);

    app.destroy_all();

    var saw_logged_locale = false;
    let l_cnt, l_ok = goose_ui::each_json_log_entry(log_path) { e =>
        if e.target == "goose_ui.signal" && e.msg == "LocaleChanged" {
            var doc: json::Node[>..] = [];
            var dec: u8[>..] = [];
            let rn, _er = json::parse(e.raw_json, doc, dec);
            if rn != null {
                let flds = json::member(rn, "fields");
                let lc, lc_ok = json::as_string(json::member(flds, "locale"));
                if lc_ok && lc == "ja" { saw_logged_locale = true; }
            }
        }
    };
    assert(l_ok && l_cnt >= 1 && saw_logged_locale);

    win32::delete_file(en_path);
    win32::delete_file(fr_path);
    win32::delete_file(bundle_path);
    win32::delete_file(log_path);
    win32::remove_directory(locales_dir);
    win32::remove_directory(base_dir);

    print("[OK] multi-language i18n (JSON/bundle/dir, fallback, interpolation, live re-translation, Translator)");
}

fn is_win_pos_default(p: goose_ui::WindowPosition) -> bool {
    return match p { SystemDefault => true, _ => false };
}

fn is_win_pos_center_primary(p: goose_ui::WindowPosition) -> bool {
    return match p { CenterPrimary => true, _ => false };
}

fn is_win_pos_manual(p: goose_ui::WindowPosition) -> bool {
    return match p { Manual => true, _ => false };
}

fn test_window_positioning() {
    // 1. Centering math & clamping
    let wr_std = win32::Rect { left: 0, top: 0, right: 1920, bottom: 1040 };
    let cx1, cy1 = goose_ui::compute_centered_pos(wr_std, 800, 600);
    assert(cx1 == 560 && cy1 == 220);

    let wr_neg = win32::Rect { left: -1920, top: 0, right: 0, bottom: 1040 };
    let cx2, cy2 = goose_ui::compute_centered_pos(wr_neg, 800, 600);
    assert(cx2 == -1360 && cy2 == 220);

    let wr_off = win32::Rect { left: 10, top: 40, right: 1930, bottom: 1080 };
    let cx3, cy3 = goose_ui::compute_centered_pos(wr_off, 2500, 1400);
    assert(cx3 == 10 && cy3 == 40);

    // 2. Headless startup positioning policies & runtime helpers
    var app = goose_ui::App { .. };
    assert(is_win_pos_default(app.window_start_position()));

    app.set_window_start_position(goose_ui::WindowPosition.CenterPrimary);
    assert(is_win_pos_center_primary(app.window_start_position()));
    let w_hl = app.create_headless_window("CenterHL", 640, 400);
    let primary_work = goose_ui::primary_work_area();
    assert(primary_work.width() > 0 && primary_work.height() > 0);
    let exp_hx, exp_hy = goose_ui::compute_centered_pos(primary_work, 640, 400);
    let hlx, hly = app.window_position(w_hl);
    assert(hlx == exp_hx && hly == exp_hy);

    app.set_window_start_position_manual(120, 80);
    assert(is_win_pos_manual(app.window_start_position()));
    let w_man = app.create_headless_window("ManHL", 400, 300);
    let mx, my = app.window_position(w_man);
    assert(mx == 120 && my == 80);

    app.center_window(w_man);
    let exp_mx, exp_my = goose_ui::compute_centered_pos(primary_work, 400, 300);
    let cmx, cmy = app.window_position(w_man);
    assert(cmx == exp_mx && cmy == exp_my);

    app.set_window_position(w_man, 33, 44);
    let sx, sy = app.window_position(w_man);
    assert(sx == 33 && sy == 44);

    app.set_center_on_primary_display(true);
    assert(is_win_pos_center_primary(app.window_start_position()));
    app.set_center_on_primary_display(false);
    assert(is_win_pos_default(app.window_start_position()));
    app.destroy_all();

    // 3. Real Win32 (Software, hidden) primary-display centering & runtime move/center
    var app2 = goose_ui::App { .. };
    app2.init(true, goose_ui::RenderBackend.Software);
    app2.set_window_start_position(goose_ui::WindowPosition.CenterPrimary);
    let w_real = app2.create_window("CenterReal", 520, 360);
    assert(app2.valid_window(w_real));
    let wrc = app2.hwnd(w_real).window_rect();
    let ex, ey = goose_ui::compute_centered_pos(primary_work, wrc.width(), wrc.height());
    let rx, ry = app2.window_position(w_real);
    assert(rx >= ex - 2 && rx <= ex + 2 && ry >= ey - 2 && ry <= ey + 2);

    let target_x = primary_work.left + 40;
    let target_y = primary_work.top + 40;
    app2.set_window_position(w_real, target_x, target_y);
    let mx2, my2 = app2.window_position(w_real);
    assert(mx2 >= target_x - 2 && mx2 <= target_x + 2 && my2 >= target_y - 2 && my2 <= target_y + 2);

    app2.center_window(w_real);
    let rx2, ry2 = app2.window_position(w_real);
    assert(rx2 >= ex - 2 && rx2 <= ex + 2 && ry2 >= ey - 2 && ry2 <= ey + 2);

    app2.destroy_all();
    print("[OK] window startup positioning (CenterPrimary, Manual, compute_centered_pos & Win32 move/center)");
}

fn test_regressions_text_scroll_and_wrap() {
    // 1. Headless LineEdit horizontal scroll & nested ListView inside ScrollArea wheel fallthrough
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("TextScrollWrapTest", 360, 260);
    let root = app.root(win);
    app.set_padding(root, 12.0);
    app.set_spacing(root, 8.0);

    let sample = "[サンプル] 起動テスト用。右ペインまたは一覧から編集・削除できます。";
    let ed = app.add_line_edit(root, "Memo", sample);
    app.set_fixed_width(ed, 240.0);

    let sc = app.add_scroll_area(root);
    app.set_fixed_height(sc, 140.0);
    let lv = app.add_list_view(sc, 32.0);
    app.set_fixed_height(lv, 110.0);
    app.add_item(lv, "Only One Item");
    let _tall_pad = app.add_label(sc, "Bottom spacer");
    app.set_fixed_height(_tall_pad, 140.0);

    app.update_layout(win, true);

    // Focus end of long CJK text -> horizontally scrolls right
    app.set_focus(win, ed);
    assert(app.widgets[ed.index].caret == sample.len);
    assert(app.widgets[ed.index].text_scroll_byte > 0);

    // Home -> scrolls back to 0; End -> scrolls back to scrolled end
    app.inject_key(win, 0x24, 0); // VK_HOME
    assert(app.widgets[ed.index].caret == 0 && app.widgets[ed.index].text_scroll_byte == 0);
    app.inject_key(win, 0x23, 0); // VK_END
    let scrolled_sb = app.widgets[ed.index].text_scroll_byte;
    assert(app.widgets[ed.index].caret == sample.len && scrolled_sb > 0);

    // Click inside scrolled LineEdit hits a valid UTF-8 boundary >= scrolled_sb
    let red = app.widget_rect(ed);
    app.inject_click(win, red.x + 28.0, red.y + red.h * 0.5);
    let c_pos = app.widgets[ed.index].caret;
    assert(c_pos >= app.widgets[ed.index].text_scroll_byte);
    assert(c_pos == goose_ui::utf8_snap_boundary(sample, c_pos));

    // Wheel over 1-item ListView (scroll_max_y == 0) falls through to outer ScrollArea
    let rlv = app.widget_rect(lv);
    assert(app.widgets[lv.index].scroll_max_y == 0.0);
    assert(app.widgets[sc.index].scroll_max_y > 0.0);
    app.inject_mouse_wheel(win, rlv.x + 20.0, rlv.y + 20.0, -120);
    assert(app.widgets[sc.index].scroll_y > 0.0);

    app.destroy_all();

    // 2. Real Win32 Direct2D (hidden) DirectWrite font metrics, wrapped Label, scrolled LineEdit & hardware-clipped ScrollArea/ListView
    var app2 = goose_ui::App { .. };
    app2.init(true, goose_ui::RenderBackend.Direct2D);
    let w2 = app2.create_window("D2DTextAndClip", 520, 340);
    assert(app2.valid_window(w2));
    assert(app2.windows[w2.index].metric_dc.raw == 0);

    let measured_w = goose_ui::measure_win_text_width(app2, w2.index, "[サンプル] 起動テスト用。右ペインまたは一", goose_ui::FontRole.Body);
    assert(measured_w >= 215.0 && measured_w <= 245.0);
    let measured_mono_w = goose_ui::measure_win_text_width(
        app2,
        w2.index,
        "{\"ts\":\"2026-11-24T20:19:39.708\",\"seq\":2,\"level\":\"info\"}",
        goose_ui::FontRole.Mono
    );
    assert(measured_mono_w >= 395.0 && measured_mono_w <= 420.0);
    let trail_w = goose_ui::measure_win_text_width(app2, w2.index, "abc ", goose_ui::FontRole.Body);
    let plain_w = goose_ui::measure_win_text_width(app2, w2.index, "abc", goose_ui::FontRole.Body);
    assert(trail_w > plain_w);

    var w_ed = goose_ui::WIDGET_NONE;
    var w_lbl = goose_ui::WIDGET_NONE;
    var w_sc2 = goose_ui::WIDGET_NONE;
    app2.ui(w2) { u =>
        u.padding(12.0).spacing(8.0);
        u.line_edit("Memo", sample).width(240.0).bind(w_ed);
        u.label("{\"ts\":\"2026-11-24T20:19:39.708\",\"seq\":2,\"level\":\"info\",\"target\":\"app\",\"msg\":\"YuLauncher started\",\"pid\":7496,\"tid\":50844,\"fields\":{\"version\":\"0.1.0-alpha\",\"backend\":\"direct2d\",\"locale\":\"ja\"}}")
            .mono().wrap().text_align(goose_ui::Align.Start, goose_ui::Align.Start).height(76.0).bind(w_lbl);
        u.scroll_area(8.0, 8.0) { sc2 =>
            sc2.stretch(1.0).bind(w_sc2);
            sc2.frame(goose_ui::LayoutKind.VBox, 6.0, 8.0) { c1 =>
                c1.label("Top Card");
                c1.spacer().height(90.0);
            };
            sc2.list_view(32.0).min_size(120.0, 180.0).item("Note 1").item("Note 2");
        };
    };

    app2.windows[w2.index].visible = true;
    app2.update_layout(w2, true);
    app2.set_focus(w2, w_ed);
    assert(app2.widgets[w_ed.index].text_scroll_byte > 0);
    assert(app2.widgets[w_lbl.index].word_wrap);
    app2.render_window(w2);

    assert(app2.widgets[w_sc2.index].scroll_max_y > 0.0);
    let partial_sy = if app2.widgets[w_sc2.index].scroll_max_y > 60.0 { 60.0 } else { app2.widgets[w_sc2.index].scroll_max_y * 0.5 };
    app2.widgets[w_sc2.index].scroll_y = partial_sy;
    app2.update_layout(w2, true);
    app2.render_window(w2);

    app2.destroy_all();
    print("[OK] LineEdit horizontal scroll, DirectWrite font metrics, wrapped Label & D2D hardware clipping");
}

fn test_viewport_resize_and_stretch() {
    // 1. Headless multi-column HBox vertical container stretch + compact VBox centering + ScrollArea max_size
    {
        var app = goose_ui::App { .. };
        let win = app.create_headless_window("ResizeStretchHL", 800, 600);
        let _sb = app.set_status_bar(win, "Ready");

        var exp_col = goose_ui::WIDGET_NONE;
        var exp_canvas = goose_ui::WIDGET_NONE;
        var compact_col = goose_ui::WIDGET_NONE;
        var capped_row = goose_ui::WIDGET_NONE;
        app.ui(win) { u =>
            u.padding(0.0).spacing(0.0);
            u.hbox(0.0, 0.0) { row =>
                row.stretch(1.0);
                row.vbox(6.0, 8.0) { c0 =>
                    c0.width(240.0).bind(exp_col);
                    c0.label("Header");
                    c0.canvas(120.0, 80.0).stretch(1.0).bind(exp_canvas);
                };
                row.vbox(4.0, 8.0) { c1 =>
                    c1.width(120.0).bind(compact_col);
                    c1.label("Line 1");
                    c1.label("Line 2");
                };
                row.scroll_area(8.0, 12.0) { sc =>
                    sc.stretch(1.0);
                    sc.hbox(8.0) { hr =>
                        hr.max_size(400.0, 34.0).bind(capped_row);
                        hr.button("A").height(34.0).stretch(1.0);
                        hr.button("B").height(34.0).stretch(1.0);
                    };
                };
            };
        };

        let widths: i32[3] = [800, 1400, 640];
        let heights: i32[3] = [600, 900, 480];
        for i in 0..3 {
            app.windows[win.index].width = widths[i];
            app.windows[win.index].height = heights[i];
            app.update_layout(win, true);

            let exp_h = heights[i] - 26.0;
            let rexp = app.widget_rect(exp_col);
            let rcomp = app.widget_rect(compact_col);
            let rcap = app.widget_rect(capped_row);
            assert(approx(rexp.y, 0.0) && approx(rexp.h, exp_h));
            assert(app.widget_rect(exp_canvas).h > exp_h * 0.7);
            // Fixed-label VBox without expanding descendants stays compact & vertically centered
            assert(rcomp.h < exp_h * 0.5 && rcomp.y > 40.0);
            // ScrollArea child honors max_size.w when wider and shrinks cleanly when narrower
            let sc_inner_w = widths[i] - 240.0 - 120.0 - 24.0 - 10.0;
            let exp_cap_w = if sc_inner_w < 400.0 { sc_inner_w } else { 400.0 };
            assert(approx(rcap.w, exp_cap_w, 1.5));
        }

        app.destroy_all();
    }

    // 2. Real Win32 Direct2D window resize -> syncs Window, D2D surface pixel_size, root & StatusBar
    {
        var app = goose_ui::App { .. };
        app.init(true, goose_ui::RenderBackend.Direct2D);
        let win = app.create_window("D2DResizeTest", 480, 320);
        assert(app.valid_window(win));
        let root = app.root(win);
        app.set_status_bar(win, "D2D Resize");
        app.ui(win) { u =>
            u.padding(8.0);
            u.canvas(100.0, 60.0).stretch(1.0);
        };
        app.windows[win.index].visible = true;
        app.render_window(win);

        let wrc = app.hwnd(win).window_rect();
        assert(app.hwnd(win).move(wrc.left, wrc.top, wrc.width() + 200, wrc.height() + 140, false));
        app.render_window(win);

        let rc1 = app.hwnd(win).client_rect();
        assert(app.windows[win.index].width == rc1.width() && app.windows[win.index].height == rc1.height());
        let pw, ph = app.windows[win.index].d2d.pixel_size();
        assert(pw == rc1.width() && ph == rc1.height());
        let r_root = app.widget_rect(root);
        assert(approx(r_root.w, rc1.width()) && approx(r_root.h, rc1.height() - 26.0));
        app.destroy_all();
    }

    // 3. Real Win32 OpenGL window resize -> expanded viewport renders to right/bottom edge
    {
        var app = goose_ui::App { .. };
        app.init(true, goose_ui::RenderBackend.OpenGL);
        let win = app.create_window("GLResizeTest", 360, 240);
        assert(app.valid_window(win));
        var cv = goose_ui::WIDGET_NONE;
        app.ui(win) { u =>
            u.padding(0.0);
            u.canvas(100.0, 100.0).stretch(1.0).bind(cv);
        };
        app.windows[win.index].visible = true;
        app.render_window(win);

        let wrc = app.hwnd(win).window_rect();
        assert(app.hwnd(win).move(wrc.left, wrc.top, wrc.width() + 240, wrc.height() + 180, false));
        let rc1 = app.hwnd(win).client_rect();
        var px: u32 = 0;
        var read_ok = false;
        app.render_window_with(win) { cid, p =>
            if goose_ui::eq(cid, cv) {
                p.fill_rect(p.width - 40.0, p.height - 40.0, 32.0, 32.0, goose_ui::rgb(34, 211, 238));
                read_ok = p.gl2d.readback_pixel(rc1.width() - 24, rc1.height() - 24, px);
            }
        };
        assert(read_ok);
        let rch = px & 0xFF;
        let gch = (px >> 8) & 0xFF;
        let bch = (px >> 16) & 0xFF;
        assert(rch <= 45 && gch >= 200 && bch >= 225);
        app.destroy_all();
    }

    // 4. Real Win32 Software GDI resize + set_window_min_size enforcement
    {
        var app = goose_ui::App { .. };
        app.init(true, goose_ui::RenderBackend.Software);
        let win = app.create_window("SWMinSizeTest", 480, 320);
        assert(app.valid_window(win));
        app.set_window_min_size(win, 360, 260);
        let wrc = app.hwnd(win).window_rect();
        assert(app.hwnd(win).move(wrc.left, wrc.top, 160, 120, false));
        app.windows[win.index].visible = true;
        app.render_window(win);
        assert(app.windows[win.index].width >= 360 && app.windows[win.index].height >= 260);
        app.destroy_all();
    }

    print("[OK] viewport resize stretch (HBox containers, ScrollArea max_size, D2D/GL/SW & min_size)");
}

fn verify_webview_backend_smoke(
    backend: goose_ui::RenderBackend,
    win_title: const u8[:],
    udf_dir: const u8[:],
    run_eval: bool
) {
    var app = goose_ui::App { .. };
    app.init(true, backend);
    app.set_webview_user_data_dir(udf_dir);

    let win = app.create_window(win_title, 640, 420);
    assert(app.valid_window(win));

    var wv = goose_ui::WIDGET_NONE;
    app.ui(win) { u =>
        u.padding(8.0);
        u.webview_html("<!doctype html><html><head><title>LiveWV</title></head><body>Hello</body></html>", 300.0, 200.0)
         .stretch(1.0)
         .bind(wv);
    };

    app.windows[win.index].visible = true;
    app.running = true;
    app.update_layout(win, true);
    app.render_window(win);

    var got_ready = false;
    var sent_eval = false;
    var got_eval = !run_eval;
    var eval_req: u64 = 0;

    let deadline = win32::tick_count_ms() + 12000;
    while win32::tick_count_ms() < deadline && !(got_ready && got_eval) {
        app.pump_events(false);
        var sig = goose_ui::Signal.None;
        while app.next_signal(sig) {
            match sig {
                WebViewInitFailed _s => {
                    assert(false);
                },
                WebViewReady s => {
                    if goose_ui::eq(s.widget, wv) {
                        got_ready = true;
                        assert(app.webview_is_ready(wv));
                        if run_eval && !sent_eval {
                            sent_eval = true;
                            eval_req = app.webview_eval_js(wv, "6 * 7");
                            assert(eval_req != 0);
                        }
                    }
                },
                WebViewNavigationCompleted s => {
                    if goose_ui::eq(s.widget, wv) && run_eval && !sent_eval {
                        sent_eval = true;
                        eval_req = app.webview_eval_js(wv, "6 * 7");
                        assert(eval_req != 0);
                    }
                },
                WebViewScriptResult s => {
                    if goose_ui::eq(s.widget, wv) && s.request_id == eval_req {
                        assert(s.ok);
                        assert(app.webview_payload(s.payload) == "42");
                        got_eval = true;
                    }
                },
                _ => {},
            }
        }
        if !(got_ready && got_eval) {
            win32::Sleep(10);
        }
    }
    assert(got_ready && got_eval);

    if run_eval {
        assert(!app.webview_is_muted(wv));
        assert(app.webview_set_muted(wv, true));
        assert(app.webview_is_muted(wv));
        assert(app.webview_set_muted(wv, false));
        assert(!app.webview_is_muted(wv));
        let _playing = app.webview_is_playing_audio(wv);
    }

    app.toggle_theme();
    app.windows[win.index].width = 760;
    app.windows[win.index].height = 500;
    app.update_layout(win, true);
    app.render_window(win);

    app.destroy_all();
}

fn test_webview_headless() {
    var app = goose_ui::App { .. };
    let win = app.create_headless_window("WebViewHeadless", 900, 600);
    let _sb = app.set_status_bar(win, "Ready");

    var w_tabs = goose_ui::WIDGET_NONE;
    var w_stack = goose_ui::WIDGET_NONE;
    var w_wrap = goose_ui::WIDGET_NONE;
    var w_sc = goose_ui::WIDGET_NONE;
    var w_wv = goose_ui::WIDGET_NONE;

    app.ui(win) { u =>
        u.padding(8.0).spacing(6.0);
        u.tabs() { t =>
            t.bind(w_tabs).stretch(1.0);
            t.tab("Home") { p0 =>
                p0.label("Home tab");
            };
            t.tab("Web") { p1 =>
                p1.stack(0.0) { st =>
                    st.bind(w_stack).stretch(1.0);
                    st.vbox(4.0, 4.0) { s0 =>
                        s0.label("Stack placeholder");
                    };
                    st.vbox(0.0, 0.0) { s1 =>
                        s1.bind(w_wrap);
                        s1.scroll_area(0.0, 0.0) { sc =>
                            sc.bind(w_sc).stretch(1.0);
                            sc.spacer().height(180.0);
                            sc.webview("https://example.org", 300.0, 220.0)
                              .init_script("window.x=1;")
                              .devtools(false)
                              .context_menu(false)
                              .status_bar(true)
                              .zoom_control(false)
                              .accelerator_keys(false)
                              .zoom(1.5)
                              .new_window_policy(goose_ui::WebViewNewWindowPolicy.NavigateSelf)
                              .color_scheme(goose_ui::WebViewColorScheme.Auto)
                              .user_agent("GooseTest/1.0")
                              .virtual_host("demo.local", "C:\\tmp", goose_ui::WebViewHostAccess.Allow)
                              .bind(w_wv);
                        };
                    };
                };
            };
        };
    };

    app.windows[win.index].visible = true;
    app.update_layout(win, true);

    // Inactive TabWidget hides WebView
    assert(!app.webview_effective_visible(w_wv));

    // Active TabWidget + inactive Stack hides WebView
    app.set_current_tab(w_tabs, 1);
    app.update_layout(win, true);
    assert(!app.webview_effective_visible(w_wv));

    // Active TabWidget + active Stack reveals WebView
    app.set_selected_index(w_stack, 1);
    app.update_layout(win, true);
    assert(app.webview_effective_visible(w_wv));
    let r_wv = app.widget_rect(w_wv);
    assert(r_wv.w >= 300.0 && r_wv.h >= 220.0);

    // ScrollArea viewport clipping constrains WebView clipped_rect
    app.widgets[w_sc.index].scroll_y = 200.0;
    app.update_layout(win, true);
    let r_clip = app.webview_clipped_rect(w_wv);
    let r_sc = app.widget_rect(w_sc);
    assert(r_clip.w > 0.0 && r_clip.h > 0.0 && r_clip.y >= r_sc.y);

    // Explicit ancestor hide/show toggles WebView effective visibility
    app.set_visible(w_wrap, false);
    app.update_layout(win, true);
    assert(!app.webview_effective_visible(w_wv));
    app.set_visible(w_wrap, true);
    app.update_layout(win, true);
    assert(app.webview_effective_visible(w_wv));

    // Theme switch & drain before signal injection
    app.toggle_theme();
    var sig = goose_ui::Signal.None;
    while app.next_signal(sig) {}

    app.inject_webview_ready(w_wv);
    app.inject_webview_navigation(w_wv, "https://goose.local/app", true, 0);
    app.inject_webview_title(w_wv, "Goose WebView");
    app.inject_webview_message(w_wv, "{\"n\":1}", true, "https://goose.local/");
    app.inject_webview_message(w_wv, "plain-two", false, "https://other.local/");
    app.inject_webview_script_result(w_wv, 99, "\"ok\"", true);

    assert(app.webview_is_ready(w_wv));
    assert(app.webview_url(w_wv) == "https://goose.local/app");
    assert(app.webview_title(w_wv) == "Goose WebView");
    assert(app.webview_last_message(w_wv) == "plain-two");
    assert(app.webview_last_script_result(w_wv) == "\"ok\"");
    assert(app.webview_zoom(w_wv) > 1.49 && app.webview_zoom(w_wv) < 1.51);
    assert(!app.webview_is_muted(w_wv));
    assert(app.webview_set_muted(w_wv, true));
    assert(app.webview_is_muted(w_wv));
    assert(!app.webview_is_playing_audio(w_wv));
    assert(app.webview_set_muted(w_wv, false));
    assert(!app.webview_is_muted(w_wv));

    var saw_ready = false;
    var saw_nav_done = false;
    var saw_title = false;
    var msg_count: i32 = 0;
    var saw_res = false;
    while app.next_signal(sig) {
        match sig {
            WebViewReady s => { if goose_ui::eq(s.widget, w_wv) { saw_ready = true; } },
            WebViewNavigationCompleted s => { if goose_ui::eq(s.widget, w_wv) && s.success { saw_nav_done = true; } },
            WebViewTitleChanged s => { if goose_ui::eq(s.widget, w_wv) { saw_title = true; } },
            WebViewMessageReceived s => {
                if msg_count == 0 {
                    assert(s.is_json);
                    assert(app.webview_payload(s.payload) == "{\"n\":1}");
                    assert(app.webview_payload_source(s.payload) == "https://goose.local/");
                } else if msg_count == 1 {
                    assert(!s.is_json);
                    assert(app.webview_payload(s.payload) == "plain-two");
                    assert(app.webview_payload_source(s.payload) == "https://other.local/");
                }
                msg_count += 1;
            },
            WebViewScriptResult s => {
                assert(s.ok && s.request_id == 99);
                assert(app.webview_payload(s.payload) == "\"ok\"");
                saw_res = true;
            },
            _ => {},
        }
    }
    assert(saw_ready && saw_nav_done && saw_title && msg_count == 2 && saw_res);
    assert(app.webview_payloads.len == 0 && app.webview_msg_pool.len == 0);

    // JSON logging of WebView signals
    let tmp = win32::temp_dir();
    let sep = if tmp.len > 0 && (tmp[tmp.len - 1] == '\\' || tmp[tmp.len - 1] == '/') { "" } else { "\\" };
    let log_path = str(tmp, sep, "goose_ui_wv_log_", win32::GetCurrentProcessId(), ".jsonl");
    assert(app.log_open(log_path, goose_ui::LogOptions {
        min_level: goose_ui::LogLevel.Debug,
        append: false,
        log_ui_events: true,
    }));
    app.log_set_stderr(false);
    app.inject_webview_message(w_wv, "logged-msg", false, "https://log.local/");
    app.inject_webview_script_result(w_wv, 123, "42", true);
    app.log_flush();
    app.log_close();

    var saw_log_msg = false;
    var saw_log_res = false;
    let lcnt, lok = goose_ui::each_json_log_entry(log_path) { e =>
        if e.target == "goose_ui.signal" && e.msg == "WebViewMessageReceived" {
            var doc: json::Node[>..] = [];
            var dec: u8[>..] = [];
            let rn, _er = json::parse(e.raw_json, doc, dec);
            let flds = json::member(rn, "fields");
            let p, pok = json::as_string(json::member(flds, "payload"));
            let src, sok = json::as_string(json::member(flds, "source"));
            if pok && sok && p == "logged-msg" && src == "https://log.local/" { saw_log_msg = true; }
        } else if e.target == "goose_ui.signal" && e.msg == "WebViewScriptResult" {
            var doc: json::Node[>..] = [];
            var dec: u8[>..] = [];
            let rn, _er = json::parse(e.raw_json, doc, dec);
            let flds = json::member(rn, "fields");
            let req, rok = json::as_i64(json::member(flds, "request_id"));
            let res, resok = json::as_string(json::member(flds, "result"));
            if rok && resok && req == 123 && res == "42" { saw_log_res = true; }
        }
    };
    assert(lok && lcnt >= 2 && saw_log_msg && saw_log_res);
    win32::delete_file(log_path);

    // Destroying widget reclaims WebView slot
    app.destroy_widget(w_wv);
    assert(!app.valid_widget(w_wv));
    for i in app.webviews.len {
        assert(!app.webviews[i].alive);
    }

    app.destroy_all();
    print("[OK] WebView headless layout/visibility/clipping, burst signals, JSON logging & cleanup");
}

fn test_webview_live_smoke() {
    if !goose_ui::webview_is_available() {
        print("[SKIP] WebView2 Runtime not installed on this machine");
        return;
    }
    let tmp = win32::temp_dir();
    let sep = if tmp.len > 0 && (tmp[tmp.len - 1] == '\\' || tmp[tmp.len - 1] == '/') { "" } else { "\\" };
    let udf_dir = str(tmp, sep, "goose_ui_wv_test_udf");

    verify_webview_backend_smoke(goose_ui::RenderBackend.Software, "WV Software", udf_dir, true);
    verify_webview_backend_smoke(goose_ui::RenderBackend.Direct2D, "WV Direct2D", udf_dir, false);
    verify_webview_backend_smoke(goose_ui::RenderBackend.OpenGL, "WV OpenGL", udf_dir, false);
    print("[OK] WebView2 live smoke across Software, Direct2D & OpenGL (eval_js=42)");
}

fn test_text_fit_api() {
    // 1. Headless text measurement, fit_text, i18n re-fit, clamping, and fit_to_text_now
    {
        var app = goose_ui::App { .. };
        assert(app.i18n_load_json_str("en", "{\"k\":{\"mute\":\"Mute\",\"muted\":\"Muted\"}}"));
        assert(app.i18n_load_json_str("ja", "{\"k\":{\"mute\":\"ミュート\",\"muted\":\"ミュート中\"}}"));
        assert(app.set_locale("en"));

        let win = app.create_headless_window("FitTextHL", 640, 320);
        let sz_en = app.measure_text(win, "DevTools", goose_ui::FontRole.Caption);
        let sz_jp = app.measure_text(win, "ミュート中", goose_ui::FontRole.Caption);
        assert(sz_en.w > 0.0 && sz_en.h > 0.0);
        assert(sz_jp.w > 0.0 && sz_jp.h > 0.0);

        var b_short = goose_ui::WIDGET_NONE;
        var b_tr = goose_ui::WIDGET_NONE;
        var b_clamp = goose_ui::WIDGET_NONE;
        var b_now = goose_ui::WIDGET_NONE;
        app.ui(win) { u =>
            u.hbox(6.0, 8.0) { row =>
                row.button("OK").ghost().caption().height(26.0).fit_text(8.0).bind(b_short);
                row.tr_button("k.mute").ghost().caption().height(26.0).fit_text(8.0).bind(b_tr);
                row.button("10%").ghost().caption().height(26.0).fit_text_clamped(6.0, 42.0, 90.0).bind(b_clamp);
                row.button("External").ghost().caption().height(26.0).bind(b_now);
            };
        };

        app.update_layout(win, true);
        let r_short0 = app.widget_rect(b_short);
        assert(r_short0.w < 72.0 && approx(r_short0.h, 26.0));
        assert(r_short0.w >= app.measure_widget_text(b_short).w + 16.0);

        // Growing text expands fit_text button cleanly
        app.set_text(b_short, "DevTools");
        app.update_layout(win, true);
        let r_short1 = app.widget_rect(b_short);
        assert(r_short1.w > r_short0.w);
        assert(r_short1.w >= app.measure_widget_text(b_short).w + 16.0);

        // Locale switch automatically re-fits translated text width
        let r_tr_en = app.widget_rect(b_tr);
        assert(r_tr_en.w >= app.measure_widget_text(b_tr).w + 16.0);
        assert(app.set_locale("ja"));
        app.update_layout(win, true);
        let r_tr_jp = app.widget_rect(b_tr);
        assert(app.text(b_tr) == "ミュート");
        assert(r_tr_jp.w >= app.measure_widget_text(b_tr).w + 16.0);

        // Clamped min_w and max_w bounds
        assert(approx(app.widget_rect(b_clamp).w, 42.0));
        app.set_text(b_clamp, "Very Long Clamped Label For Max Width Check");
        app.update_layout(win, true);
        assert(approx(app.widget_rect(b_clamp).w, 90.0));

        // Imperative fit_to_text_now applies fixed width from measured text
        let applied = app.fit_to_text_now(b_now, 8.0, 4.0, false);
        assert(applied.w >= app.measure_widget_text(b_now).w + 16.0);
        assert(approx(app.widgets[b_now.index].fixed_w, applied.w));

        app.destroy_all();
    }

    // 2. Live Direct2D & Software real metric text-fit verification
    {
        var app_d2d = goose_ui::App { .. };
        app_d2d.init(true, goose_ui::RenderBackend.Direct2D);
        let wd = app_d2d.create_window("FitTextD2D", 520, 200);
        assert(app_d2d.valid_window(wd));
        var bd = goose_ui::WIDGET_NONE;
        var b_ok = goose_ui::WIDGET_NONE;
        app_d2d.ui(wd) { u =>
            u.hbox(6.0, 8.0) { r =>
                r.button("OK").ghost().caption().height(26.0).fit_text(8.0).bind(b_ok);
                r.button("DevTools").ghost().caption().height(26.0).fit_text(8.0).bind(bd);
            };
        };
        app_d2d.update_layout(wd, true);
        assert(app_d2d.widget_rect(b_ok).w < 72.0);
        assert(app_d2d.widget_rect(bd).w >= app_d2d.measure_widget_text(bd).w + 16.0);
        assert(app_d2d.measure_text(wd, "ミュート中", goose_ui::FontRole.Caption).w > 0.0);
        app_d2d.destroy_all();

        var app_sw = goose_ui::App { .. };
        app_sw.init(true, goose_ui::RenderBackend.Software);
        let ws = app_sw.create_window("FitTextSW", 520, 200);
        assert(app_sw.valid_window(ws));
        var bs = goose_ui::WIDGET_NONE;
        app_sw.ui(ws) { u =>
            u.hbox(6.0, 8.0) { r =>
                r.button("DevTools").ghost().caption().height(26.0).fit_text(8.0).bind(bs);
            };
        };
        app_sw.update_layout(ws, true);
        assert(app_sw.widget_rect(bs).w >= app_sw.measure_widget_text(bs).w + 16.0);
        app_sw.destroy_all();
    }

    print("[OK] text measurement & fit_text / fit_to_text_now auto-sizing API (headless, D2D & Software)");
}

fn main() {
    test_tree_and_handles();
    test_layouts();
    test_widgets_and_signals();
    test_combo_list_tabs_focus();
    test_real_win32_d2d_smoke();
    test_software_gdi_and_str_pool();
    test_opengl_backend_render();
    test_dsl_and_win32_anchors();
    test_regressions_canvas_and_visibility();
    test_regressions_inputs_and_signals();
    test_regressions_layout_and_pools();
    test_json_logging();
    test_i18n();
    test_window_positioning();
    test_regressions_text_scroll_and_wrap();
    test_viewport_resize_and_stretch();
    test_text_fit_api();
    test_webview_headless();
    test_webview_live_smoke();
    print("ALL GOOSE_UI TESTS PASSED");
}
