// Minimal Counter example using goose_ui's scoped nested DSL + Win32-style action IDs.
// Run with:   goose run examples/counter.goose
// Build with: goose build examples/counter.goose
import std;
import win32 from "../win32-goose";
import goose_ui from "..";

let ID_DEC = 101;
let ID_RST = 102;
let ID_INC = 103;
let ID_VAL = 200;

fn main() {
    var app = goose_ui::App { .. };
    app.init(true, goose_ui::RenderBackend.Software);

    let win = app.create_window("goose_ui — Counter", 420, 290);
    guard app.valid_window(win) else { abort("failed to create window"); }
    app.set_status_bar(win, "Press buttons or Tab + Space to interact");

    app.ui(win) { u =>
        u.padding(18.0).spacing(14.0);

        u.hbox(8.0) { hdr =>
            hdr.label("Goose UI Counter").heading().stretch(1.0);
            hdr.toggle("Dark", true).on_toggle_theme();
        };

        u.frame(goose_ui::LayoutKind.VBox, 6.0, 16.0) { card =>
            card.stretch(1.0);
            card.label("Current Value").caption().center();
            card.label("0").heading().center().stretch(1.0).action(ID_VAL);
        };

        u.hbox(10.0) { row =>
            row.button("- Decrement").secondary().stretch(1.0).tooltip("Decrease by 1").action(ID_DEC);
            row.button("Reset").ghost().stretch(0.8).action(ID_RST);
            row.button("+ Increment").primary().stretch(1.0).tooltip("Increase by 1").action(ID_INC);
        };
    };

    var count: i64 = 0;
    app.show_window(win);

    app.exec() { sig =>
        match sig {
            Clicked s => {
                var changed = true;
                match app.action_id(s.widget) {
                    ID_INC => { count += 1; },
                    ID_DEC => { count -= 1; },
                    ID_RST => { count = 0; },
                    _ => { changed = false; },
                }
                if changed {
                    app.set_text_of(win, ID_VAL, str(count));
                    app.set_status_text(win, str("Count updated to ", count));
                }
            },
            _ => {},
        }
    };
}
