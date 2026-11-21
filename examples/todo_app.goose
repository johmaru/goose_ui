// Practical Todo Manager built with goose_ui's scoped nested DSL + Win32-style IDs.
// Run with:   goose run examples/todo_app.goose
// Build with: goose build examples/todo_app.goose
import std;
import win32 from "../win32-goose";
import goose_ui from "..";

struct TodoItem {
    title: u8[..160] = [],
    priority: u8[..24] = [],
    done: bool = false,
}

// Menu command IDs
let ACT_QUIT: u32 = 101;
let ACT_MARK_ALL: u32 = 201;
let ACT_CLEAR_DONE: u32 = 202;
let ACT_THEME: u32 = 301;

// Control action IDs
let ID_ADD = 1001;
let ID_TOGGLE = 1002;
let ID_DELETE = 1003;
let ID_CLEAR = 1004;
let ID_FLT_ALL = 1010;
let ID_FLT_ACTIVE = 1011;
let ID_FLT_DONE = 1012;

fn make_todo(title: const u8[:], priority: const u8[:], done: bool = false) -> TodoItem {
    var t = TodoItem { done: done };
    goose_ui::copy_str(t.title, title);
    goose_ui::copy_str(t.priority, priority);
    return t;
}

fn main() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Software);

    let win = app.create_window("goose_ui — Todo Manager", 680, 560);
    guard app.valid_window(win) else { abort("failed to create window"); }
    app.set_status_bar(win, "Type a task and press Enter or click Add");

    // Native Menu Bar
    let mbar = app.create_menu_bar(win);
    let m_file = goose_ui::add_submenu(mbar, "&File");
    goose_ui::add_action(m_file, ACT_QUIT, "E&xit\tAlt+F4");
    let m_tasks = goose_ui::add_submenu(mbar, "&Tasks");
    goose_ui::add_action(m_tasks, ACT_MARK_ALL, "&Mark All Done");
    goose_ui::add_action(m_tasks, ACT_CLEAR_DONE, "&Clear Completed");
    let m_view = goose_ui::add_submenu(mbar, "&View");
    goose_ui::add_action(m_view, ACT_THEME, "Toggle &Dark / Light Theme");
    app.refresh_menu_bar(win);

    // Bind only widgets we read/write directly; buttons & radios use Win32-style IDs.
    var sw_theme = goose_ui::WIDGET_NONE;
    var input = goose_ui::WIDGET_NONE;
    var prio = goose_ui::WIDGET_NONE;
    var search = goose_ui::WIDGET_NONE;
    var list = goose_ui::WIDGET_NONE;
    var prog = goose_ui::WIDGET_NONE;

    app.ui(win) { u =>
        u.padding(16.0).spacing(12.0);

        u.hbox(10.0) { hdr =>
            hdr.label("Tasks").heading().stretch(1.0);
            hdr.toggle("Dark Mode", true).on_toggle_theme().bind(sw_theme);
        };

        u.hbox(8.0) { add_row =>
            add_row.line_edit("Add a new task... (press Enter)").stretch(1.0).bind(input);
            add_row.combo_box().width(110.0).item("High").item("Normal").item("Low").select(1).bind(prio);
            add_row.button("Add Task").primary().width(100.0).action(ID_ADD);
        };

        u.hbox(10.0) { flt_row =>
            flt_row.radio("All", true).action(ID_FLT_ALL);
            flt_row.radio("Active", false).action(ID_FLT_ACTIVE);
            flt_row.radio("Done", false).action(ID_FLT_DONE);
            flt_row.spacer(1.0);
            flt_row.line_edit("Filter tasks...").width(200.0).bind(search);
        };

        u.list_view(34.0).stretch(1.0).bind(list);
        u.progress_bar(0.0, 100.0, 0.0).bind(prog);

        u.hbox(8.0) { act_row =>
            act_row.button("Toggle Done").action(ID_TOGGLE);
            act_row.button("Delete Selected").danger().action(ID_DELETE);
            act_row.spacer(1.0);
            act_row.button("Clear Completed").secondary().action(ID_CLEAR);
        };
    };

    var todos: TodoItem[>..] = [];
    todos.push(make_todo("Explore goose_ui nested DSL + Win32 action IDs", "High", true));
    todos.push(make_todo("Try Signal-Slot declarative connections", "Normal", false));
    todos.push(make_todo("Switch between Dark and Light themes live", "Low", false));
    todos.push(make_todo("Double-click any task in this list to toggle completion", "Normal", false));

    var filter_mode: i32 = 0; // 0=All, 1=Active, 2=Done

    fn rebuild_list() {
        let prev_sel = app.selected_index(list);
        app.clear_items(list);
        let q = app.text(search);
        var done_count: i32 = 0;
        for i in todos.len {
            if todos[i].done { done_count += 1; }
            if filter_mode == 1 && todos[i].done { continue; }
            if filter_mode == 2 && !todos[i].done { continue; }
            if q.len > 0 && find(todos[i].title, q) < 0 { continue; }

            var label: u8[>..] = [];
            format(label, if todos[i].done { "[x] " } else { "[ ] " }, todos[i].title);
            app.add_item(list, label, todos[i].priority, i);
        }
        let n = app.item_count(list);
        if prev_sel >= 0 && prev_sel < n {
            app.set_selected_index(list, prev_sel);
        } else if n > 0 {
            app.set_selected_index(list, 0);
        }

        let total = todos.len as! i32;
        let pct = if total > 0 { (done_count * 100.0) / total } else { 0.0 };
        app.set_value(prog, pct);
        app.set_status_text(win, str(done_count, " of ", total, " tasks completed (", n, " shown)"));
    }

    fn add_new_task() {
        let txt = trim(app.text(input));
        guard txt.len > 0 else { return; }
        let ptxt = app.item_text(prio, app.selected_index(prio));
        todos.push(make_todo(txt, if ptxt.len > 0 { ptxt } else { "Normal" }, false));
        app.set_text(input, "");
        rebuild_list();
    }

    rebuild_list();
    app.show_window(win);

    app.exec() { sig =>
        match sig {
            Clicked s => {
                match app.action_id(s.widget) {
                    ID_ADD => { add_new_task(); },
                    ID_TOGGLE => {
                        let sel = app.selected_index(list);
                        if sel >= 0 {
                            let ti = app.item_tag(list, sel);
                            if ti >= 0 && ti < todos.len {
                                todos[ti].done = !todos[ti].done;
                                rebuild_list();
                            }
                        }
                    },
                    ID_DELETE => {
                        let sel = app.selected_index(list);
                        if sel >= 0 {
                            let ti = app.item_tag(list, sel);
                            if ti >= 0 && ti < todos.len {
                                remove_at(todos, ti);
                                rebuild_list();
                            }
                        }
                    },
                    ID_CLEAR => {
                        var i = todos.len;
                        while i > 0 {
                            i -= 1;
                            if todos[i].done { remove_at(todos, i); }
                        }
                        rebuild_list();
                    },
                    _ => {},
                }
            },
            Toggled s => {
                if s.checked {
                    match app.action_id(s.widget) {
                        ID_FLT_ALL => { filter_mode = 0; rebuild_list(); },
                        ID_FLT_ACTIVE => { filter_mode = 1; rebuild_list(); },
                        ID_FLT_DONE => { filter_mode = 2; rebuild_list(); },
                        _ => {},
                    }
                }
            },
            TextSubmitted s => {
                if goose_ui::eq(s.widget, input) { add_new_task(); }
            },
            TextChanged s => {
                if goose_ui::eq(s.widget, search) { rebuild_list(); }
            },
            ItemActivated s => {
                if goose_ui::eq(s.widget, list) {
                    let ti = app.item_tag(list, s.index);
                    if ti >= 0 && ti < todos.len {
                        todos[ti].done = !todos[ti].done;
                        rebuild_list();
                    }
                }
            },
            ActionTriggered s => {
                if s.action_id == ACT_QUIT {
                    app.close_window(win);
                } else if s.action_id == ACT_MARK_ALL {
                    for i in todos.len { todos[i].done = true; }
                    rebuild_list();
                } else if s.action_id == ACT_CLEAR_DONE {
                    var i = todos.len;
                    while i > 0 {
                        i -= 1;
                        if todos[i].done { remove_at(todos, i); }
                    }
                    rebuild_list();
                } else if s.action_id == ACT_THEME {
                    app.toggle_theme();
                    app.set_checked(sw_theme, app.is_dark_theme());
                }
            },
            _ => {},
        }
    };
}
