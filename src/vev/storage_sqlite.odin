// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import c "core:c"
import "core:fmt"
import "core:strings"

sqlite_attr_serializable_text :: proc(attr: string) -> string {
    if strings.has_prefix(attr, ":") {
        return attr
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    _ = strings.write_byte(&builder, '"')
    for ch in transmute([]byte)attr {
        switch ch {
        case '"':
            _ = strings.write_string(&builder, "\\\"")
        case '\\':
            _ = strings.write_string(&builder, "\\\\")
        case:
            _ = strings.write_byte(&builder, ch)
        }
    }
    _ = strings.write_byte(&builder, '"')
    out, _ := strings.clone(strings.to_string(builder))
    return out
}

when ODIN_OS == .Windows {
    foreign import sqlite "system:sqlite3.lib"
} else {
    foreign import sqlite "system:sqlite3"
}

SQLite3 :: struct {}
SQLite3_Stmt :: struct {}

SQLITE_OK :: c.int(0)
SQLITE_ROW :: c.int(100)
SQLITE_DONE :: c.int(101)
SQLITE_TRANSIENT :: rawptr(~uintptr(0))

@(default_calling_convention="c")
foreign sqlite {
    sqlite3_open :: proc(filename: cstring, db: ^^SQLite3) -> c.int ---
    sqlite3_open_v2 :: proc(filename: cstring, db: ^^SQLite3, flags: c.int, vfs: cstring) -> c.int ---
    sqlite3_close :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_close_v2 :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_get_autocommit :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_errmsg :: proc(db: ^SQLite3) -> cstring ---
    sqlite3_errcode :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_extended_errcode :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_exec :: proc(db: ^SQLite3, sql: cstring, callback: rawptr, arg: rawptr, errmsg: ^^c.char) -> c.int ---
    sqlite3_free :: proc(ptr: rawptr) ---
    sqlite3_prepare_v2 :: proc(db: ^SQLite3, sql: cstring, nbytes: c.int, stmt: ^^SQLite3_Stmt, tail: ^cstring) -> c.int ---
    sqlite3_finalize :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_reset :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_clear_bindings :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_step :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_bind_null :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> c.int ---
    sqlite3_bind_text :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: cstring, nbytes: c.int, destructor: rawptr) -> c.int ---
    sqlite3_bind_text64 :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: cstring, nbytes: u64, destructor: rawptr, encoding: u8) -> c.int ---
    sqlite3_bind_blob64 :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: rawptr, nbytes: u64, destructor: rawptr) -> c.int ---
    sqlite3_bind_int64 :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: i64) -> c.int ---
    sqlite3_bind_int :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: c.int) -> c.int ---
    sqlite3_bind_double :: proc(stmt: ^SQLite3_Stmt, idx: c.int, value: f64) -> c.int ---
    sqlite3_bind_parameter_count :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_bind_parameter_index :: proc(stmt: ^SQLite3_Stmt, name: cstring) -> c.int ---
    sqlite3_bind_parameter_name :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> cstring ---
    sqlite3_column_count :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_column_name :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> cstring ---
    sqlite3_column_type :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> c.int ---
    sqlite3_column_text :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> cstring ---
    sqlite3_column_blob :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> rawptr ---
    sqlite3_column_bytes :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> c.int ---
    sqlite3_column_int :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> c.int ---
    sqlite3_column_int64 :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> i64 ---
    sqlite3_column_double :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> f64 ---
    sqlite3_last_insert_rowid :: proc(db: ^SQLite3) -> i64 ---
    sqlite3_changes :: proc(db: ^SQLite3) -> c.int ---
    sqlite3_changes64 :: proc(db: ^SQLite3) -> i64 ---
    sqlite3_total_changes64 :: proc(db: ^SQLite3) -> i64 ---
    sqlite3_busy_timeout :: proc(db: ^SQLite3, milliseconds: c.int) -> c.int ---
    sqlite3_interrupt :: proc(db: ^SQLite3) ---
    sqlite3_stmt_readonly :: proc(stmt: ^SQLite3_Stmt) -> c.int ---
    sqlite3_libversion :: proc() -> cstring ---
    sqlite3_sourceid :: proc() -> cstring ---
    sqlite3_compileoption_used :: proc(option: cstring) -> c.int ---
}

SQLITE_OPEN_READONLY :: c.int(0x00000001)
SQLITE_OPEN_READWRITE :: c.int(0x00000002)
SQLITE_OPEN_CREATE :: c.int(0x00000004)
SQLITE_OPEN_URI :: c.int(0x00000040)
SQLITE_OPEN_MEMORY :: c.int(0x00000080)
SQLITE_OPEN_NOMUTEX :: c.int(0x00008000)
SQLITE_OPEN_FULLMUTEX :: c.int(0x00010000)
SQLITE_UTF8 :: u8(1)

sqlite_app_is_vev_store :: proc(db: ^SQLite3) -> bool {
    table_stmt: ^SQLite3_Stmt
    table_sql := cstring("SELECT 1 FROM sqlite_schema WHERE type='table' AND name='vev_meta' LIMIT 1")
    if sqlite3_prepare_v2(db, table_sql, -1, &table_stmt, nil) != SQLITE_OK {
        return false
    }
    has_meta := sqlite3_step(table_stmt) == SQLITE_ROW
    _ = sqlite3_finalize(table_stmt)
    if !has_meta {
        return false
    }

    marker_stmt: ^SQLite3_Stmt
    marker_sql := cstring("SELECT 1 FROM vev_meta WHERE (key='schema-version' AND value='1') OR (key='storage-architecture' AND value LIKE 'vev-%') LIMIT 1")
    if sqlite3_prepare_v2(db, marker_sql, -1, &marker_stmt, nil) != SQLITE_OK {
        return false
    }
    is_vev := sqlite3_step(marker_stmt) == SQLITE_ROW
    _ = sqlite3_finalize(marker_stmt)
    return is_vev
}

sqlite_app_open_raw :: proc(path: string, flags: c.int) -> (rawptr, c.int, string) {
    db: ^SQLite3
    path_c, path_c_ok := sqlite_cstring(path)
    if !path_c_ok {
        error, _ := strings.clone("failed to allocate sqlite path")
        return nil, c.int(7), error
    }
    defer delete(path_c)
    rc := sqlite3_open_v2(path_c, &db, flags, nil)
    if rc != SQLITE_OK {
        error := sqlite_error_text(db, "sqlite open failed")
        return rawptr(db), rc, error
    }
    if sqlite_app_is_vev_store(db) {
        _ = sqlite3_close_v2(db)
        error, _ := strings.clone("raw SQLite access to a VevDB store is not allowed")
        return nil, c.int(23), error
    }
    return rawptr(db), SQLITE_OK, ""
}

sqlite_app_close_raw :: proc(handle: rawptr) -> c.int {
    if handle == nil {
        return SQLITE_OK
    }
    return sqlite3_close_v2((^SQLite3)(handle))
}

sqlite_app_error_code_raw :: proc(handle: rawptr) -> c.int {
    if handle == nil {
        return c.int(21)
    }
    return sqlite3_errcode((^SQLite3)(handle))
}

sqlite_app_extended_error_code_raw :: proc(handle: rawptr) -> c.int {
    if handle == nil {
        return c.int(21)
    }
    return sqlite3_extended_errcode((^SQLite3)(handle))
}

sqlite_app_error_raw :: proc(handle: rawptr) -> string {
    return sqlite_error_text((^SQLite3)(handle), "invalid sqlite database handle")
}

sqlite_app_exec_raw :: proc(handle: rawptr, sql: string) -> c.int {
    if handle == nil {
        return c.int(21)
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return c.int(7)
    }
    defer delete(sql_c)
    return sqlite3_exec((^SQLite3)(handle), sql_c, nil, nil, nil)
}

sqlite_app_prepare_raw :: proc(handle: rawptr, sql: string) -> (rawptr, c.int) {
    if handle == nil {
        return nil, c.int(21)
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, c.int(7)
    }
    defer delete(sql_c)
    stmt: ^SQLite3_Stmt
    rc := sqlite3_prepare_v2((^SQLite3)(handle), sql_c, -1, &stmt, nil)
    return rawptr(stmt), rc
}

sqlite_app_finalize_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return SQLITE_OK
    }
    return sqlite3_finalize((^SQLite3_Stmt)(stmt))
}

sqlite_app_reset_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_reset((^SQLite3_Stmt)(stmt))
}

sqlite_app_clear_bindings_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_clear_bindings((^SQLite3_Stmt)(stmt))
}

sqlite_app_step_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_step((^SQLite3_Stmt)(stmt))
}

sqlite_app_bind_null_raw :: proc(stmt: rawptr, index: c.int) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_bind_null((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_bind_int64_raw :: proc(stmt: rawptr, index: c.int, value: i64) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_bind_int64((^SQLite3_Stmt)(stmt), index, value)
}

sqlite_app_bind_double_raw :: proc(stmt: rawptr, index: c.int, value: f64) -> c.int {
    if stmt == nil {
        return c.int(21)
    }
    return sqlite3_bind_double((^SQLite3_Stmt)(stmt), index, value)
}

sqlite_app_bind_text_raw :: proc(stmt: rawptr, index: c.int, data: rawptr, length: u64) -> c.int {
    if stmt == nil || (data == nil && length > 0) {
        return c.int(21)
    }
    if length == 0 {
        return sqlite3_bind_text64((^SQLite3_Stmt)(stmt), index, cstring(""), 0, SQLITE_TRANSIENT, SQLITE_UTF8)
    }
    return sqlite3_bind_text64((^SQLite3_Stmt)(stmt), index, cstring(data), length, SQLITE_TRANSIENT, SQLITE_UTF8)
}

sqlite_app_bind_blob_raw :: proc(stmt: rawptr, index: c.int, data: rawptr, length: u64) -> c.int {
    if stmt == nil || (data == nil && length > 0) {
        return c.int(21)
    }
    if length == 0 {
        empty: byte
        return sqlite3_bind_blob64((^SQLite3_Stmt)(stmt), index, rawptr(&empty), 0, SQLITE_TRANSIENT)
    }
    return sqlite3_bind_blob64((^SQLite3_Stmt)(stmt), index, data, length, SQLITE_TRANSIENT)
}

sqlite_app_bind_parameter_count_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return 0
    }
    return sqlite3_bind_parameter_count((^SQLite3_Stmt)(stmt))
}

sqlite_app_bind_parameter_index_raw :: proc(stmt: rawptr, name: string) -> c.int {
    if stmt == nil {
        return 0
    }
    name_c, name_c_ok := sqlite_cstring(name)
    if !name_c_ok {
        return 0
    }
    defer delete(name_c)
    return sqlite3_bind_parameter_index((^SQLite3_Stmt)(stmt), name_c)
}

sqlite_app_bind_parameter_name_raw :: proc(stmt: rawptr, index: c.int) -> string {
    if stmt == nil {
        return ""
    }
    name := sqlite3_bind_parameter_name((^SQLite3_Stmt)(stmt), index)
    if name == nil {
        return ""
    }
    out, err := strings.clone_from_cstring(name)
    if err != nil {
        return ""
    }
    return out
}

sqlite_app_column_count_raw :: proc(stmt: rawptr) -> c.int {
    if stmt == nil {
        return 0
    }
    return sqlite3_column_count((^SQLite3_Stmt)(stmt))
}

sqlite_app_column_name_raw :: proc(stmt: rawptr, index: c.int) -> string {
    if stmt == nil {
        return ""
    }
    name := sqlite3_column_name((^SQLite3_Stmt)(stmt), index)
    if name == nil {
        return ""
    }
    out, err := strings.clone_from_cstring(name)
    if err != nil {
        return ""
    }
    return out
}

sqlite_app_column_type_raw :: proc(stmt: rawptr, index: c.int) -> c.int {
    if stmt == nil {
        return 5
    }
    return sqlite3_column_type((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_column_int64_raw :: proc(stmt: rawptr, index: c.int) -> i64 {
    if stmt == nil {
        return 0
    }
    return sqlite3_column_int64((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_column_double_raw :: proc(stmt: rawptr, index: c.int) -> f64 {
    if stmt == nil {
        return 0.0
    }
    return sqlite3_column_double((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_column_text_raw :: proc(stmt: rawptr, index: c.int) -> rawptr {
    if stmt == nil {
        return nil
    }
    return rawptr(sqlite3_column_text((^SQLite3_Stmt)(stmt), index))
}

sqlite_app_column_blob_raw :: proc(stmt: rawptr, index: c.int) -> rawptr {
    if stmt == nil {
        return nil
    }
    return sqlite3_column_blob((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_column_bytes_raw :: proc(stmt: rawptr, index: c.int) -> c.int {
    if stmt == nil {
        return 0
    }
    return sqlite3_column_bytes((^SQLite3_Stmt)(stmt), index)
}

sqlite_app_changes_raw :: proc(handle: rawptr) -> i64 {
    if handle == nil {
        return 0
    }
    return sqlite3_changes64((^SQLite3)(handle))
}

sqlite_app_total_changes_raw :: proc(handle: rawptr) -> i64 {
    if handle == nil {
        return 0
    }
    return sqlite3_total_changes64((^SQLite3)(handle))
}

sqlite_app_last_insert_rowid_raw :: proc(handle: rawptr) -> i64 {
    if handle == nil {
        return 0
    }
    return sqlite3_last_insert_rowid((^SQLite3)(handle))
}

sqlite_app_autocommit_raw :: proc(handle: rawptr) -> bool {
    if handle == nil {
        return false
    }
    return sqlite3_get_autocommit((^SQLite3)(handle)) != 0
}

sqlite_app_busy_timeout_raw :: proc(handle: rawptr, milliseconds: c.int) -> c.int {
    if handle == nil || milliseconds < 0 {
        return c.int(21)
    }
    return sqlite3_busy_timeout((^SQLite3)(handle), milliseconds)
}

sqlite_app_interrupt_raw :: proc(handle: rawptr) {
    if handle != nil {
        sqlite3_interrupt((^SQLite3)(handle))
    }
}

sqlite_app_stmt_readonly_raw :: proc(stmt: rawptr) -> bool {
    if stmt == nil {
        return false
    }
    return sqlite3_stmt_readonly((^SQLite3_Stmt)(stmt)) != 0
}

sqlite_app_version_raw :: proc() -> string {
    out, err := strings.clone_from_cstring(sqlite3_libversion())
    if err != nil {
        return ""
    }
    return out
}

sqlite_app_source_id_raw :: proc() -> string {
    out, err := strings.clone_from_cstring(sqlite3_sourceid())
    if err != nil {
        return ""
    }
    return out
}

sqlite_app_compile_option_used_raw :: proc(option: string) -> bool {
    option_c, option_c_ok := sqlite_cstring(option)
    if !option_c_ok {
        return false
    }
    defer delete(option_c)
    return sqlite3_compileoption_used(option_c) != 0
}

sqlite_column_text_owned :: proc(stmt: ^SQLite3_Stmt, idx: c.int) -> (string, bool) {
    raw := sqlite3_column_text(stmt, idx)
    if raw == nil {
        return "", false
    }
    byte_count := sqlite3_column_bytes(stmt, idx)
    if byte_count < 0 {
        return "", false
    }
    out, err := strings.clone_from_ptr((^byte)(raw), int(byte_count))
    if err != nil {
        return "", false
    }
    return out, true
}

sqlite_error_text :: proc(db: ^SQLite3, fallback: string) -> string {
    if db == nil {
        return fallback
    }
    msg := sqlite3_errmsg(db)
    if msg == nil {
        return fallback
    }
    out, err := strings.clone_from_cstring(msg)
    if err != nil {
        return fallback
    }
    return out
}

sqlite_cstring :: proc(text: string) -> (cstring, bool) {
    out, err := strings.clone_to_cstring(text)
    if err != nil {
        return cstring(""), false
    }
    return out, true
}

sqlite_bind_text_borrowed :: proc(stmt: ^SQLite3_Stmt, idx: c.int, text: string) -> c.int {
    if len(text) == 0 {
        return sqlite3_bind_text(stmt, idx, cstring(""), 0, SQLITE_TRANSIENT)
    }
    return sqlite3_bind_text(stmt, idx, cstring(raw_data(text)), c.int(len(text)), SQLITE_TRANSIENT)
}

sqlite_exec_ok :: proc(db: ^SQLite3, sql: string) -> (bool, string) {
    errmsg: ^c.char = nil
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    rc := sqlite3_exec(db, sql_c, nil, nil, &errmsg)
    if rc == SQLITE_OK {
        return true, ""
    }
    if errmsg != nil {
        text, err := strings.clone_from_cstring(cstring(errmsg))
        sqlite3_free(rawptr(errmsg))
        if err == nil {
            return false, text
        }
    }
    return false, sqlite_error_text(db, "sqlite exec failed")
}
