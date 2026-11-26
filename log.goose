// Structured JSON logging system for goose_ui.
// Supports user-chosen output paths (JsonLines / NDJSON or JsonArray),
// size-based file rotation, structured field builders, App integration,
// standalone JsonLogger, optional automatic UI Signal logging, and log reading.
namespace goose_ui;

import std;
import json;
import os;
import win32 from "./win32-goose";
import types;
import widget;
import tree;

// --- Level & Format Helpers -------------------------------------------------

fn log_level_rank(lvl: LogLevel) -> i32 {
    return match lvl {
        Trace => 0,
        Debug => 1,
        Info => 2,
        Warn => 3,
        Error => 4,
        Fatal => 5,
        Off => 6,
    };
}

fn log_level_from_rank(rank: i32) -> LogLevel {
    if rank <= 0 { return LogLevel.Trace; }
    if rank == 1 { return LogLevel.Debug; }
    if rank == 2 { return LogLevel.Info; }
    if rank == 3 { return LogLevel.Warn; }
    if rank == 4 { return LogLevel.Error; }
    if rank == 5 { return LogLevel.Fatal; }
    return LogLevel.Off;
}

fn log_level_name_rank(rank: i32) -> const u8[:] {
    if rank <= 0 { return "trace"; }
    if rank == 1 { return "debug"; }
    if rank == 2 { return "info"; }
    if rank == 3 { return "warn"; }
    if rank == 4 { return "error"; }
    if rank == 5 { return "fatal"; }
    return "off";
}

fn log_level_name(lvl: LogLevel) -> const u8[:] {
    return log_level_name_rank(log_level_rank(lvl));
}

fn eq_ascii_nocase(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        var ca = a[i];
        var cb = b[i];
        if ca >= 'A' && ca <= 'Z' { ca += 32; }
        if cb >= 'A' && cb <= 'Z' { cb += 32; }
        if ca != cb { return false; }
    }
    return true;
}

fn parse_log_level(s: const u8[:]) -> LogLevel, bool {
    let t = trim(s);
    if eq_ascii_nocase(t, "trace") { return LogLevel.Trace, true; }
    if eq_ascii_nocase(t, "debug") { return LogLevel.Debug, true; }
    if eq_ascii_nocase(t, "info") { return LogLevel.Info, true; }
    if eq_ascii_nocase(t, "warn") || eq_ascii_nocase(t, "warning") { return LogLevel.Warn, true; }
    if eq_ascii_nocase(t, "error") || eq_ascii_nocase(t, "err") { return LogLevel.Error, true; }
    if eq_ascii_nocase(t, "fatal") { return LogLevel.Fatal, true; }
    if eq_ascii_nocase(t, "off") { return LogLevel.Off, true; }
    return LogLevel.Info, false;
}

fn log_format_code(fmt: LogFormat) -> i32 {
    return match fmt {
        JsonLines => 0,
        JsonArray => 1,
    };
}

fn log_format_from_code(code: i32) -> LogFormat {
    if code == 1 { return LogFormat.JsonArray; }
    return LogFormat.JsonLines;
}

// --- Timestamp & Path Helpers -----------------------------------------------

fn append_digits2(out: u8[>..]&, v: u16) {
    let d1 = (v / 10) % 10;
    let d0 = v % 10;
    out.push(('0' + d1) as! u8);
    out.push(('0' + d0) as! u8);
}

fn append_digits3(out: u8[>..]&, v: u16) {
    let d2 = (v / 100) % 10;
    let d1 = (v / 10) % 10;
    let d0 = v % 10;
    out.push(('0' + d2) as! u8);
    out.push(('0' + d1) as! u8);
    out.push(('0' + d0) as! u8);
}

fn append_digits4(out: u8[>..]&, v: u16) {
    let d3 = (v / 1000) % 10;
    let d2 = (v / 100) % 10;
    let d1 = (v / 10) % 10;
    let d0 = v % 10;
    out.push(('0' + d3) as! u8);
    out.push(('0' + d2) as! u8);
    out.push(('0' + d1) as! u8);
    out.push(('0' + d0) as! u8);
}

fn format_log_timestamp(out: u8[>..]&, utc: bool) {
    var st = win32::SystemTime {};
    if utc {
        win32::system_time(st);
    } else {
        win32::local_time(st);
    }
    append_digits4(out, st.year);
    out.push('-');
    append_digits2(out, st.month);
    out.push('-');
    append_digits2(out, st.day);
    out.push('T');
    append_digits2(out, st.hour);
    out.push(':');
    append_digits2(out, st.minute);
    out.push(':');
    append_digits2(out, st.second);
    out.push('.');
    append_digits3(out, st.milliseconds);
    if utc {
        out.push('Z');
    }
}

fn is_path_sep(c: u8) -> bool {
    return c == '/' || c == '\\';
}

fn ensure_parent_dirs(path: const u8[:]) -> bool {
    var last_sep: i64 = -1;
    for i in path.len {
        if is_path_sep(path[i]) { last_sep = i; }
    }
    if last_sep <= 0 { return true; }

    var start: i64 = 0;
    if path.len >= 2 && is_path_sep(path[0]) && is_path_sep(path[1]) {
        // UNC path: \\server\share\... -> skip server and share components.
        var seps = 0;
        var p: i64 = 2;
        while p < last_sep {
            if is_path_sep(path[p]) {
                seps += 1;
                if seps == 2 {
                    start = p + 1;
                    break;
                }
            }
            p += 1;
        }
        if seps < 2 { return true; }
    } else if path.len >= 2 && path[1] == ':' {
        start = if path.len > 2 && is_path_sep(path[2]) { 3 } else { 2 };
    } else if is_path_sep(path[0]) {
        start = 1;
    }

    var i = start;
    while i <= last_sep {
        if i == last_sep || is_path_sep(path[i]) {
            if i > start && !is_path_sep(path[i - 1]) {
                let sub = path[..i];
                if sub != "." && !(sub.len == 2 && sub[1] == ':') {
                    if !win32::dir_exists(sub) {
                        if !win32::create_directory(sub) && !win32::dir_exists(sub) {
                            return false;
                        }
                    }
                }
            }
        }
        i += 1;
    }
    return true;
}

// --- Low-Level LogState File Operations -------------------------------------

fn log_state_close(st: LogState&) {
    if st.file.is_valid() {
        st.file.flush();
        st.file.close();
        st.file = win32::Hfile {};
    }
}

fn log_state_flush(st: LogState&) -> bool {
    if st.file.is_valid() {
        return st.file.flush();
    }
    return false;
}

fn log_open_handle(path: const u8[:], append: bool) -> win32::Hfile {
    let disp = if append { win32::OPEN_ALWAYS } else { win32::CREATE_ALWAYS };
    return win32::create_file(
        path,
        win32::GENERIC_READ | win32::GENERIC_WRITE,
        win32::FILE_SHARE_READ | win32::FILE_SHARE_WRITE | win32::FILE_SHARE_DELETE,
        disp,
        win32::FILE_ATTRIBUTE_NORMAL
    );
}

fn log_init_new_array_file(st: LogState&) -> bool {
    let _pos, seek_ok = st.file.seek(0, win32::FILE_BEGIN);
    guard seek_ok else { return false; }
    guard st.file.write_all("[]\n") else { return false; }
    guard st.file.truncate() else { return false; }
    st.has_array_entries = false;
    st.array_end_pos = 1;
    st.written_bytes = 3;
    if st.auto_flush { st.file.flush(); }
    return true;
}

fn is_json_ws(c: u8) -> bool {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

fn log_scan_existing_array(st: LogState&, sz: i64) -> bool {
    guard sz >= 2 else { return false; }
    var buf: u8[4096] = [0; 4096];
    var end = sz;
    var found_close = false;
    while end > 0 {
        let start = if end > 4096 { end - 4096 } else { 0 };
        let want = end - start;
        let _pos, seek_ok = st.file.seek(start, win32::FILE_BEGIN);
        guard seek_ok else { return false; }
        let got, read_ok = st.file.read(buf[..want]);
        guard read_ok && got > 0 else { return false; }

        var i = got - 1;
        while i >= 0 {
            let c = buf[i];
            if !found_close {
                if is_json_ws(c) {
                    i -= 1;
                    continue;
                }
                if c != ']' { return false; }
                found_close = true;
                i -= 1;
                continue;
            }
            if is_json_ws(c) {
                i -= 1;
                continue;
            }
            st.has_array_entries = c != '[';
            st.array_end_pos = start + i + 1;
            st.written_bytes = sz;
            return true;
        }
        end = start;
    }
    return false;
}

fn log_state_open(st: LogState&, path: const u8[:], opts: LogOptions) -> bool {
    guard path.len > 0 && !is_path_sep(path[path.len - 1]) else { return false; }
    log_state_close(st);

    if opts.create_dirs {
        guard ensure_parent_dirs(path) else { return false; }
    }

    let f = log_open_handle(path, opts.append);
    guard f.is_valid() else { return false; }

    st.file = f;
    st.min_level_rank = log_level_rank(opts.min_level);
    st.format_code = log_format_code(opts.format);
    st.auto_flush = opts.auto_flush;
    st.also_stderr = opts.also_stderr;
    st.utc = opts.utc;
    st.include_process_info = opts.include_process_info;
    st.ui_events = opts.log_ui_events;
    st.max_file_bytes = opts.max_file_bytes;
    st.max_backups = if opts.max_backups >= 0 { opts.max_backups } else { 0 };

    let sz, sz_ok = f.size();
    if st.format_code == 1 {
        if !opts.append || !sz_ok || sz == 0 {
            if !log_init_new_array_file(st) {
                log_state_close(st);
                return false;
            }
        } else {
            if !log_scan_existing_array(st, sz) {
                log_state_close(st);
                return false;
            }
        }
    } else {
        st.file.seek(0, win32::FILE_END);
        st.written_bytes = if sz_ok { sz } else { 0 };
        st.has_array_entries = false;
        st.array_end_pos = 0;
    }
    return true;
}

fn log_state_rotate(st: LogState&, path: const u8[:]) -> bool {
    guard path.len > 0 else { return false; }
    log_state_close(st);

    if st.max_backups > 0 {
        let oldest = str(path, ".", st.max_backups);
        if win32::file_exists(oldest) {
            win32::delete_file(oldest);
        }
        var k: i32 = st.max_backups - 1;
        while k >= 1 {
            let src = str(path, ".", k);
            if win32::file_exists(src) {
                win32::move_file(src, str(path, ".", k + 1), true);
            }
            k -= 1;
        }
        if win32::file_exists(path) {
            win32::move_file(path, str(path, ".1"), true);
        }
    }

    let f = log_open_handle(path, false);
    guard f.is_valid() else { return false; }
    st.file = f;

    if st.format_code == 1 {
        return log_init_new_array_file(st);
    }
    st.written_bytes = 0;
    st.has_array_entries = false;
    st.array_end_pos = 0;
    return true;
}

// --- Structured JSON Field & Array Builders ---------------------------------

struct LogFields {
    out: u8[>..]&,
    start_len: i64 = 0,
    is_root_fields: bool = true,
}

struct LogArray {
    out: u8[>..]&,
    start_len: i64 = 0,
}

fn field_prefix(f: LogFields, key: const u8[:]) {
    if f.is_root_fields {
        if f.out.len == f.start_len {
            f.out.append(",\"fields\":{");
        } else {
            f.out.push(',');
        }
    } else if f.out.len > f.start_len {
        f.out.push(',');
    }
    json::format_key(f.out, key);
}

fn text(f: LogFields, key: const u8[:], val: const u8[:]) -> LogFields {
    field_prefix(f, key);
    json::format_string(f.out, val);
    return f;
}

fn int(f: LogFields, key: const u8[:], val: i64) -> LogFields {
    field_prefix(f, key);
    json::format_int(f.out, val);
    return f;
}

fn uint(f: LogFields, key: const u8[:], val: u64) -> LogFields {
    field_prefix(f, key);
    format(f.out, val);
    return f;
}

fn num(f: LogFields, key: const u8[:], val: f64) -> LogFields {
    field_prefix(f, key);
    json::format_number(f.out, val);
    return f;
}

fn flag(f: LogFields, key: const u8[:], val: bool) -> LogFields {
    field_prefix(f, key);
    json::format_bool(f.out, val);
    return f;
}

fn nil(f: LogFields, key: const u8[:]) -> LogFields {
    field_prefix(f, key);
    f.out.append("null");
    return f;
}

fn raw_json(f: LogFields, key: const u8[:], raw: const u8[:]) -> LogFields {
    field_prefix(f, key);
    f.out.append(raw);
    return f;
}

fn obj<F>(f: LogFields, key: const u8[:]) -> LogFields {
    field_prefix(f, key);
    f.out.push('{');
    let start = f.out.len;
    F(LogFields { out: f.out, start_len: start, is_root_fields: false });
    f.out.push('}');
    return f;
}

fn arr<F>(f: LogFields, key: const u8[:]) -> LogFields {
    field_prefix(f, key);
    f.out.push('[');
    let start = f.out.len;
    F(LogArray { out: f.out, start_len: start });
    f.out.push(']');
    return f;
}

fn window_id(f: LogFields, key: const u8[:], id: WindowId) -> LogFields {
    field_prefix(f, key);
    format(f.out, "{\"index\":", id.index, ",\"gen\":", id.gen, "}");
    return f;
}

fn widget_id(f: LogFields, key: const u8[:], id: WidgetId) -> LogFields {
    field_prefix(f, key);
    format(f.out, "{\"index\":", id.index, ",\"gen\":", id.gen, "}");
    return f;
}

fn rect(f: LogFields, key: const u8[:], r: RectF) -> LogFields {
    field_prefix(f, key);
    f.out.append("{\"x\":");
    json::format_number(f.out, r.x);
    f.out.append(",\"y\":");
    json::format_number(f.out, r.y);
    f.out.append(",\"w\":");
    json::format_number(f.out, r.w);
    f.out.append(",\"h\":");
    json::format_number(f.out, r.h);
    f.out.push('}');
    return f;
}

fn color(f: LogFields, key: const u8[:], c: Color) -> LogFields {
    field_prefix(f, key);
    f.out.append("{\"r\":");
    json::format_number(f.out, c.r);
    f.out.append(",\"g\":");
    json::format_number(f.out, c.g);
    f.out.append(",\"b\":");
    json::format_number(f.out, c.b);
    f.out.append(",\"a\":");
    json::format_number(f.out, c.a);
    f.out.push('}');
    return f;
}

fn arr_prefix(a: LogArray) {
    if a.out.len > a.start_len {
        a.out.push(',');
    }
}

fn text(a: LogArray, val: const u8[:]) -> LogArray {
    arr_prefix(a);
    json::format_string(a.out, val);
    return a;
}

fn int(a: LogArray, val: i64) -> LogArray {
    arr_prefix(a);
    json::format_int(a.out, val);
    return a;
}

fn uint(a: LogArray, val: u64) -> LogArray {
    arr_prefix(a);
    format(a.out, val);
    return a;
}

fn num(a: LogArray, val: f64) -> LogArray {
    arr_prefix(a);
    json::format_number(a.out, val);
    return a;
}

fn flag(a: LogArray, val: bool) -> LogArray {
    arr_prefix(a);
    json::format_bool(a.out, val);
    return a;
}

fn nil(a: LogArray) -> LogArray {
    arr_prefix(a);
    a.out.append("null");
    return a;
}

fn raw_json(a: LogArray, raw: const u8[:]) -> LogArray {
    arr_prefix(a);
    a.out.append(raw);
    return a;
}

fn obj<F>(a: LogArray) -> LogArray {
    arr_prefix(a);
    a.out.push('{');
    let start = a.out.len;
    F(LogFields { out: a.out, start_len: start, is_root_fields: false });
    a.out.push('}');
    return a;
}

fn arr<F>(a: LogArray) -> LogArray {
    arr_prefix(a);
    a.out.push('[');
    let start = a.out.len;
    F(LogArray { out: a.out, start_len: start });
    a.out.push(']');
    return a;
}

// --- Core Record Formatting & Emission --------------------------------------

fn log_should_emit(st: const LogState&, level_rank: i32) -> bool {
    return (st.file.is_valid() || st.also_stderr) && st.min_level_rank < 6 && level_rank >= st.min_level_rank && level_rank < 6;
}

fn log_begin_record(st: LogState&, out: u8[>..]&, level_rank: i32, target: const u8[:], msg: const u8[:]) {
    st.seq += 1;
    out.append("{\"ts\":\"");
    format_log_timestamp(out, st.utc);
    out.append("\",\"seq\":");
    format(out, st.seq);
    out.append(",\"level\":");
    json::format_string(out, log_level_name_rank(level_rank));
    if target.len > 0 {
        out.append(",\"target\":");
        json::format_string(out, target);
    }
    out.append(",\"msg\":");
    json::format_string(out, msg);
    if st.include_process_info {
        format(out, ",\"pid\":", win32::GetCurrentProcessId(), ",\"tid\":", win32::GetCurrentThreadId());
    }
}

fn log_commit_record(st: LogState&, path: const u8[:], obj_json: const u8[:]) -> bool {
    if st.also_stderr {
        var err_line: u8[>..] = [];
        err_line.append(obj_json);
        err_line.push('\n');
        write_stderr(err_line);
    }
    if !st.file.is_valid() {
        return st.also_stderr;
    }

    if st.max_file_bytes > 0 && st.written_bytes > 0 {
        let extra = if st.format_code == 1 { obj_json.len + 4 } else { obj_json.len + 1 };
        if st.written_bytes + extra > st.max_file_bytes {
            guard log_state_rotate(st, path) else { return false; }
        }
    }

    if st.format_code == 0 {
        var line: u8[>..] = [];
        line.append(obj_json);
        line.push('\n');
        st.file.seek(0, win32::FILE_END);
        guard st.file.write_all(line) else { return false; }
        st.written_bytes += line.len;
        if st.auto_flush { st.file.flush(); }
        return true;
    }

    var chunk: u8[>..] = [];
    if st.has_array_entries {
        chunk.append(",\n  ");
    } else {
        chunk.append("\n  ");
    }
    chunk.append(obj_json);
    chunk.append("\n]\n");

    let _pos, seek_ok = st.file.seek(st.array_end_pos, win32::FILE_BEGIN);
    guard seek_ok && st.file.write_all(chunk) else { return false; }
    st.file.truncate();
    st.array_end_pos = st.array_end_pos + chunk.len - 3;
    st.written_bytes = st.array_end_pos + 3;
    st.has_array_entries = true;
    if st.auto_flush { st.file.flush(); }
    return true;
}

fn log_emit_plain(st: LogState&, path: const u8[:], level_rank: i32, target: const u8[:], msg: const u8[:]) -> bool {
    guard log_should_emit(st, level_rank) else { return false; }
    var buf: u8[>..] = [];
    log_begin_record(st, buf, level_rank, target, msg);
    buf.push('}');
    return log_commit_record(st, path, buf);
}

fn log_emit_with<F>(st: LogState&, path: const u8[:], level_rank: i32, target: const u8[:], msg: const u8[:]) -> bool {
    guard log_should_emit(st, level_rank) else { return false; }
    var buf: u8[>..] = [];
    log_begin_record(st, buf, level_rank, target, msg);
    let fstart = buf.len;
    F(LogFields { out: buf, start_len: fstart, is_root_fields: true });
    if buf.len > fstart {
        buf.push('}');
    }
    buf.push('}');
    return log_commit_record(st, path, buf);
}

// --- Standalone JsonLogger --------------------------------------------------

root struct JsonLogger {
    state: LogState = LogState {},
    path: u8[>..<] = [],
}

fn open(l: JsonLogger&, path: const u8[:], opts: LogOptions) -> bool {
    var pcopy: u8[>..] = [];
    pcopy.append(path);
    guard log_state_open(l.state, pcopy, opts) else { return false; }
    l.path.resize(0);
    l.path.append(pcopy);
    return true;
}

fn open(l: JsonLogger&, path: const u8[:]) -> bool {
    return l.open(path, LogOptions {});
}

fn close(l: JsonLogger&) {
    log_state_close(l.state);
}

fn flush(l: JsonLogger&) -> bool {
    return log_state_flush(l.state);
}

fn is_open(l: const JsonLogger&) -> bool {
    return l.state.file.is_valid();
}

fn log_path(l: const JsonLogger&) -> const u8[:] {
    return l.path;
}

fn set_level(l: JsonLogger&, level: LogLevel) {
    l.state.min_level_rank = log_level_rank(level);
}

fn level(l: const JsonLogger&) -> LogLevel {
    return log_level_from_rank(l.state.min_level_rank);
}

fn set_stderr(l: JsonLogger&, enabled: bool) {
    l.state.also_stderr = enabled;
}

fn set_auto_flush(l: JsonLogger&, enabled: bool) {
    l.state.auto_flush = enabled;
}

fn entry_count(l: const JsonLogger&) -> u64 {
    return l.state.seq;
}

fn bytes_written(l: const JsonLogger&) -> i64 {
    return l.state.written_bytes;
}

fn write(l: JsonLogger&, level: LogLevel, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, log_level_rank(level), target, msg);
}

fn write_with<F>(l: JsonLogger&, level: LogLevel, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, log_level_rank(level), target, msg) { f => F(f); };
}

fn trace(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 0, "", msg);
}

fn trace(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 0, target, msg);
}

fn trace_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 0, target, msg) { f => F(f); };
}

fn debug(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 1, "", msg);
}

fn debug(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 1, target, msg);
}

fn debug_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 1, target, msg) { f => F(f); };
}

fn info(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 2, "", msg);
}

fn info(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 2, target, msg);
}

fn info_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 2, target, msg) { f => F(f); };
}

fn warn(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 3, "", msg);
}

fn warn(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 3, target, msg);
}

fn warn_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 3, target, msg) { f => F(f); };
}

fn error(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 4, "", msg);
}

fn error(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 4, target, msg);
}

fn error_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 4, target, msg) { f => F(f); };
}

fn fatal(l: JsonLogger&, msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 5, "", msg);
}

fn fatal(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_plain(l.state, l.path, 5, target, msg);
}

fn fatal_with<F>(l: JsonLogger&, target: const u8[:], msg: const u8[:]) -> bool {
    return log_emit_with(l.state, l.path, 5, target, msg) { f => F(f); };
}

// --- App-Integrated Logging API ---------------------------------------------

fn log_open(app: App&, path: const u8[:], opts: LogOptions) -> bool {
    var pcopy: u8[>..] = [];
    pcopy.append(path);
    guard log_state_open(app.log, pcopy, opts) else { return false; }
    str_set(app.str_pool, app.log_path_span, pcopy);
    return true;
}

fn log_open(app: App&, path: const u8[:]) -> bool {
    return app.log_open(path, LogOptions {});
}

fn log_close(app: App&) {
    log_state_close(app.log);
}

fn log_flush(app: App&) -> bool {
    return log_state_flush(app.log);
}

fn log_is_open(app: const App&) -> bool {
    return app.log.file.is_valid();
}

fn log_path(app: const App&) -> const u8[:] {
    return app.str_view(app.log_path_span);
}

fn log_set_level(app: App&, level: LogLevel) {
    app.log.min_level_rank = log_level_rank(level);
}

fn log_level(app: const App&) -> LogLevel {
    return log_level_from_rank(app.log.min_level_rank);
}

fn log_set_stderr(app: App&, enabled: bool) {
    app.log.also_stderr = enabled;
}

fn log_set_auto_flush(app: App&, enabled: bool) {
    app.log.auto_flush = enabled;
}

fn log_set_ui_events(app: App&, enabled: bool) {
    app.log.ui_events = enabled;
}

fn log_count(app: const App&) -> u64 {
    return app.log.seq;
}

fn log_bytes_written(app: const App&) -> i64 {
    return app.log.written_bytes;
}

fn log_msg(app: App&, level: LogLevel, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, log_level_rank(level), target, msg);
}

fn log_with<F>(app: App&, level: LogLevel, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, log_level_rank(level), target, msg) { f => F(f); };
}

fn log_trace(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 0, "", msg);
}

fn log_trace(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 0, target, msg);
}

fn log_trace_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 0, target, msg) { f => F(f); };
}

fn log_debug(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 1, "", msg);
}

fn log_debug(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 1, target, msg);
}

fn log_debug_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 1, target, msg) { f => F(f); };
}

fn log_info(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 2, "", msg);
}

fn log_info(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 2, target, msg);
}

fn log_info_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 2, target, msg) { f => F(f); };
}

fn log_warn(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 3, "", msg);
}

fn log_warn(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 3, target, msg);
}

fn log_warn_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 3, target, msg) { f => F(f); };
}

fn log_error(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 4, "", msg);
}

fn log_error(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 4, target, msg);
}

fn log_error_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 4, target, msg) { f => F(f); };
}

fn log_fatal(app: App&, msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 5, "", msg);
}

fn log_fatal(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_plain(app.log, p, 5, target, msg);
}

fn log_fatal_with<F>(app: App&, target: const u8[:], msg: const u8[:]) -> bool {
    let p = app.str_view(app.log_path_span);
    return log_emit_with(app.log, p, 5, target, msg) { f => F(f); };
}

// --- Automatic / Manual UI Signal Logging -----------------------------------

fn log_wv_span(app: const App&, sp: StrSpan) -> const u8[:] {
    if sp.len <= 0 || sp.off < 0 || sp.off + sp.len > app.webview_msg_pool.len {
        return "";
    }
    return app.webview_msg_pool[sp.off..sp.off + sp.len];
}

fn log_signal(app: App&, sig: Signal) {
    guard log_should_emit(app.log, 1) else { return; }

    var sig_name: const u8[:] = "";
    var win = WINDOW_NONE;
    var wid = WIDGET_NONE;
    var has_widget = false;

    match sig {
        None => { return; },
        Clicked s => { sig_name = "Clicked"; win = s.window; wid = s.widget; has_widget = true; },
        DoubleClicked s => { sig_name = "DoubleClicked"; win = s.window; wid = s.widget; has_widget = true; },
        Toggled s => { sig_name = "Toggled"; win = s.window; wid = s.widget; has_widget = true; },
        ValueChanged s => { sig_name = "ValueChanged"; win = s.window; wid = s.widget; has_widget = true; },
        TextChanged s => { sig_name = "TextChanged"; win = s.window; wid = s.widget; has_widget = true; },
        TextSubmitted s => { sig_name = "TextSubmitted"; win = s.window; wid = s.widget; has_widget = true; },
        SelectionChanged s => { sig_name = "SelectionChanged"; win = s.window; wid = s.widget; has_widget = true; },
        ItemActivated s => { sig_name = "ItemActivated"; win = s.window; wid = s.widget; has_widget = true; },
        TabChanged s => { sig_name = "TabChanged"; win = s.window; wid = s.widget; has_widget = true; },
        FocusChanged s => { sig_name = "FocusChanged"; win = s.window; wid = s.widget; has_widget = true; },
        ActionTriggered s => { sig_name = "ActionTriggered"; win = s.window; },
        TimerFired s => { sig_name = "TimerFired"; win = s.window; },
        KeyPressed s => { sig_name = "KeyPressed"; win = s.window; wid = s.widget; has_widget = true; },
        CanvasMouseDown s => { sig_name = "CanvasMouseDown"; win = s.window; wid = s.widget; has_widget = true; },
        CanvasMouseMove s => { sig_name = "CanvasMouseMove"; win = s.window; wid = s.widget; has_widget = true; },
        CanvasMouseUp s => { sig_name = "CanvasMouseUp"; win = s.window; wid = s.widget; has_widget = true; },
        CanvasWheel s => { sig_name = "CanvasWheel"; win = s.window; wid = s.widget; has_widget = true; },
        FilesDropped s => { sig_name = "FilesDropped"; win = s.window; },
        WindowResized s => { sig_name = "WindowResized"; win = s.window; },
        WindowClosed s => { sig_name = "WindowClosed"; win = s.window; },
        LocaleChanged _s => { sig_name = "LocaleChanged"; },
        WebViewReady s => { sig_name = "WebViewReady"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewInitFailed s => { sig_name = "WebViewInitFailed"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewNavigationStarting s => { sig_name = "WebViewNavigationStarting"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewNavigationCompleted s => { sig_name = "WebViewNavigationCompleted"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewTitleChanged s => { sig_name = "WebViewTitleChanged"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewSourceChanged s => { sig_name = "WebViewSourceChanged"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewHistoryChanged s => { sig_name = "WebViewHistoryChanged"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewMessageReceived s => { sig_name = "WebViewMessageReceived"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewScriptResult s => { sig_name = "WebViewScriptResult"; win = s.window; wid = s.widget; has_widget = true; },
        WebViewNewWindowRequested s => { sig_name = "WebViewNewWindowRequested"; win = s.window; wid = s.widget; has_widget = true; },
    }

    var buf: u8[>..] = [];
    log_begin_record(app.log, buf, 1, "goose_ui.signal", sig_name);
    let fstart = buf.len;
    let f = LogFields { out: buf, start_len: fstart, is_root_fields: true };
    f.text("signal", sig_name);
    if win.is_valid() {
        f.window_id("window", win);
    }
    if has_widget && wid.is_valid() {
        f.widget_id("widget", wid);
        if app.valid_widget(wid) {
            let wname = app.str_view(app.widgets[wid.index].name);
            if wname.len > 0 {
                f.text("widget_name", wname);
            }
            let aid = app.widgets[wid.index].tag;
            if aid != 0 {
                f.int("action_id", aid);
            }
        }
    }

    match sig {
        Toggled s => { f.flag("checked", s.checked); },
        ValueChanged s => { f.num("value", s.value); },
        SelectionChanged s => { f.int("index", s.index); },
        ItemActivated s => { f.int("index", s.index); },
        TabChanged s => { f.int("index", s.index); },
        FocusChanged s => { f.flag("focused", s.focused); },
        ActionTriggered s => { f.uint("action_id", s.action_id); },
        TimerFired s => { f.uint("timer_id", s.timer_id); },
        KeyPressed s => { f.uint("key", s.key); f.uint("mods", s.mods); },
        CanvasMouseDown s => { f.num("x", s.x); f.num("y", s.y); f.int("button", s.button); },
        CanvasMouseMove s => { f.num("x", s.x); f.num("y", s.y); },
        CanvasMouseUp s => { f.num("x", s.x); f.num("y", s.y); f.int("button", s.button); },
        CanvasWheel s => { f.num("x", s.x); f.num("y", s.y); f.int("delta", s.delta); },
        FilesDropped s => { f.int("count", s.count); },
        WindowResized s => { f.int("width", s.width); f.int("height", s.height); },
        LocaleChanged s => {
            f.int("locale_index", s.locale_index);
            if s.locale_index >= 0 && s.locale_index < app.i18n_locales.len {
                let sp = app.i18n_locales[s.locale_index].code;
                if sp.len > 0 && sp.off >= 0 && sp.off + sp.len <= app.i18n_pool.len {
                    f.text("locale", app.i18n_pool[sp.off..sp.off + sp.len]);
                }
            }
        },
        WebViewInitFailed s => { f.int("hr", s.hr); },
        WebViewNavigationStarting s => {
            f.flag("user_initiated", s.user_initiated);
            f.flag("redirected", s.redirected);
            if s.payload >= 0 && s.payload < app.webview_payloads.len {
                let u = log_wv_span(app, app.webview_payloads[s.payload].text);
                if u.len > 0 { f.text("url", u); }
            }
        },
        WebViewNavigationCompleted s => { f.flag("success", s.success); f.int("error_status", s.error_status); },
        WebViewSourceChanged s => { f.flag("is_new_document", s.is_new_document); },
        WebViewHistoryChanged s => { f.flag("can_go_back", s.can_go_back); f.flag("can_go_forward", s.can_go_forward); },
        WebViewMessageReceived s => {
            f.flag("is_json", s.is_json);
            if s.payload >= 0 && s.payload < app.webview_payloads.len {
                let msg = log_wv_span(app, app.webview_payloads[s.payload].text);
                if msg.len > 0 { f.text("payload", msg); }
                let src = log_wv_span(app, app.webview_payloads[s.payload].aux);
                if src.len > 0 { f.text("source", src); }
            }
        },
        WebViewScriptResult s => {
            f.uint("request_id", s.request_id);
            f.flag("ok", s.ok);
            if s.payload >= 0 && s.payload < app.webview_payloads.len {
                let res = log_wv_span(app, app.webview_payloads[s.payload].text);
                if res.len > 0 { f.text("result", res); }
            }
        },
        WebViewNewWindowRequested s => {
            f.flag("user_initiated", s.user_initiated);
            if s.payload >= 0 && s.payload < app.webview_payloads.len {
                let u = log_wv_span(app, app.webview_payloads[s.payload].text);
                if u.len > 0 { f.text("url", u); }
            }
        },
        _ => {},
    }

    if buf.len > fstart { buf.push('}'); }
    buf.push('}');
    let path = app.str_view(app.log_path_span);
    log_commit_record(app.log, path, buf);
}

// --- JSON Log Reader --------------------------------------------------------

fn fill_log_entry_view(node: json::Node?, raw: const u8[:]) -> LogEntryView {
    var entry = LogEntryView { raw_json: raw };
    let ts_s, ts_ok = json::as_string(json::member(node, "ts"));
    if ts_ok { entry.ts = ts_s; }
    let seq_v, seq_ok = json::as_i64(json::member(node, "seq"));
    if seq_ok { entry.seq = seq_v; }
    let lvl_s, lvl_ok = json::as_string(json::member(node, "level"));
    if lvl_ok {
        entry.level_text = lvl_s;
        let parsed_lvl, parsed_ok = parse_log_level(lvl_s);
        if parsed_ok { entry.level = parsed_lvl; }
    }
    let tgt_s, tgt_ok = json::as_string(json::member(node, "target"));
    if tgt_ok { entry.target = tgt_s; }
    let msg_s, msg_ok = json::as_string(json::member(node, "msg"));
    if msg_ok { entry.msg = msg_s; }
    let pid_v, pid_ok = json::as_i64(json::member(node, "pid"));
    if pid_ok { entry.pid = pid_v; }
    let tid_v, tid_ok = json::as_i64(json::member(node, "tid"));
    if tid_ok { entry.tid = tid_v; }
    return entry;
}

fn each_json_log_entry<F>(path: const u8[:]) -> i64, bool {
    var content: u8[>..] = [];
    guard win32::read_file_bytes(path, content) else { return 0, false; }
    let trimmed = trim(content);
    if trimmed.len == 0 { return 0, true; }

    if trimmed[0] == '[' {
        var doc: json::Node[>..] = [];
        var decoded: u8[>..] = [];
        let root, _err = json::parse(trimmed, doc, decoded);
        guard root else { return 0, false; }
        match root.val {
            Arr => {},
            _ => { return 0, false; },
        }
        var count: i64 = 0;
        json::each(root) { item =>
            count += 1;
            F(fill_log_entry_view(item, ""));
        };
        return count, true;
    }

    var count: i64 = 0;
    var pos: i64 = 0;
    while pos < trimmed.len {
        var nl = pos;
        while nl < trimmed.len && trimmed[nl] != '\n' {
            nl += 1;
        }
        let line = trim(trimmed[pos..nl]);
        pos = if nl < trimmed.len { nl + 1 } else { nl };
        if line.len == 0 { continue; }

        var doc: json::Node[>..] = [];
        var decoded: u8[>..] = [];
        let root, _err = json::parse(line, doc, decoded);
        guard root else { return count, false; }
        count += 1;
        F(fill_log_entry_view(root, line));
    }
    return count, true;
}
