// Automated test suite for goose_ui (layout math, widget tree lifecycle,
// generational handles, hit testing, input state machines, UTF-8 LineEdit,
// Qt-style Signal/Slot declarative connections, and real Win32+D2D smoke test).
//
// Run with:   goose run test/goose_ui_test.goose
// Build with: goose build test/goose_ui_test.goose
import std;
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

fn main() {
    test_tree_and_handles();
    test_layouts();
    test_widgets_and_signals();
    test_combo_list_tabs_focus();
    test_real_win32_d2d_smoke();
    test_software_gdi_and_str_pool();
    test_dsl_and_win32_anchors();
    test_regressions_canvas_and_visibility();
    test_regressions_inputs_and_signals();
    test_regressions_layout_and_pools();
    print("ALL GOOSE_UI TESTS PASSED");
}
