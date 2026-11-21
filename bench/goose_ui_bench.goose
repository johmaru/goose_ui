// Memory & startup/layout/render benchmark for goose_ui.
// Usage:
//   goose build bench/goose_ui_bench.goose
//   ./bench/goose_ui_bench.exe --count 1000
//   ./bench/goose_ui_bench.exe --count 1000 --headless
import std;
import os;
import win32 from "../win32-goose";
import goose_ui from "..";

// Windows x64 PROCESS_MEMORY_COUNTERS_EX (80 bytes, zero padding).
struct ProcessMemoryCountersEx {
    cb: u32 = 80,
    page_fault_count: u32 = 0,
    peak_working_set: u64 = 0,
    working_set: u64 = 0,
    quota_peak_paged: u64 = 0,
    quota_paged: u64 = 0,
    quota_peak_nonpaged: u64 = 0,
    quota_nonpaged: u64 = 0,
    pagefile_usage: u64 = 0,
    peak_pagefile_usage: u64 = 0,
    private_usage: u64 = 0,
}

extern "kernel32" {
    fn K32GetProcessMemoryInfo(hproc: u64, counters: ProcessMemoryCountersEx&, cb: u32) -> i32;
}

fn read_mem() -> ProcessMemoryCountersEx {
    var pmc = ProcessMemoryCountersEx { cb: 80 };
    // Pseudo-handle for current process on Windows is (HANDLE)-1.
    K32GetProcessMemoryInfo(0xFFFFFFFFFFFFFFFF, pmc, 80);
    return pmc;
}

fn main() {
    let t_start = win32::perf_counter();
    let freq = win32::perf_frequency();

    var count: i32 = 0;
    var headless = false;
    var software = false;
    let argv = args();
    var ai: i64 = 1;
    while ai < argv.len {
        if argv[ai] == "--count" && ai + 1 < argv.len {
            let n, ok = parse_int(argv[ai + 1]);
            if ok && n >= 0 { count = n as! i32; }
            ai += 2;
        } else if argv[ai] == "--headless" {
            headless = true;
            ai += 1;
        } else if argv[ai] == "--software" {
            software = true;
            ai += 1;
        } else {
            ai += 1;
        }
    }

    var app = goose_ui::App { .. };
    app.init(true, if software { goose_ui::RenderBackend.Software } else { goose_ui::RenderBackend.Direct2D });

    let win = if headless {
        app.create_headless_window("goose_ui Memory Bench", 900, 640)
    } else {
        app.create_window("goose_ui Memory Bench", 900, 640)
    };
    guard app.valid_window(win) else { abort("create_window failed"); }

    let root = app.root(win);
    app.set_padding(root, 10.0);
    app.set_spacing(root, 6.0);
    app.set_status_bar(win, "Benchmark running");

    var created_controls: i32 = 0;
    if count > 0 {
        let scroll = app.add_scroll_area(root, 4.0, 6.0);
        app.set_stretch(scroll, 1.0);
        let rows = (count + 4) / 5;
        for r: i32 in 0..rows {
            let row = app.add_hbox(scroll, 6.0);
            if created_controls < count {
                app.add_label(row, str("Row ", r));
                created_controls += 1;
            }
            if created_controls < count {
                let ed = app.add_line_edit(row, "Value", str("Item ", r));
                app.set_stretch(ed, 1.0);
                created_controls += 1;
            }
            if created_controls < count {
                app.add_checkbox(row, "Active", (r % 2) == 0);
                created_controls += 1;
            }
            if created_controls < count {
                let pb = app.add_progress_bar(row, 0.0, 100.0, (r * 7) % 100);
                app.set_fixed_width(pb, 90.0);
                created_controls += 1;
            }
            if created_controls < count {
                app.add_button(row, "Action", goose_ui::ButtonVariant.Default);
                created_controls += 1;
            }
        }
    }

    let t_built = win32::perf_counter();

    if !headless {
        app.show_window(win);
    }
    app.update_layout(win, true);
    let t_laid_out = win32::perf_counter();

    app.render_window(win);
    if !headless {
        var ev = win32::Event {};
        while win32::poll_event(ev) {}
        app.render_window(win);
    }
    let t_rendered = win32::perf_counter();

    let pmc = read_mem();
    let total_widgets = app.widgets.len;

    let build_ms = (t_built - t_start) * 1000.0 / freq;
    let layout_ms = (t_laid_out - t_built) * 1000.0 / freq;
    let render_ms = (t_rendered - t_laid_out) * 1000.0 / freq;
    let total_ms = (t_rendered - t_start) * 1000.0 / freq;

    // Emit single-line JSON for benchmark harness.
    let mode_name = if headless {
        "goose_ui_headless"
    } else if software {
        "goose_ui_software"
    } else {
        "goose_ui_d2d"
    };
    var out: u8[>..] = [];
    format(out, "{\"framework\":\"", mode_name, "\",");
    format(out, "\"controls\":", created_controls, ",");
    format(out, "\"total_widgets\":", total_widgets, ",");
    format(out, "\"str_pool_bytes\":", app.str_pool.len, ",");
    format(out, "\"private_bytes\":", pmc.private_usage, ",");
    format(out, "\"working_set\":", pmc.working_set, ",");
    format(out, "\"peak_working_set\":", pmc.peak_working_set, ",");
    format(out, "\"build_ms\":");
    format_flt(out, build_ms, 2);
    format(out, ",\"layout_ms\":");
    format_flt(out, layout_ms, 2);
    format(out, ",\"render_ms\":");
    format_flt(out, render_ms, 2);
    format(out, ",\"total_ms\":");
    format_flt(out, total_ms, 2);
    format(out, "}");
    print(out);

    app.destroy_all();
}
