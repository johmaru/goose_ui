// Zero-heap, pure-Goose internationalization (i18n) subsystem for goose_ui.
// Supports code-registered catalogs, flat & nested JSON, multi-locale bundles,
// directory scanning (*.json), Windows OS locale detection, BCP-47 hierarchical
// fallback, named & positional template interpolation, live widget re-translation,
// and standalone Translator usage.
namespace goose_ui;

import std;
import json;
import win32 from "./win32-goose";
import types;
import widget;
import tree;
import events;

extern "kernel32" {
    fn GetUserDefaultLocaleName(buf: u16&, cch: i32) -> i32;
}

// --- OS Locale Detection ----------------------------------------------------

// Returns the active Windows user locale in BCP-47 form (e.g. "ja-JP", "en-US").
fn system_locale() -> u8[>..] {
    var wbuf: u16[85] = [0; 85];
    let n = GetUserDefaultLocaleName(wbuf[0], 85);
    if n > 0 {
        let s = win32::utf16_to_utf8(wbuf[..]);
        if s.len > 0 {
            return s;
        }
    }
    return str("en");
}

// Returns the lowercase primary language subtag of the OS locale (e.g. "ja", "en").
fn system_language() -> u8[>..] {
    let full = system_locale();
    var out: u8[>..] = [];
    for i in full.len {
        let c = full[i];
        if c == '-' || c == '_' { break; }
        if c >= 'A' && c <= 'Z' {
            out.push(c + 32);
        } else {
            out.push(c);
        }
    }
    if out.len == 0 {
        out.append("en");
    }
    return out;
}

// --- Pool, ASCII & BCP-47 Normalization Helpers -----------------------------

fn i18n_pool_view(pool: const u8[:], s: StrSpan) -> const u8[:] {
    if s.len <= 0 || s.off < 0 || s.off + s.len > pool.len {
        return "";
    }
    return pool[s.off..s.off + s.len];
}

fn i18n_ascii_lower(c: u8) -> u8 {
    if c >= 'A' && c <= 'Z' { return c + 32; }
    return c;
}

fn i18n_ascii_upper(c: u8) -> u8 {
    if c >= 'a' && c <= 'z' { return c - 32; }
    return c;
}

fn i18n_is_ascii_alpha(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn i18n_eq_nocase(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        if i18n_ascii_lower(a[i]) != i18n_ascii_lower(b[i]) { return false; }
    }
    return true;
}

fn i18n_ends_with_nocase(s: const u8[:], suffix: const u8[:]) -> bool {
    if suffix.len > s.len { return false; }
    let off = s.len - suffix.len;
    for i in suffix.len {
        if i18n_ascii_lower(s[off + i]) != i18n_ascii_lower(suffix[i]) {
            return false;
        }
    }
    return true;
}

fn i18n_bytes_lt(a: const u8[:], b: const u8[:]) -> bool {
    let n = if a.len < b.len { a.len } else { b.len };
    for i in n {
        if a[i] != b[i] {
            return a[i] < b[i];
        }
    }
    return a.len < b.len;
}

// Normalizes e.g. "ja_jp" -> "ja-JP", "zh_hans_cn" -> "zh-Hans-CN", "EN" -> "en".
fn i18n_normalize_code(raw: const u8[:], out: u8[>..]&) {
    out.clear();
    let s = trim(raw);
    if s.len == 0 { return; }

    var seg_idx: i32 = 0;
    var i: i64 = 0;
    while i < s.len {
        while i < s.len && (s[i] == '-' || s[i] == '_') {
            i += 1;
        }
        if i >= s.len { break; }
        let start = i;
        while i < s.len && s[i] != '-' && s[i] != '_' {
            i += 1;
        }
        let seg = s[start..i];
        if seg.len == 0 { continue; }
        if seg_idx > 0 { out.push('-'); }

        var all_alpha = true;
        for k in seg.len {
            if !i18n_is_ascii_alpha(seg[k]) {
                all_alpha = false;
                break;
            }
        }

        if seg_idx == 0 {
            for k in seg.len { out.push(i18n_ascii_lower(seg[k])); }
        } else if seg.len == 2 && all_alpha {
            for k in seg.len { out.push(i18n_ascii_upper(seg[k])); }
        } else if seg.len == 4 && all_alpha {
            out.push(i18n_ascii_upper(seg[0]));
            for k in 1..seg.len { out.push(i18n_ascii_lower(seg[k])); }
        } else {
            for k in seg.len { out.push(i18n_ascii_lower(seg[k])); }
        }
        seg_idx += 1;
    }
}

fn i18n_base_lang(code: const u8[:]) -> const u8[:] {
    for i in code.len {
        if code[i] == '-' || code[i] == '_' {
            return code[..i];
        }
    }
    return "";
}

// FNV-1a 64-bit hash combining locale index and UTF-8 key bytes.
fn i18n_hash_key(locale_idx: i32, key: const u8[:]) -> u64 {
    var h: u64 = 14695981039346656037;
    var li = locale_idx as! u32;
    for _ in 4 {
        h ^= li & 0xFF;
        h *= 1099511628211;
        li >>= 8;
    }
    h ^= 0xFF;
    h *= 1099511628211;
    for i in key.len {
        h ^= key[i];
        h *= 1099511628211;
    }
    return h;
}

// --- Shared Zero-Heap Catalog Core ------------------------------------------

fn i18n_cat_rehash(entries: const I18nEntry[:], buckets: i32[>..<]&, new_cap: i64) {
    buckets.resize(0);
    buckets.resize(new_cap, -1);
    let mask = new_cap - 1;
    for ei in entries.len {
        var slot = (entries[ei].key_hash & (mask as! u64)) as! i64;
        while buckets[slot] >= 0 {
            slot = (slot + 1) & mask;
        }
        buckets[slot] = ei as! i32;
    }
}

fn i18n_cat_ensure_bucket_room(entries: const I18nEntry[:], buckets: i32[>..<]&) {
    if buckets.len == 0 {
        i18n_cat_rehash(entries, buckets, 64);
    } else if (entries.len + 1) * 3 > buckets.len * 2 {
        i18n_cat_rehash(entries, buckets, buckets.len * 2);
    }
}

fn i18n_cat_find_entry(
    pool: const u8[:],
    entries: const I18nEntry[:],
    buckets: const i32[:],
    locale_idx: i32,
    key: const u8[:]
) -> i64 {
    if buckets.len == 0 || locale_idx < 0 { return -1; }
    let h = i18n_hash_key(locale_idx, key);
    let mask = buckets.len - 1;
    var slot = (h & (mask as! u64)) as! i64;
    loop {
        let ei = buckets[slot];
        if ei < 0 { return -1; }
        if entries[ei].locale_idx == locale_idx &&
           entries[ei].key_hash == h &&
           i18n_pool_view(pool, entries[ei].key) == key {
            return ei;
        }
        slot = (slot + 1) & mask;
    }
}

fn i18n_cat_find_exact_locale(pool: const u8[:], locales: const I18nLocale[:], code: const u8[:]) -> i32 {
    for i in locales.len {
        if i18n_eq_nocase(i18n_pool_view(pool, locales[i].code), code) {
            return i as! i32;
        }
    }
    return -1;
}

fn i18n_cat_relink_parents(pool: const u8[:], locales: I18nLocale[>..]& ) {
    for i in locales.len {
        let code = i18n_pool_view(pool, locales[i].code);
        let base = i18n_base_lang(code);
        if base.len > 0 {
            locales[i].parent_idx = i18n_cat_find_exact_locale(pool, locales, base);
        } else {
            locales[i].parent_idx = -1;
        }
    }
}

fn i18n_cat_match_locale(pool: const u8[:], locales: const I18nLocale[:], raw_code: const u8[:]) -> i32 {
    var norm: u8[>..] = [];
    i18n_normalize_code(raw_code, norm);
    if norm.len == 0 { return -1; }

    // 1. Exact code match (case-insensitive)
    let exact = i18n_cat_find_exact_locale(pool, locales, norm);
    if exact >= 0 { return exact; }

    // 2. Match base language against registered locale (e.g. "ja-JP" -> "ja")
    let base = i18n_base_lang(norm);
    let q_lang = if base.len > 0 { base } else { norm };
    let base_idx = i18n_cat_find_exact_locale(pool, locales, q_lang);
    if base_idx >= 0 { return base_idx; }

    // 3. Match registered regional locale sharing the same base language (e.g. "ja" -> "ja-JP")
    for i in locales.len {
        let lc = i18n_pool_view(pool, locales[i].code);
        let lbase = i18n_base_lang(lc);
        let target_lang = if lbase.len > 0 { lbase } else { lc };
        if i18n_eq_nocase(target_lang, q_lang) {
            return i as! i32;
        }
    }
    return -1;
}

fn i18n_cat_register_locale(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    active: i32&,
    fallback: i32&,
    raw_code: const u8[:],
    display_name: const u8[:] = ""
) -> i32 {
    var norm: u8[>..] = [];
    i18n_normalize_code(raw_code, norm);
    guard norm.len > 0 else { return -1; }

    var dname: u8[>..] = [];
    dname.append(trim(display_name));

    let existing = i18n_cat_find_exact_locale(pool, locales, norm);
    if existing >= 0 {
        if dname.len > 0 {
            str_set(pool, locales[existing].display_name, dname);
        }
        return existing;
    }

    var loc = I18nLocale {};
    str_set(pool, loc.code, norm);
    if dname.len > 0 {
        str_set(pool, loc.display_name, dname);
    } else {
        str_set(pool, loc.display_name, norm);
    }
    let idx = locales.len as! i32;
    locales.push(loc);
    i18n_cat_relink_parents(pool, locales);

    if active < 0 { active = idx; }
    if fallback < 0 { fallback = idx; }
    return idx;
}

fn i18n_cat_put(
    pool: u8[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    locale_idx: i32,
    key: const u8[:],
    val: const u8[:]
) -> bool {
    guard locale_idx >= 0 && key.len > 0 else { return false; }

    var kcopy: u8[>..] = [];
    kcopy.append(key);
    var vcopy: u8[>..] = [];
    vcopy.append(val);

    let existing = i18n_cat_find_entry(pool, entries, buckets, locale_idx, kcopy);
    if existing >= 0 {
        str_set(pool, entries[existing].val, vcopy);
        return true;
    }

    i18n_cat_ensure_bucket_room(entries, buckets);
    let h = i18n_hash_key(locale_idx, kcopy);
    var entry = I18nEntry {
        locale_idx: locale_idx,
        key_hash: h,
    };
    str_set(pool, entry.key, kcopy);
    str_set(pool, entry.val, vcopy);
    let ei = entries.len as! i32;
    entries.push(entry);

    let mask = buckets.len - 1;
    var slot = (h & (mask as! u64)) as! i64;
    while buckets[slot] >= 0 {
        slot = (slot + 1) & mask;
    }
    buckets[slot] = ei;
    return true;
}

fn i18n_cat_lookup_chain(
    pool: const u8[:],
    locales: const I18nLocale[:],
    entries: const I18nEntry[:],
    buckets: const i32[:],
    loc_idx: i32,
    fallback_idx: i32,
    key: const u8[:]
) -> const u8[:], bool {
    if key.len == 0 { return key, false; }

    if loc_idx >= 0 && loc_idx < locales.len {
        let ei = i18n_cat_find_entry(pool, entries, buckets, loc_idx, key);
        if ei >= 0 { return i18n_pool_view(pool, entries[ei].val), true; }

        let parent = locales[loc_idx].parent_idx;
        if parent >= 0 && parent < locales.len {
            let pei = i18n_cat_find_entry(pool, entries, buckets, parent, key);
            if pei >= 0 { return i18n_pool_view(pool, entries[pei].val), true; }
        }
    }

    if fallback_idx >= 0 && fallback_idx < locales.len && fallback_idx != loc_idx {
        let fei = i18n_cat_find_entry(pool, entries, buckets, fallback_idx, key);
        if fei >= 0 { return i18n_pool_view(pool, entries[fei].val), true; }

        let fparent = locales[fallback_idx].parent_idx;
        if fparent >= 0 && fparent < locales.len && fparent != loc_idx {
            let fpei = i18n_cat_find_entry(pool, entries, buckets, fparent, key);
            if fpei >= 0 { return i18n_pool_view(pool, entries[fpei].val), true; }
        }
    }

    return key, false;
}

// --- Iterative Flat & Nested JSON Loader ------------------------------------

struct I18nJsonFrame {
    cur: json::Node? = null,
    prefix_len: i64 = 0,
}

fn i18n_cat_load_json_object(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    raw_code: const u8[:],
    obj_node: json::Node?
) -> bool {
    guard obj_node else { return false; }
    match obj_node.val {
        Obj => {},
        _ => { return false; },
    }

    let loc_idx = i18n_cat_register_locale(pool, locales, active, fallback, raw_code);
    guard loc_idx >= 0 else { return false; }

    var stack: I18nJsonFrame[>..<] = [];
    var prefix: u8[>..] = [];
    stack.push(I18nJsonFrame { cur: obj_node.first, prefix_len: 0 });

    while stack.len > 0 {
        let top = stack.len - 1;
        let node = stack[top].cur;
        let pfx_len = stack[top].prefix_len;
        if !node {
            stack.pop();
            if stack.len > 0 {
                prefix.resize(stack[stack.len - 1].prefix_len);
            } else {
                prefix.resize(0);
            }
            continue;
        }

        // Advance sibling before descending so popped frames resume at next member.
        stack[top] = I18nJsonFrame { cur: node.next, prefix_len: pfx_len };
        if node.key.len == 0 {
            prefix.resize(pfx_len);
            continue;
        }

        if pfx_len == 0 && node.key == "_locale_name" {
            let dn, dn_ok = json::as_string(node);
            if dn_ok && trim(dn).len > 0 {
                str_set(pool, locales[loc_idx].display_name, trim(dn));
            }
            prefix.resize(0);
            continue;
        }
        if pfx_len == 0 && node.key == "_meta" {
            let mn, mn_ok = json::as_string(json::member(node, "name"));
            if mn_ok && trim(mn).len > 0 {
                str_set(pool, locales[loc_idx].display_name, trim(mn));
            }
            prefix.resize(0);
            continue;
        }

        if pfx_len > 0 {
            prefix.push('.');
        }
        prefix.append(node.key);

        match node.val {
            Str s => {
                i18n_cat_put(pool, entries, buckets, loc_idx, prefix, s.s);
                prefix.resize(pfx_len);
            },
            Int iv => {
                var vbuf: u8[>..] = [];
                format(vbuf, iv.v);
                i18n_cat_put(pool, entries, buckets, loc_idx, prefix, vbuf);
                prefix.resize(pfx_len);
            },
            Num nv => {
                var vbuf: u8[>..] = [];
                format(vbuf, nv.v);
                i18n_cat_put(pool, entries, buckets, loc_idx, prefix, vbuf);
                prefix.resize(pfx_len);
            },
            Bool bv => {
                i18n_cat_put(pool, entries, buckets, loc_idx, prefix, if bv.v { "true" } else { "false" });
                prefix.resize(pfx_len);
            },
            Obj => {
                stack.push(I18nJsonFrame { cur: node.first, prefix_len: prefix.len });
            },
            _ => {
                prefix.resize(pfx_len);
            },
        }
    }
    return true;
}

fn i18n_cat_load_json_str(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    raw_code: const u8[:],
    json_text: const u8[:]
) -> bool {
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, _err = json::parse(json_text, doc, decoded);
    guard root else { return false; }
    return i18n_cat_load_json_object(pool, locales, entries, buckets, active, fallback, raw_code, root);
}

fn i18n_cat_load_json_file(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    raw_code: const u8[:],
    path: const u8[:]
) -> bool {
    var bytes: u8[>..] = [];
    guard win32::read_file_bytes(path, bytes) else { return false; }
    return i18n_cat_load_json_str(pool, locales, entries, buckets, active, fallback, raw_code, bytes);
}

fn i18n_cat_load_bundle_json_str(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    json_text: const u8[:]
) -> bool {
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, _err = json::parse(json_text, doc, decoded);
    guard root else { return false; }
    match root.val {
        Obj => {},
        _ => { return false; },
    }
    var loaded: i32 = 0;
    var child = root.first;
    while child {
        let sub_key = child.key;
        if sub_key.len > 0 && sub_key[0] != '_' {
            if i18n_cat_load_json_object(pool, locales, entries, buckets, active, fallback, sub_key, child) {
                loaded += 1;
            }
        }
        child .= child.next;
    }
    return loaded > 0;
}

fn i18n_cat_load_bundle_json_file(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    path: const u8[:]
) -> bool {
    var bytes: u8[>..] = [];
    guard win32::read_file_bytes(path, bytes) else { return false; }
    return i18n_cat_load_bundle_json_str(pool, locales, entries, buckets, active, fallback, bytes);
}

struct I18nDirFile {
    name: u8[..260] = [],
}

fn i18n_cat_load_dir(
    pool: u8[>..]&,
    locales: I18nLocale[>..]&,
    entries: I18nEntry[>..]&,
    buckets: i32[>..<]&,
    active: i32&,
    fallback: i32&,
    dir_path: const u8[:]
) -> i32 {
    guard dir_path.len > 0 && win32::dir_exists(dir_path) else { return 0; }

    var base: u8[>..] = [];
    base.append(dir_path);
    while base.len > 0 && (base[base.len - 1] == '\\' || base[base.len - 1] == '/') {
        base.pop();
    }
    guard base.len > 0 else { return 0; }

    var files: I18nDirFile[>..<] = [];
    var fname: u8[>..] = [];
    var info = win32::FileInfo {};
    let hf = win32::find_first_file(str(base, "\\*"), fname, info);
    if hf.is_valid() {
        loop {
            if !info.is_directory() && fname.len > 5 && i18n_ends_with_nocase(fname, ".json") {
                var item = I18nDirFile {};
                copy_str(item.name, fname);
                if item.name == fname {
                    files.push(item);
                }
            }
            fname.clear();
            if !hf.next(fname, info) { break; }
        }
        hf.close();
    }

    // Insertion sort filenames for deterministic load ordering.
    for i in 1..files.len {
        let cur = files[i];
        var j = i - 1;
        while j >= 0 && i18n_bytes_lt(cur.name, files[j].name) {
            files[j + 1] = files[j];
            j -= 1;
        }
        files[j + 1] = cur;
    }

    var count: i32 = 0;
    for i in files.len {
        let fn_s = files[i].name;
        let stem = fn_s[..fn_s.len - 5];
        let full = str(base, "\\", fn_s);
        if i18n_cat_load_json_file(pool, locales, entries, buckets, active, fallback, stem, full) {
            count += 1;
        }
    }
    return count;
}

// --- Template Interpolation Engine ------------------------------------------

struct I18nArgSlot {
    name: StrSpan = StrSpan {},
    val: StrSpan = StrSpan {},
}

struct I18nArgs {
    pool: u8[>..]&,
    items: I18nArgSlot[>..]&,
}

fn i18n_push_arg(a: I18nArgs, name: const u8[:], val: const u8[:]) -> I18nArgs {
    var slot = I18nArgSlot {};
    str_set(a.pool, slot.name, name);
    str_set(a.pool, slot.val, val);
    a.items.push(slot);
    return a;
}

fn text(a: I18nArgs, name: const u8[:], val: const u8[:]) -> I18nArgs {
    return i18n_push_arg(a, name, val);
}

fn int(a: I18nArgs, name: const u8[:], val: i64) -> I18nArgs {
    var buf: u8[>..] = [];
    format(buf, val);
    return i18n_push_arg(a, name, buf);
}

fn uint(a: I18nArgs, name: const u8[:], val: u64) -> I18nArgs {
    var buf: u8[>..] = [];
    format(buf, val);
    return i18n_push_arg(a, name, buf);
}

fn num(a: I18nArgs, name: const u8[:], val: f64, decimals: i32 = 1) -> I18nArgs {
    var buf: u8[>..] = [];
    if decimals <= 0 {
        let iv = (if val >= 0.0 { val + 0.5 } else { val - 0.5 }) as! i64;
        format(buf, iv);
    } else {
        format_flt(buf, val, decimals);
    }
    return i18n_push_arg(a, name, buf);
}

fn i18n_render_template(
    tmpl: const u8[:],
    arg_pool: const u8[:],
    items: const I18nArgSlot[:],
    out: u8[>..]&
) {
    var i: i64 = 0;
    while i < tmpl.len {
        let c = tmpl[i];
        if c == '{' {
            if i + 1 < tmpl.len && tmpl[i + 1] == '{' {
                out.push('{');
                i += 2;
                continue;
            }
            var j = i + 1;
            var found_close = false;
            while j < tmpl.len {
                if tmpl[j] == '}' {
                    found_close = true;
                    break;
                }
                if tmpl[j] == '{' { break; }
                j += 1;
            }
            if found_close && j > i + 1 {
                let pname = tmpl[i + 1..j];
                var matched = false;
                for k in items.len {
                    if i18n_pool_view(arg_pool, items[k].name) == pname {
                        out.append(i18n_pool_view(arg_pool, items[k].val));
                        matched = true;
                        break;
                    }
                }
                if matched {
                    i = j + 1;
                    continue;
                }
            }
            out.push('{');
            i += 1;
        } else if c == '}' && i + 1 < tmpl.len && tmpl[i + 1] == '}' {
            out.push('}');
            i += 2;
        } else {
            out.push(c);
            i += 1;
        }
    }
}

// --- App-Integrated i18n Catalog & Locale Control ---------------------------

fn i18n_register_locale(app: App&, code: const u8[:], display_name: const u8[:] = "") -> i32 {
    return i18n_cat_register_locale(app.i18n_pool, app.i18n_locales, app.i18n_active, app.i18n_fallback, code, display_name);
}

fn i18n_add(app: App&, locale_code: const u8[:], key: const u8[:], text: const u8[:]) -> bool {
    let loc_idx = i18n_cat_register_locale(app.i18n_pool, app.i18n_locales, app.i18n_active, app.i18n_fallback, locale_code);
    guard loc_idx >= 0 else { return false; }
    return i18n_cat_put(app.i18n_pool, app.i18n_entries, app.i18n_buckets, loc_idx, key, text);
}

fn i18n_load_json_str(app: App&, locale_code: const u8[:], json_text: const u8[:]) -> bool {
    return i18n_cat_load_json_str(app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets, app.i18n_active, app.i18n_fallback, locale_code, json_text);
}

fn i18n_load_json_file(app: App&, locale_code: const u8[:], path: const u8[:]) -> bool {
    return i18n_cat_load_json_file(app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets, app.i18n_active, app.i18n_fallback, locale_code, path);
}

fn i18n_load_bundle_json_str(app: App&, json_text: const u8[:]) -> bool {
    return i18n_cat_load_bundle_json_str(app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets, app.i18n_active, app.i18n_fallback, json_text);
}

fn i18n_load_bundle_json_file(app: App&, path: const u8[:]) -> bool {
    return i18n_cat_load_bundle_json_file(app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets, app.i18n_active, app.i18n_fallback, path);
}

fn i18n_load_dir(app: App&, dir_path: const u8[:]) -> i32 {
    return i18n_cat_load_dir(app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets, app.i18n_active, app.i18n_fallback, dir_path);
}

fn i18n_clear(app: App&) {
    app.i18n_active = -1;
    app.i18n_fallback = -1;
    app.i18n_pool.clear();
    app.i18n_locales.clear();
    app.i18n_entries.clear();
    app.i18n_buckets.clear();
}

fn set_fallback_locale(app: App&, code: const u8[:]) -> bool {
    let idx = i18n_cat_match_locale(app.i18n_pool, app.i18n_locales, code);
    guard idx >= 0 else { return false; }
    app.i18n_fallback = idx;
    return true;
}

fn fallback_locale(app: const App&) -> const u8[:] {
    if app.i18n_fallback < 0 || app.i18n_fallback >= app.i18n_locales.len { return ""; }
    return i18n_pool_view(app.i18n_pool, app.i18n_locales[app.i18n_fallback].code);
}

fn locale(app: const App&) -> const u8[:] {
    if app.i18n_active < 0 || app.i18n_active >= app.i18n_locales.len { return ""; }
    return i18n_pool_view(app.i18n_pool, app.i18n_locales[app.i18n_active].code);
}

fn locale_display_name(app: const App&) -> const u8[:] {
    if app.i18n_active < 0 || app.i18n_active >= app.i18n_locales.len { return ""; }
    return i18n_pool_view(app.i18n_pool, app.i18n_locales[app.i18n_active].display_name);
}

fn locale_count(app: const App&) -> i32 {
    return app.i18n_locales.len as! i32;
}

fn locale_code(app: const App&, index: i32) -> const u8[:] {
    if index < 0 || index >= app.i18n_locales.len { return ""; }
    return i18n_pool_view(app.i18n_pool, app.i18n_locales[index].code);
}

fn locale_name_at(app: const App&, index: i32) -> const u8[:] {
    if index < 0 || index >= app.i18n_locales.len { return ""; }
    return i18n_pool_view(app.i18n_pool, app.i18n_locales[index].display_name);
}

fn has_locale(app: const App&, code: const u8[:]) -> bool {
    return i18n_cat_match_locale(app.i18n_pool, app.i18n_locales, code) >= 0;
}

// --- App Lookup & Template Formatting ---------------------------------------

fn tr(app: const App&, key: const u8[:]) -> const u8[:] {
    let val, _ok = i18n_cat_lookup_chain(
        app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets,
        app.i18n_active, app.i18n_fallback, key
    );
    return val;
}

fn tr_or(app: const App&, key: const u8[:], default_text: const u8[:]) -> const u8[:] {
    let val, ok = i18n_cat_lookup_chain(
        app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets,
        app.i18n_active, app.i18n_fallback, key
    );
    return if ok { val } else { default_text };
}

fn tr_for(app: const App&, locale_code: const u8[:], key: const u8[:]) -> const u8[:] {
    let idx = i18n_cat_match_locale(app.i18n_pool, app.i18n_locales, locale_code);
    let val, _ok = i18n_cat_lookup_chain(
        app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets,
        idx, app.i18n_fallback, key
    );
    return val;
}

fn has_tr(app: const App&, key: const u8[:]) -> bool {
    let _val, ok = i18n_cat_lookup_chain(
        app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets,
        app.i18n_active, app.i18n_fallback, key
    );
    return ok;
}

fn tr_fmt<F>(app: const App&, key: const u8[:]) -> u8[>..] {
    var pool: u8[>..] = [];
    var items: I18nArgSlot[>..] = [];
    F(I18nArgs { pool: pool, items: items });
    let tmpl = app.tr(key);
    var out: u8[>..] = [];
    i18n_render_template(tmpl, pool, items, out);
    return out;
}

fn tr1(app: const App&, key: const u8[:], a0: const u8[:]) -> u8[>..] {
    return app.tr_fmt(key) { f => f.text("0", a0); };
}

fn tr2(app: const App&, key: const u8[:], a0: const u8[:], a1: const u8[:]) -> u8[>..] {
    return app.tr_fmt(key) { f => f.text("0", a0).text("1", a1); };
}

fn tr3(app: const App&, key: const u8[:], a0: const u8[:], a1: const u8[:], a2: const u8[:]) -> u8[>..] {
    return app.tr_fmt(key) { f => f.text("0", a0).text("1", a1).text("2", a2); };
}

// --- Live Retranslation & Binding Lifecycle ---------------------------------

fn retranslate_all(app: App&) {
    var val_buf: u8[>..] = [];
    var any_dead = false;

    for i in app.i18n_bindings.len {
        if !app.i18n_bindings[i].alive { continue; }
        let b = app.i18n_bindings[i];

        if b.target_kind == I18N_TARGET_WINDOW_TITLE || b.target_kind == I18N_TARGET_STATUS_BAR {
            if !app.valid_window(b.window) {
                app.i18n_bindings[i].alive = false;
                any_dead = true;
                continue;
            }
        } else {
            if !app.valid_widget(b.widget) {
                app.i18n_bindings[i].alive = false;
                any_dead = true;
                continue;
            }
        }

        let key = i18n_pool_view(app.i18n_pool, b.key);
        let translated, _ok = i18n_cat_lookup_chain(
            app.i18n_pool, app.i18n_locales, app.i18n_entries, app.i18n_buckets,
            app.i18n_active, app.i18n_fallback, key
        );
        val_buf.clear();
        val_buf.append(translated);

        if b.target_kind == I18N_TARGET_WIDGET_TEXT {
            set_widget_text_raw(app, b.widget, val_buf);
        } else if b.target_kind == I18N_TARGET_WIDGET_PLACEHOLDER {
            set_widget_placeholder_raw(app, b.widget, val_buf);
        } else if b.target_kind == I18N_TARGET_WIDGET_TOOLTIP {
            set_widget_tooltip_raw(app, b.widget, val_buf);
        } else if b.target_kind == I18N_TARGET_LIST_ITEM_TEXT {
            if find_item_by_uid(app, b.widget, b.item_uid) < 0 {
                app.i18n_bindings[i].alive = false;
                any_dead = true;
            } else {
                set_list_item_text_by_uid_raw(app, b.widget, b.item_uid, val_buf);
            }
        } else if b.target_kind == I18N_TARGET_LIST_ITEM_SUBTEXT {
            if find_item_by_uid(app, b.widget, b.item_uid) < 0 {
                app.i18n_bindings[i].alive = false;
                any_dead = true;
            } else {
                set_list_item_subtext_by_uid_raw(app, b.widget, b.item_uid, val_buf);
            }
        } else if b.target_kind == I18N_TARGET_WINDOW_TITLE {
            set_window_title_raw(app, b.window, val_buf);
        } else if b.target_kind == I18N_TARGET_STATUS_BAR {
            set_status_text_raw(app, b.window, val_buf);
        }
    }

    if any_dead {
        compact_i18n_bindings(app);
    }

    for i in app.windows.len {
        if app.windows[i].alive {
            if !app.windows[i].headless && app.windows[i].gl2d.is_valid() {
                app.windows[i].gl2d.clear_text_cache();
            }
            app.windows[i].layout_dirty = true;
            app.windows[i].dirty = true;
        }
    }
}

fn set_locale(app: App&, code: const u8[:]) -> bool {
    let idx = i18n_cat_match_locale(app.i18n_pool, app.i18n_locales, code);
    guard idx >= 0 else { return false; }
    let changed = idx != app.i18n_active;
    app.i18n_active = idx;
    if changed {
        app.retranslate_all();
        app.push_signal(Signal.LocaleChanged { locale_index: idx });
    }
    return true;
}

fn set_system_locale(app: App&, fallback_code: const u8[:] = "en") -> bool {
    let sys = system_locale();
    if app.set_locale(sys) { return true; }
    let lang = system_language();
    if app.set_locale(lang) { return true; }
    if fallback_code.len > 0 {
        return app.set_locale(fallback_code);
    }
    return false;
}

fn i18n_upsert_binding(
    app: App&,
    target_kind: u8,
    win: WindowId,
    widget: WidgetId,
    item_uid: u64,
    key: const u8[:]
) {
    var kcopy: u8[>..] = [];
    kcopy.append(key);

    var free_slot: i64 = -1;
    for i in app.i18n_bindings.len {
        if !app.i18n_bindings[i].alive {
            if free_slot < 0 { free_slot = i; }
            continue;
        }
        if app.i18n_bindings[i].target_kind == target_kind &&
           app.i18n_bindings[i].item_uid == item_uid &&
           eq(app.i18n_bindings[i].widget, widget) &&
           eq(app.i18n_bindings[i].window, win) {
            str_set(app.i18n_pool, app.i18n_bindings[i].key, kcopy);
            return;
        }
    }

    if free_slot >= 0 {
        var b = app.i18n_bindings[free_slot];
        b.alive = true;
        b.target_kind = target_kind;
        b.window = win;
        b.widget = widget;
        b.item_uid = item_uid;
        str_set(app.i18n_pool, b.key, kcopy);
        app.i18n_bindings[free_slot] = b;
        return;
    }

    var nb = I18nBinding {
        alive: true,
        target_kind: target_kind,
        window: win,
        widget: widget,
        item_uid: item_uid,
    };
    str_set(app.i18n_pool, nb.key, kcopy);
    app.i18n_bindings.push(nb);
}

fn set_tr_text(app: App&, id: WidgetId, key: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    let win = app.widgets[id.index].window;
    i18n_upsert_binding(app, I18N_TARGET_WIDGET_TEXT, win, id, 0, key);
    var vbuf: u8[>..] = [];
    vbuf.append(app.tr(key));
    set_widget_text_raw(app, id, vbuf);
}

fn set_tr_placeholder(app: App&, id: WidgetId, key: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    let win = app.widgets[id.index].window;
    i18n_upsert_binding(app, I18N_TARGET_WIDGET_PLACEHOLDER, win, id, 0, key);
    var vbuf: u8[>..] = [];
    vbuf.append(app.tr(key));
    set_widget_placeholder_raw(app, id, vbuf);
}

fn set_tr_tooltip(app: App&, id: WidgetId, key: const u8[:]) {
    guard app.valid_widget(id) else { return; }
    let win = app.widgets[id.index].window;
    i18n_upsert_binding(app, I18N_TARGET_WIDGET_TOOLTIP, win, id, 0, key);
    var vbuf: u8[>..] = [];
    vbuf.append(app.tr(key));
    set_widget_tooltip_raw(app, id, vbuf);
}

fn set_tr_window_title(app: App&, win: WindowId, key: const u8[:]) {
    guard app.valid_window(win) else { return; }
    i18n_upsert_binding(app, I18N_TARGET_WINDOW_TITLE, win, WIDGET_NONE, 0, key);
    var vbuf: u8[>..] = [];
    vbuf.append(app.tr(key));
    set_window_title_raw(app, win, vbuf);
}

fn set_tr_status_text(app: App&, win: WindowId, key: const u8[:]) {
    guard app.valid_window(win) else { return; }
    if !app.valid_widget(app.windows[win.index].status_bar) {
        app.set_status_bar(win, "");
    }
    i18n_upsert_binding(app, I18N_TARGET_STATUS_BAR, win, WIDGET_NONE, 0, key);
    var vbuf: u8[>..] = [];
    vbuf.append(app.tr(key));
    set_status_text_raw(app, win, vbuf);
}

fn add_tr_item(
    app: App&,
    owner: WidgetId,
    text_key: const u8[:],
    subtext_key: const u8[:] = "",
    tag: i64 = 0
) -> i32 {
    guard app.valid_widget(owner) else { return -1; }
    var tbuf: u8[>..] = [];
    tbuf.append(app.tr(text_key));
    var sbuf: u8[>..] = [];
    if subtext_key.len > 0 {
        sbuf.append(app.tr(subtext_key));
    }
    let idx = app.add_item(owner, tbuf, sbuf, tag);
    guard idx >= 0 else { return -1; }

    let slot = app.find_nth_item(owner, idx);
    if slot >= 0 {
        let uid = app.list_items[slot].uid;
        let win = app.widgets[owner.index].window;
        i18n_upsert_binding(app, I18N_TARGET_LIST_ITEM_TEXT, win, owner, uid, text_key);
        if subtext_key.len > 0 {
            i18n_upsert_binding(app, I18N_TARGET_LIST_ITEM_SUBTEXT, win, owner, uid, subtext_key);
        }
    }
    return idx;
}

fn add_tr_tab(
    app: App&,
    tab_widget: WidgetId,
    title_key: const u8[:],
    layout: LayoutKind = LayoutKind.VBox,
    spacing: f32 = 10.0,
    padding: f32 = 12.0
) -> WidgetId {
    guard app.valid_widget(tab_widget) else { return WIDGET_NONE; }
    var tbuf: u8[>..] = [];
    tbuf.append(app.tr(title_key));
    let page = app.add_tab(tab_widget, tbuf, layout, spacing, padding);
    guard app.valid_widget(page) else { return WIDGET_NONE; }

    let cnt = app.item_count(tab_widget);
    if cnt > 0 {
        let slot = app.find_nth_item(tab_widget, cnt - 1);
        if slot >= 0 {
            let uid = app.list_items[slot].uid;
            let win = app.widgets[tab_widget.index].window;
            i18n_upsert_binding(app, I18N_TARGET_LIST_ITEM_TEXT, win, tab_widget, uid, title_key);
        }
    }
    return page;
}

fn clear_tr_bindings(app: App&) {
    app.i18n_bindings.clear();
}

// --- Standalone Translator (App-Independent) --------------------------------

root struct Translator {
    active: i32 = -1,
    fallback: i32 = -1,
    pool: u8[>..] = [],
    locales: I18nLocale[>..] = [],
    entries: I18nEntry[>..] = [],
    buckets: i32[>..<] = [],
}

fn register_locale(t: Translator&, code: const u8[:], display_name: const u8[:] = "") -> i32 {
    return i18n_cat_register_locale(t.pool, t.locales, t.active, t.fallback, code, display_name);
}

fn add(t: Translator&, locale_code: const u8[:], key: const u8[:], text: const u8[:]) -> bool {
    let loc_idx = i18n_cat_register_locale(t.pool, t.locales, t.active, t.fallback, locale_code);
    guard loc_idx >= 0 else { return false; }
    return i18n_cat_put(t.pool, t.entries, t.buckets, loc_idx, key, text);
}

fn load_json_str(t: Translator&, locale_code: const u8[:], json_text: const u8[:]) -> bool {
    return i18n_cat_load_json_str(t.pool, t.locales, t.entries, t.buckets, t.active, t.fallback, locale_code, json_text);
}

fn load_json_file(t: Translator&, locale_code: const u8[:], path: const u8[:]) -> bool {
    return i18n_cat_load_json_file(t.pool, t.locales, t.entries, t.buckets, t.active, t.fallback, locale_code, path);
}

fn load_bundle_json_str(t: Translator&, json_text: const u8[:]) -> bool {
    return i18n_cat_load_bundle_json_str(t.pool, t.locales, t.entries, t.buckets, t.active, t.fallback, json_text);
}

fn load_bundle_json_file(t: Translator&, path: const u8[:]) -> bool {
    return i18n_cat_load_bundle_json_file(t.pool, t.locales, t.entries, t.buckets, t.active, t.fallback, path);
}

fn load_dir(t: Translator&, dir_path: const u8[:]) -> i32 {
    return i18n_cat_load_dir(t.pool, t.locales, t.entries, t.buckets, t.active, t.fallback, dir_path);
}

fn clear(t: Translator&) {
    t.active = -1;
    t.fallback = -1;
    t.pool.clear();
    t.locales.clear();
    t.entries.clear();
    t.buckets.clear();
}

fn set_fallback(t: Translator&, code: const u8[:]) -> bool {
    let idx = i18n_cat_match_locale(t.pool, t.locales, code);
    guard idx >= 0 else { return false; }
    t.fallback = idx;
    return true;
}

fn fallback(t: const Translator&) -> const u8[:] {
    if t.fallback < 0 || t.fallback >= t.locales.len { return ""; }
    return i18n_pool_view(t.pool, t.locales[t.fallback].code);
}

fn set_locale(t: Translator&, code: const u8[:]) -> bool {
    let idx = i18n_cat_match_locale(t.pool, t.locales, code);
    guard idx >= 0 else { return false; }
    t.active = idx;
    return true;
}

fn set_system_locale(t: Translator&, fallback_code: const u8[:] = "en") -> bool {
    let sys = system_locale();
    if t.set_locale(sys) { return true; }
    let lang = system_language();
    if t.set_locale(lang) { return true; }
    if fallback_code.len > 0 {
        return t.set_locale(fallback_code);
    }
    return false;
}

fn locale(t: const Translator&) -> const u8[:] {
    if t.active < 0 || t.active >= t.locales.len { return ""; }
    return i18n_pool_view(t.pool, t.locales[t.active].code);
}

fn locale_count(t: const Translator&) -> i32 {
    return t.locales.len as! i32;
}

fn locale_code(t: const Translator&, index: i32) -> const u8[:] {
    if index < 0 || index >= t.locales.len { return ""; }
    return i18n_pool_view(t.pool, t.locales[index].code);
}

fn locale_name_at(t: const Translator&, index: i32) -> const u8[:] {
    if index < 0 || index >= t.locales.len { return ""; }
    return i18n_pool_view(t.pool, t.locales[index].display_name);
}

fn locale_display_name(t: const Translator&) -> const u8[:] {
    if t.active < 0 || t.active >= t.locales.len { return ""; }
    return i18n_pool_view(t.pool, t.locales[t.active].display_name);
}

fn has_locale(t: const Translator&, code: const u8[:]) -> bool {
    return i18n_cat_match_locale(t.pool, t.locales, code) >= 0;
}

fn tr(t: const Translator&, key: const u8[:]) -> const u8[:] {
    let val, _ok = i18n_cat_lookup_chain(
        t.pool, t.locales, t.entries, t.buckets,
        t.active, t.fallback, key
    );
    return val;
}

fn tr_or(t: const Translator&, key: const u8[:], default_text: const u8[:]) -> const u8[:] {
    let val, ok = i18n_cat_lookup_chain(
        t.pool, t.locales, t.entries, t.buckets,
        t.active, t.fallback, key
    );
    return if ok { val } else { default_text };
}

fn tr_for(t: const Translator&, locale_code: const u8[:], key: const u8[:]) -> const u8[:] {
    let idx = i18n_cat_match_locale(t.pool, t.locales, locale_code);
    let val, _ok = i18n_cat_lookup_chain(
        t.pool, t.locales, t.entries, t.buckets,
        idx, t.fallback, key
    );
    return val;
}

fn has_tr(t: const Translator&, key: const u8[:]) -> bool {
    let _val, ok = i18n_cat_lookup_chain(
        t.pool, t.locales, t.entries, t.buckets,
        t.active, t.fallback, key
    );
    return ok;
}

fn tr_fmt<F>(t: const Translator&, key: const u8[:]) -> u8[>..] {
    var pool: u8[>..] = [];
    var items: I18nArgSlot[>..] = [];
    F(I18nArgs { pool: pool, items: items });
    let tmpl = t.tr(key);
    var out: u8[>..] = [];
    i18n_render_template(tmpl, pool, items, out);
    return out;
}

fn tr1(t: const Translator&, key: const u8[:], a0: const u8[:]) -> u8[>..] {
    return t.tr_fmt(key) { f => f.text("0", a0); };
}

fn tr2(t: const Translator&, key: const u8[:], a0: const u8[:], a1: const u8[:]) -> u8[>..] {
    return t.tr_fmt(key) { f => f.text("0", a0).text("1", a1); };
}

fn tr3(t: const Translator&, key: const u8[:], a0: const u8[:], a1: const u8[:], a2: const u8[:]) -> u8[>..] {
    return t.tr_fmt(key) { f => f.text("0", a0).text("1", a1).text("2", a2); };
}
