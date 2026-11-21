// Full-featured Kitchen Sink showcase using goose_ui's scoped nested DSL,
// Win32-style action IDs, declarative Signal-Slot bindings, and Direct2D Canvas.
//
// Run with:   goose run examples/kitchen_sink.goose
// Build with: goose build examples/kitchen_sink.goose
import std;
import math;
import win32 from "../win32-goose";
import goose_ui from "..";

// Menu command IDs
let ID_FILE_OPEN: u32 = 1001;
let ID_FILE_SAVE: u32 = 1002;
let ID_FILE_FOLDER: u32 = 1003;
let ID_FILE_QUIT: u32 = 1004;
let ID_EDIT_COLOR: u32 = 2001;
let ID_EDIT_INPUT: u32 = 2002;
let ID_EDIT_COPY: u32 = 2003;
let ID_VIEW_THEME: u32 = 3001;
let ID_HELP_ABOUT: u32 = 4001;

// Control action IDs
let IDC_BTN_DEF = 101;
let IDC_BTN_PRI = 102;
let IDC_BTN_SEC = 103;
let IDC_BTN_DNG = 104;
let IDC_BTN_GHO = 105;
let IDC_BTN_TOG = 106;
let IDC_BTN_TARGET = 107;
let IDC_CHK_OPT = 108;
let IDC_RAD_STYLE = 109;
let IDC_DLG_OPEN = 201;
let IDC_DLG_FOLDER = 202;
let IDC_DLG_COLOR = 203;
let IDC_DLG_INPUT = 204;
let IDC_DLG_ASK = 205;
let IDC_CLR_DOTS = 301;

struct CanvasDot {
    x: f32,
    y: f32,
}

fn main() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Direct2D);

    let win = app.create_window("goose_ui — Kitchen Sink Showcase", 1020, 680);
    guard app.valid_window(win) else { abort("failed to create window"); }
    app.enable_drop_files(win, true);
    app.set_status_bar(win, "Ready — Try switching tabs, dragging the splitter, or dropping files here.");

    // --- Native Menu Bar ----------------------------------------------------
    let mbar = app.create_menu_bar(win);
    let m_file = goose_ui::add_submenu(mbar, "&File");
    goose_ui::add_action(m_file, ID_FILE_OPEN, "&Open File...");
    goose_ui::add_action(m_file, ID_FILE_SAVE, "&Save File...");
    goose_ui::add_action(m_file, ID_FILE_FOLDER, "Select &Folder...");
    goose_ui::add_menu_separator(m_file);
    goose_ui::add_action(m_file, ID_FILE_QUIT, "E&xit");

    let m_edit = goose_ui::add_submenu(mbar, "&Edit");
    goose_ui::add_action(m_edit, ID_EDIT_COLOR, "Choose Accent &Color...");
    goose_ui::add_action(m_edit, ID_EDIT_INPUT, "&Input Dialog...");
    goose_ui::add_action(m_edit, ID_EDIT_COPY, "Copy &Status to Clipboard");

    let m_view = goose_ui::add_submenu(mbar, "&View");
    goose_ui::add_action(m_view, ID_VIEW_THEME, "Toggle &Dark / Light Theme");

    let m_help = goose_ui::add_submenu(mbar, "&Help");
    goose_ui::add_action(m_help, ID_HELP_ABOUT, "&About goose_ui");
    app.refresh_menu_bar(win);

    // Handles for widgets updated dynamically or wired across siblings
    var sw_dark = goose_ui::WIDGET_NONE;
    var tabs = goose_ui::WIDGET_NONE;
    var chk_enable = goose_ui::WIDGET_NONE;
    var target_btn = goose_ui::WIDGET_NONE;
    var lbl_val = goose_ui::WIDGET_NONE;
    var spin = goose_ui::WIDGET_NONE;
    var slider = goose_ui::WIDGET_NONE;
    var pbar = goose_ui::WIDGET_NONE;
    var btn_m10 = goose_ui::WIDGET_NONE;
    var btn_p10 = goose_ui::WIDGET_NONE;
    var ed_name = goose_ui::WIDGET_NONE;
    var lbl_mirror = goose_ui::WIDGET_NONE;
    var cb_role = goose_ui::WIDGET_NONE;
    var lbl_dlg_res = goose_ui::WIDGET_NONE;
    var lv = goose_ui::WIDGET_NONE;
    var lbl_sel_hdr = goose_ui::WIDGET_NONE;
    var canvas = goose_ui::WIDGET_NONE;

    // --- Declarative Scoped UI Tree (SwiftUI/Compose-style + Win32 IDs) -----
    app.ui(win) { u =>
        u.padding(14.0).spacing(10.0);

        // Header Bar
        u.hbox(12.0) { hdr =>
            hdr.vbox(2.0) { col =>
                col.stretch(1.0);
                col.label("goose_ui Showcase").heading();
                col.label("Zero-heap retained-mode GUI in Goose — Scoped DSL + Win32 IDs + Direct2D & Software GDI")
                    .caption()
                    .fg(goose_ui::color_hex(0x94A3B8));
            };
            hdr.toggle("Dark Theme", true)
                .tooltip("Live switch Dark / Light theme + Windows 11 DWM titlebar")
                .on_toggle_theme()
                .bind(sw_dark);
        };

        // Main Tabs
        u.tabs() { t =>
            t.stretch(1.0).bind(tabs);

            // TAB 1: Controls & Declarative Signal-Slot Binding
            t.tab("Controls & Signals", goose_ui::LayoutKind.VBox, 12.0, 14.0) { p =>
                p.group_box("Buttons & Toggle States", goose_ui::LayoutKind.HBox, 10.0, 12.0) { g =>
                    g.button("Default").action(IDC_BTN_DEF);
                    g.button("Primary").primary().tooltip("Primary accent action button").action(IDC_BTN_PRI);
                    g.button("Secondary").secondary().action(IDC_BTN_SEC);
                    g.button("Danger").danger().action(IDC_BTN_DNG);
                    g.button("Ghost").ghost().action(IDC_BTN_GHO);
                    g.button("Checkable").checkable(true).tooltip("Sticky toggle button").action(IDC_BTN_TOG);
                };

                p.hbox(12.0) { mid =>
                    mid.stretch(1.0);

                    mid.group_box("Selection & Exclusivity", goose_ui::LayoutKind.VBox, 8.0, 12.0) { g =>
                        g.stretch(1.0);
                        g.checkbox("Enable linked target button", true).bind(chk_enable);
                        g.checkbox("Hardware acceleration (Direct2D)", true).action(IDC_CHK_OPT);
                        g.separator();
                        g.label("Auto-exclusive Radio Group:").bold();
                        g.radio("Fusion Style (Default)", true).action(IDC_RAD_STYLE);
                        g.radio("Compact Density", false).action(IDC_RAD_STYLE);
                        g.radio("High Contrast", false).action(IDC_RAD_STYLE);
                        g.separator();
                        g.button("Target controlled by CheckBox").primary().action(IDC_BTN_TARGET).bind(target_btn);
                    };

                    mid.group_box("Declarative Signal -> Slot Binding", goose_ui::LayoutKind.VBox, 10.0, 12.0) { g =>
                        g.stretch(1.0);
                        g.label("Slider, SpinBox, Label & ProgressBar stay in sync automatically via app.connect():").caption();

                        g.hbox(8.0) { vh =>
                            vh.label("Value:").bold();
                            vh.label("42").mono().bind(lbl_val);
                            vh.spacer(1.0);
                            vh.spin_box(0.0, 100.0, 42.0, 5.0, 0).bind(spin);
                        };

                        g.slider(0.0, 100.0, 42.0, 1.0).bind(slider);
                        g.progress_bar(0.0, 100.0, 42.0).bind(pbar);

                        g.hbox(8.0) { sr =>
                            sr.button("-10").secondary().bind(btn_m10);
                            sr.button("+10").secondary().bind(btn_p10);
                        };
                    };
                };
            };

            // TAB 2: Form Layout, Text Editing & Native Dialogs
            t.tab("Form & Dialogs", goose_ui::LayoutKind.VBox, 12.0, 14.0) { p =>
                p.group_box("QFormLayout (UTF-8, Selection, Copy/Cut/Paste, Live Sync)", goose_ui::LayoutKind.Form, 10.0, 12.0) { g =>
                    g.label("Display Name:");
                    g.line_edit("Enter your name (日本語OK)...", "Goose Developer").bind(ed_name);
                    g.label("Live Mirror:");
                    g.label("Goose Developer").bold().bind(lbl_mirror);
                    g.label("Secret Token:");
                    g.line_edit("Password...", "s3cr3t-goose").password(true);
                    g.label("Role:");
                    g.combo_box()
                        .item("Systems Programmer")
                        .item("Graphics Engineer")
                        .item("GUI Architect")
                        .item("Game Developer")
                        .select(2)
                        .bind(cb_role);
                };

                p.hbox(10.0) { row =>
                    row.button("Clear Name")
                        .secondary()
                        .connect(goose_ui::SignalKind.OnClick, ed_name, goose_ui::SlotAction.ClearText)
                        .connect(goose_ui::SignalKind.OnClick, lbl_mirror, goose_ui::SlotAction.ClearText);
                    row.spacer(1.0);
                };

                p.group_box("Native Windows Common Dialogs", goose_ui::LayoutKind.HBox, 10.0, 12.0) { g =>
                    g.button("Open File...").action(IDC_DLG_OPEN);
                    g.button("Select Folder...").action(IDC_DLG_FOLDER);
                    g.button("Pick Accent Color...").primary().action(IDC_DLG_COLOR);
                    g.button("Input Box...").action(IDC_DLG_INPUT);
                    g.button("Message Box").secondary().action(IDC_DLG_ASK);
                };

                p.label("Dialog result will appear here.").mono().bind(lbl_dlg_res);
            };

            // TAB 3: Interactive Splitter, ListView & ScrollArea
            t.tab("Splitter & Lists", goose_ui::LayoutKind.VBox, 8.0, 12.0) { p =>
                p.splitter(goose_ui::Orientation.Horizontal, 0.40) { sp =>
                    sp.stretch(1.0);

                    sp.vbox(8.0, 4.0) { left =>
                        left.label("Components (scroll or Up/Down):").bold();
                        left.list_view(32.0)
                            .stretch(1.0)
                            .item("QApplication -> App", "root struct", 1)
                            .item("Scoped DSL -> app.ui(win)", "Zero-cost", 2)
                            .item("Software GDI + ClearType", "~11 MB RAM", 3)
                            .item("Direct2D + DirectWrite", "GPU Vector", 4)
                            .item("VBox / HBox / Grid / Form", "2-Pass", 5)
                            .item("Win32 Bounds + Anchor", "Resize-safe", 6)
                            .item("QSplitter", "Draggable", 7)
                            .item("QScrollArea", "Viewport", 8)
                            .item("QTabWidget", "Multi-page", 9)
                            .item("QPushButton", "5 Variants", 10)
                            .item("QCheckBox / QRadioButton", "Exclusive", 11)
                            .item("ToggleSwitch", "Modern UI", 12)
                            .item("QLineEdit", "UTF-8 + Clip", 13)
                            .item("QSlider / QSpinBox", "Numeric", 14)
                            .item("QComboBox / QListView", "Overlay", 15)
                            .item("QPainter -> Canvas", "Custom 2D", 16)
                            .select(0)
                            .bind(lv);
                    };

                    sp.vbox(8.0, 4.0) { right =>
                        right.label("Inspector — QApplication -> App").subheading().bind(lbl_sel_hdr);
                        right.scroll_area(8.0, 12.0) { sc =>
                            sc.stretch(1.0);
                            for i: i32 in 1..16 {
                                sc.frame(goose_ui::LayoutKind.HBox, 8.0, 10.0) { card =>
                                    card.label(str("Property Row #", i)).bold().stretch(1.0);
                                    card.label(str("Slot ", i * 16, " B")).mono();
                                };
                            }
                        };
                    };
                };
            };

            // TAB 4: Custom Direct2D Canvas + QTimer Animation
            t.tab("QPainter Canvas", goose_ui::LayoutKind.VBox, 10.0, 12.0) { p =>
                p.hbox(10.0) { bar =>
                    bar.label("Click on the canvas to place glowing nodes; scroll wheel to adjust orbit radius.").caption();
                    bar.spacer(1.0);
                    bar.button("Clear Nodes").secondary().action(IDC_CLR_DOTS);
                };
                p.canvas(320.0, 260.0).stretch(1.0).bind(canvas);
            };
        };
    };

    // --- Declarative Signal -> Slot Connections -----------------------------
    app.connect(chk_enable, goose_ui::SignalKind.OnToggle, target_btn, goose_ui::SlotAction.SetEnabled);
    app.connect(ed_name, goose_ui::SignalKind.OnTextChange, lbl_mirror, goose_ui::SlotAction.SyncText);

    app.connect(slider, goose_ui::SignalKind.OnValueChange, pbar, goose_ui::SlotAction.SetValue);
    app.connect(slider, goose_ui::SignalKind.OnValueChange, spin, goose_ui::SlotAction.SetValue);
    app.connect(slider, goose_ui::SignalKind.OnValueChange, lbl_val, goose_ui::SlotAction.SetValueLabel);
    app.connect(spin, goose_ui::SignalKind.OnValueChange, slider, goose_ui::SlotAction.SetValue);
    app.connect(spin, goose_ui::SignalKind.OnValueChange, pbar, goose_ui::SlotAction.SetValue);
    app.connect(spin, goose_ui::SignalKind.OnValueChange, lbl_val, goose_ui::SlotAction.SetValueLabel);
    app.connect(btn_m10, goose_ui::SignalKind.OnClick, slider, goose_ui::SlotAction.IncrementValue, -10.0);
    app.connect(btn_p10, goose_ui::SignalKind.OnClick, slider, goose_ui::SlotAction.IncrementValue, 10.0);

    var dots: CanvasDot[>..] = [];
    var orbit_r: f32 = 110.0;
    var anim_t: f64 = 0.0;
    let anim_timer = app.start_timer(win, 16, false);

    app.show_window(win);

    fn pick_accent() {
        var col = app.theme.accent;
        if app.choose_color_dialog(win, col) {
            var nt = app.theme;
            nt.accent = col;
            nt.accent_hover = goose_ui::lerp_color(col, goose_ui::rgb(255, 255, 255), 0.18);
            nt.accent_active = goose_ui::lerp_color(col, goose_ui::rgb(0, 0, 0), 0.18);
            nt.border_focus = nt.accent_hover;
            app.set_theme(nt);
            app.set_text(lbl_dlg_res, "Updated theme accent color live!");
            app.set_status_text(win, "Accent color updated");
        }
    }

    fn paint_canvas(cid: goose_ui::WidgetId, p: goose_ui::Painter) {
        if goose_ui::eq(cid, canvas) {
            let grid_col = goose_ui::with_alpha(p.theme.border, 0.35);
            var gx: f32 = 32.0;
            while gx < p.width {
                p.draw_line(gx, 4.0, gx, p.height - 4.0, grid_col, 1.0);
                gx += 32.0;
            }
            var gy: f32 = 32.0;
            while gy < p.height {
                p.draw_line(4.0, gy, p.width - 4.0, gy, grid_col, 1.0);
                gy += 32.0;
            }

            let cx = p.width * 0.5;
            let cy = p.height * 0.5;
            p.draw_ellipse(cx, cy, orbit_r, orbit_r * 0.65, goose_ui::with_alpha(p.theme.accent, 0.35), 1.5);
            for i in 10 {
                let a = anim_t + i * 0.6283185307;
                let ox = cx + (cos(a) * orbit_r) as f32;
                let oy = cy + (sin(a) * orbit_r * 0.65) as f32;
                let rad = (8.0 + sin(anim_t * 2.0 + i) * 3.0) as f32;
                p.fill_ellipse(ox, oy, rad + 4.0, rad + 4.0, goose_ui::with_alpha(p.theme.accent, 0.22));
                p.fill_ellipse(ox, oy, rad, rad, p.theme.accent);
            }

            for i in dots.len {
                if i > 0 {
                    p.draw_line(dots[i - 1].x, dots[i - 1].y, dots[i].x, dots[i].y, goose_ui::with_alpha(p.theme.success, 0.7), 2.0);
                }
                p.fill_ellipse(dots[i].x, dots[i].y, 10.0, 10.0, goose_ui::with_alpha(p.theme.success, 0.28));
                p.fill_ellipse(dots[i].x, dots[i].y, 5.5, 5.5, p.theme.success);
            }

            p.draw_text("Direct2D Custom QPainter Canvas", 14.0, 10.0, 320.0, 24.0, p.theme.text_secondary, goose_ui::FontRole.BodyBold);
        }
    }

    app.exec_with_canvas(paint_canvas) { sig =>
        match sig {
            TimerFired s => {
                if s.timer_id == anim_timer && app.current_tab(tabs) == 3 {
                    anim_t += 0.035;
                    app.mark_dirty(win);
                }
            },
            Clicked s => {
                match app.action_id(s.widget) {
                    IDC_BTN_DEF => { app.set_status_text(win, "Clicked Default button"); },
                    IDC_BTN_PRI => { app.set_status_text(win, "Clicked Primary button"); },
                    IDC_BTN_SEC => { app.set_status_text(win, "Clicked Secondary button"); },
                    IDC_BTN_DNG => { app.set_status_text(win, "Clicked Danger button"); },
                    IDC_BTN_GHO => { app.set_status_text(win, "Clicked Ghost button"); },
                    IDC_BTN_TOG => {
                        app.set_status_text(win, if app.is_checked(s.widget) { "Checkable button: ON" } else { "Checkable button: OFF" });
                    },
                    IDC_BTN_TARGET => { app.set_status_text(win, "Linked target button clicked!"); },
                    IDC_CHK_OPT => {
                        app.set_status_text(win, str("Hardware acceleration: ", if app.is_checked(s.widget) { "ON" } else { "OFF" }));
                    },
                    IDC_RAD_STYLE => {
                        app.set_status_text(win, str("Selected style: ", app.text(s.widget)));
                    },
                    IDC_DLG_OPEN => {
                        var path: u8[>..] = [];
                        if app.open_file_dialog(win, path, "Open Goose File", "Goose (*.goose)|*.goose|All Files (*.*)|*.*") {
                            app.set_text(lbl_dlg_res, str("Opened: ", path));
                            app.set_status_text(win, str("Selected file: ", path));
                        }
                    },
                    IDC_DLG_FOLDER => {
                        var path: u8[>..] = [];
                        if app.select_folder_dialog(win, path) {
                            app.set_text(lbl_dlg_res, str("Folder: ", path));
                        }
                    },
                    IDC_DLG_COLOR => { pick_accent(); },
                    IDC_DLG_INPUT => {
                        var txt: u8[>..] = [];
                        if app.input_dialog(win, txt, "goose_ui Input", "Enter new display name:", app.text(ed_name)) {
                            app.set_text(ed_name, txt);
                            app.set_text(lbl_mirror, txt);
                            app.set_text(lbl_dlg_res, str("Input: ", txt));
                        }
                    },
                    IDC_DLG_ASK => {
                        let yes = app.msg_question(win, "goose_ui", "Do you enjoy zero-heap GUI programming in Goose?");
                        app.set_text(lbl_dlg_res, if yes { "Answered: YES!" } else { "Answered: No" });
                    },
                    IDC_CLR_DOTS => {
                        dots.clear();
                        app.mark_dirty(win);
                    },
                    _ => {},
                }
            },
            SelectionChanged s => {
                if goose_ui::eq(s.widget, lv) {
                    let name = app.item_text(lv, s.index);
                    let sub_t = app.item_subtext(lv, s.index);
                    app.set_text(lbl_sel_hdr, str("Inspector — ", name));
                    app.set_status_text(win, str("Selected: ", name, " [", sub_t, "]"));
                } else if goose_ui::eq(s.widget, cb_role) {
                    app.set_status_text(win, str("Role changed to: ", app.item_text(cb_role, s.index)));
                }
            },
            ItemActivated s => {
                if goose_ui::eq(s.widget, lv) {
                    app.set_status_text(win, str("Activated item: ", app.item_text(lv, s.index)));
                }
            },
            TabChanged s => {
                app.set_status_text(win, str("Switched to tab #", s.index + 1, ": ", app.item_text(tabs, s.index)));
            },
            CanvasMouseDown s => {
                if goose_ui::eq(s.widget, canvas) && s.button == goose_ui::MOUSE_LEFT {
                    dots.push(CanvasDot { x: s.x, y: s.y });
                    app.mark_dirty(win);
                    app.set_status_text(win, str("Placed node #", dots.len, " at (", s.x as! i32, ", ", s.y as! i32, ")"));
                }
            },
            CanvasWheel s => {
                if goose_ui::eq(s.widget, canvas) {
                    orbit_r = goose_ui::clamp_f32(orbit_r + (if s.delta > 0 { 12.0 } else { -12.0 }), 35.0, 220.0);
                    app.mark_dirty(win);
                }
            },
            FilesDropped s => {
                if s.count > 0 {
                    let first = goose_ui::dropped_file_path(0);
                    app.set_status_text(win, str("Dropped ", s.count, " file(s): ", first));
                }
            },
            ActionTriggered s => {
                if s.action_id == ID_FILE_QUIT {
                    app.close_window(win);
                } else if s.action_id == ID_FILE_OPEN {
                    var path: u8[>..] = [];
                    if app.open_file_dialog(win, path) {
                        app.set_status_text(win, str("Opened: ", path));
                    }
                } else if s.action_id == ID_FILE_SAVE {
                    var path: u8[>..] = [];
                    if app.save_file_dialog(win, path, "Save As", "Text (*.txt)|*.txt|All (*.*)|*.*", "txt", "export.txt") {
                        app.set_status_text(win, str("Save target: ", path));
                    }
                } else if s.action_id == ID_FILE_FOLDER {
                    var path: u8[>..] = [];
                    if app.select_folder_dialog(win, path) {
                        app.set_status_text(win, str("Folder: ", path));
                    }
                } else if s.action_id == ID_EDIT_COLOR {
                    pick_accent();
                } else if s.action_id == ID_EDIT_INPUT {
                    var txt: u8[>..] = [];
                    if app.input_dialog(win, txt, "Input", "Set window title:", "goose_ui") {
                        app.set_window_title(win, txt);
                    }
                } else if s.action_id == ID_EDIT_COPY {
                    goose_ui::set_clipboard_text("Copied from goose_ui!");
                    app.set_status_text(win, "Copied message to Windows clipboard.");
                } else if s.action_id == ID_VIEW_THEME {
                    app.toggle_theme();
                    app.set_checked(sw_dark, app.is_dark_theme());
                } else if s.action_id == ID_HELP_ABOUT {
                    app.msg_info(win, "About goose_ui", "goose_ui — Scoped DSL + Qt-inspired retained-mode GUI framework\nBuilt in pure Goose on top of win32-goose (Software GDI & Direct2D).");
                }
            },
            _ => {},
        }
    };
}
