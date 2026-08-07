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

sqlite_set_synchronous_native_raw :: proc(handle: rawptr, level: c.int) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    sql := "PRAGMA synchronous = NORMAL"
    if level == 2 {
        sql = "PRAGMA synchronous = FULL"
    } else if level == 0 {
        sql = "PRAGMA synchronous = OFF"
    }
    return sqlite_exec_ok((^SQLite3)(handle), sql)
}

sqlite_schema_sql :: `
PRAGMA busy_timeout = 5000;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
CREATE TABLE IF NOT EXISTS vev_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS vev_snapshots (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS vev_transactions (
  tx INTEGER PRIMARY KEY
);
CREATE TABLE IF NOT EXISTS vev_tx_meta (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tx INTEGER NOT NULL,
  a TEXT NOT NULL,
  value_text TEXT NOT NULL,
  FOREIGN KEY(tx) REFERENCES vev_transactions(tx)
);
CREATE TABLE IF NOT EXISTS vev_datoms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  log_index INTEGER NOT NULL DEFAULT -1,
  e INTEGER NOT NULL,
  a TEXT NOT NULL,
  value_text TEXT NOT NULL,
  value_entity INTEGER NOT NULL DEFAULT -1,
  tx INTEGER NOT NULL,
  added INTEGER NOT NULL,
  FOREIGN KEY(tx) REFERENCES vev_transactions(tx)
);
CREATE INDEX IF NOT EXISTS vev_tx_meta_tx ON vev_tx_meta(tx, a);
CREATE INDEX IF NOT EXISTS vev_datoms_eavt ON vev_datoms(e, a, value_text, tx, added);
CREATE INDEX IF NOT EXISTS vev_datoms_eavt_entity_cover ON vev_datoms(e, a, value_text, value_entity, tx, added);
CREATE INDEX IF NOT EXISTS vev_datoms_aevt ON vev_datoms(a, e, value_text, tx, added);
CREATE INDEX IF NOT EXISTS vev_datoms_avet ON vev_datoms(a, value_text, e, tx, added);
CREATE INDEX IF NOT EXISTS vev_datoms_vaet ON vev_datoms(value_text, a, e, tx, added);
CREATE TABLE IF NOT EXISTS vev_text_terms (
  attr TEXT NOT NULL,
  term TEXT NOT NULL,
  log_index INTEGER NOT NULL,
  PRIMARY KEY(attr, term, log_index)
);
CREATE INDEX IF NOT EXISTS vev_text_terms_lookup ON vev_text_terms(attr, term, log_index);
CREATE TABLE IF NOT EXISTS vev_index_chunks (
  chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,
  index_name TEXT NOT NULL,
  level INTEGER NOT NULL,
  first_key TEXT NOT NULL,
  last_key TEXT NOT NULL,
  row_count INTEGER NOT NULL,
  child_count INTEGER NOT NULL DEFAULT 0,
  payload_text TEXT NOT NULL,
  checksum TEXT NOT NULL DEFAULT '',
  created_tx INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS vev_index_chunk_edges (
  parent_chunk_id INTEGER NOT NULL,
  child_chunk_id INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY(parent_chunk_id, ordinal),
  FOREIGN KEY(parent_chunk_id) REFERENCES vev_index_chunks(chunk_id),
  FOREIGN KEY(child_chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_chunk_entries (
  chunk_id INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  entry INTEGER NOT NULL,
  PRIMARY KEY(chunk_id, ordinal),
  FOREIGN KEY(chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_roots (
  root_id INTEGER PRIMARY KEY AUTOINCREMENT,
  basis_tx INTEGER NOT NULL,
  format TEXT NOT NULL,
  eavt_chunk_id INTEGER,
  aevt_chunk_id INTEGER,
  avet_chunk_id INTEGER,
  vaet_chunk_id INTEGER,
  eavt_manifest_id INTEGER NOT NULL DEFAULT 0,
  aevt_manifest_id INTEGER NOT NULL DEFAULT 0,
  avet_manifest_id INTEGER NOT NULL DEFAULT 0,
  vaet_manifest_id INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(eavt_chunk_id) REFERENCES vev_index_chunks(chunk_id),
  FOREIGN KEY(aevt_chunk_id) REFERENCES vev_index_chunks(chunk_id),
  FOREIGN KEY(avet_chunk_id) REFERENCES vev_index_chunks(chunk_id),
  FOREIGN KEY(vaet_chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_root_pages (
  root_id INTEGER NOT NULL,
  index_name TEXT NOT NULL,
  root_chunk_id INTEGER NOT NULL,
  manifest_id INTEGER NOT NULL DEFAULT 0,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY(root_id, index_name),
  FOREIGN KEY(root_id) REFERENCES vev_index_roots(root_id),
  FOREIGN KEY(root_chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_run_manifests (
  manifest_id INTEGER PRIMARY KEY AUTOINCREMENT,
  index_name TEXT NOT NULL,
  basis_tx INTEGER NOT NULL,
  parent_manifest_id INTEGER NOT NULL DEFAULT 0,
  base_chunk_id INTEGER NOT NULL,
  row_count INTEGER NOT NULL,
  run_count INTEGER NOT NULL,
  created_tx INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(base_chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_run_manifest_runs (
  manifest_id INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  run_chunk_id INTEGER NOT NULL,
  row_count INTEGER NOT NULL,
  first_e INTEGER NOT NULL DEFAULT 0,
  first_a TEXT NOT NULL DEFAULT '',
  first_value_text TEXT NOT NULL DEFAULT '',
  first_tx INTEGER NOT NULL DEFAULT 0,
  first_added INTEGER NOT NULL DEFAULT 1,
  last_e INTEGER NOT NULL DEFAULT 0,
  last_a TEXT NOT NULL DEFAULT '',
  last_value_text TEXT NOT NULL DEFAULT '',
  last_tx INTEGER NOT NULL DEFAULT 0,
  last_added INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY(manifest_id, ordinal),
  FOREIGN KEY(manifest_id) REFERENCES vev_index_run_manifests(manifest_id),
  FOREIGN KEY(run_chunk_id) REFERENCES vev_index_chunks(chunk_id)
);
CREATE TABLE IF NOT EXISTS vev_index_run_manifest_attr_ranges (
  manifest_id INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  attr TEXT NOT NULL,
  first_ordinal INTEGER NOT NULL DEFAULT -1,
  first_e INTEGER NOT NULL,
  first_value_text TEXT NOT NULL,
  first_tx INTEGER NOT NULL,
  first_added INTEGER NOT NULL,
  last_ordinal INTEGER NOT NULL DEFAULT -1,
  last_e INTEGER NOT NULL,
  last_value_text TEXT NOT NULL,
  last_tx INTEGER NOT NULL,
  last_added INTEGER NOT NULL,
  PRIMARY KEY(manifest_id, ordinal, attr),
  FOREIGN KEY(manifest_id, ordinal) REFERENCES vev_index_run_manifest_runs(manifest_id, ordinal)
);
CREATE TABLE IF NOT EXISTS vev_index_run_manifest_entity_attr_ranges (
  manifest_id INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  order_text TEXT NOT NULL,
  entity INTEGER NOT NULL,
  attr TEXT NOT NULL,
  first_ordinal INTEGER NOT NULL DEFAULT -1,
  last_ordinal INTEGER NOT NULL DEFAULT -1,
  PRIMARY KEY(manifest_id, ordinal, order_text, entity, attr),
  FOREIGN KEY(manifest_id, ordinal) REFERENCES vev_index_run_manifest_runs(manifest_id, ordinal)
);
CREATE TABLE IF NOT EXISTS vev_index_maintenance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  index_name TEXT NOT NULL,
  basis_tx INTEGER NOT NULL,
  root_chunk_id INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(index_name, basis_tx, root_chunk_id)
);
CREATE INDEX IF NOT EXISTS vev_index_chunks_lookup ON vev_index_chunks(index_name, level, first_key, last_key);
CREATE INDEX IF NOT EXISTS vev_index_chunk_entries_lookup ON vev_index_chunk_entries(chunk_id, ordinal);
CREATE INDEX IF NOT EXISTS vev_index_roots_basis ON vev_index_roots(basis_tx, root_id);
CREATE INDEX IF NOT EXISTS vev_index_root_pages_root ON vev_index_root_pages(root_id, ordinal);
CREATE INDEX IF NOT EXISTS vev_index_root_pages_index ON vev_index_root_pages(index_name, root_id);
CREATE INDEX IF NOT EXISTS vev_index_run_manifests_basis ON vev_index_run_manifests(index_name, basis_tx, manifest_id);
CREATE INDEX IF NOT EXISTS vev_index_run_manifest_runs_lookup ON vev_index_run_manifest_runs(manifest_id, ordinal);
CREATE INDEX IF NOT EXISTS vev_index_run_manifest_runs_bounds ON vev_index_run_manifest_runs(manifest_id, first_a, last_a);
CREATE INDEX IF NOT EXISTS vev_index_run_manifest_attr_ranges_lookup ON vev_index_run_manifest_attr_ranges(manifest_id, attr, ordinal);
CREATE INDEX IF NOT EXISTS vev_index_run_manifest_entity_attr_ranges_lookup ON vev_index_run_manifest_entity_attr_ranges(manifest_id, order_text, entity, attr, ordinal);
CREATE INDEX IF NOT EXISTS vev_index_maintenance_next ON vev_index_maintenance(id);
CREATE INDEX IF NOT EXISTS vev_index_maintenance_name ON vev_index_maintenance(index_name);
INSERT OR REPLACE INTO vev_meta (key, value) VALUES ('format', 'vev-snapshot-text-v1');
INSERT OR REPLACE INTO vev_meta (key, value) VALUES ('storage-architecture', 'vev-sqlite-chunked-index-v0');
`

SQLITE_SCHEMA_VERSION :: "1"
SQLITE_ENTITY_PARTITION_LAYOUT :: "separated-v1"

sqlite_entity_partition_layout_current :: proc(db: ^SQLite3) -> bool {
    stmt: ^SQLite3_Stmt
    sql := "SELECT 1 FROM vev_meta WHERE key = 'entity-partition-layout' AND value = ? LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, SQLITE_ENTITY_PARTITION_LAYOUT) != SQLITE_OK {
        return false
    }
    return sqlite3_step(stmt) == SQLITE_ROW
}

sqlite_mark_entity_partition_layout_current :: proc(db: ^SQLite3) -> (bool, string) {
    return sqlite_exec_ok(
        db,
        "INSERT OR REPLACE INTO vev_meta (key, value) VALUES ('entity-partition-layout', 'separated-v1')",
    )
}

sqlite_require_entity_partition_layout :: proc(db: ^SQLite3) -> (bool, string) {
    if sqlite_entity_partition_layout_current(db) {
        return true, ""
    }
    stmt: ^SQLite3_Stmt
    sql := "SELECT 1 FROM vev_datoms LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite entity-partition probe"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare entity-partition probe failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_DONE {
        return sqlite_mark_entity_partition_layout_current(db)
    }
    if rc != SQLITE_ROW {
        return false, sqlite_error_text(db, "sqlite entity-partition probe failed")
    }
    return false, strings.clone(
        "legacy Vev database has no separated entity-partition marker; keep a backup and explicitly confirm or migrate it before opening",
    )
}

sqlite_schema_version_current :: proc(db: ^SQLite3) -> bool {
    stmt: ^SQLite3_Stmt
    sql := "SELECT 1 FROM vev_meta WHERE key = 'schema-version' AND value = ? LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, SQLITE_SCHEMA_VERSION) != SQLITE_OK {
        return false
    }
    return sqlite3_step(stmt) == SQLITE_ROW
}

sqlite_mark_schema_current :: proc(db: ^SQLite3) -> (bool, string) {
    return sqlite_exec_ok(
        db,
        "INSERT OR REPLACE INTO vev_meta (key, value) VALUES ('schema-version', '1')",
    )
}

sqlite_open_initialized :: proc(path: string) -> (^SQLite3, bool, string) {
    db: ^SQLite3
    path_c, path_c_ok := sqlite_cstring(path)
    if !path_c_ok {
        return nil, false, "failed to allocate sqlite path"
    }
    defer delete(path_c)
    if sqlite3_open(path_c, &db) != SQLITE_OK {
        msg := sqlite_error_text(db, "sqlite open failed")
        if db != nil {
            _ = sqlite3_close(db)
        }
        return nil, false, msg
    }
    _ = sqlite3_busy_timeout(db, 5000)
    // A current store is already initialized. Re-running the complete DDL
    // program on every connection turns an otherwise read-only open into a
    // schema writer and can fail with SQLITE_BUSY while another connection is
    // committing. Connection-local durability policy is sufficient here;
    // journal mode and schema creation belong to initialization/migration.
    if sqlite_schema_version_current(db) {
        synchronous_ok, synchronous_error := sqlite_exec_ok(db, "PRAGMA synchronous = NORMAL")
        if !synchronous_ok {
            _ = sqlite3_close(db)
            return nil, false, synchronous_error
        }
        partition_ok, partition_error := sqlite_require_entity_partition_layout(db)
        if !partition_ok {
            _ = sqlite3_close(db)
            return nil, false, partition_error
        }
        return db, true, ""
    }
    ok, err := sqlite_exec_ok(db, sqlite_schema_sql)
    if !ok {
        _ = sqlite3_close(db)
        return nil, false, err
    }
    log_index_ok, log_index_error := sqlite_ensure_datom_log_index_column(db)
    if !log_index_ok {
        _ = sqlite3_close(db)
        return nil, false, log_index_error
    }
    value_entity_ok, value_entity_error := sqlite_ensure_datom_value_entity_column(db)
    if !value_entity_ok {
        _ = sqlite3_close(db)
        return nil, false, value_entity_error
    }
    text_terms_ok, text_terms_error := sqlite_ensure_text_terms_table(db)
    if !text_terms_ok {
        _ = sqlite3_close(db)
        return nil, false, text_terms_error
    }
    child_count_ok, child_count_error := sqlite_ensure_index_chunk_child_count_column(db)
    if !child_count_ok {
        _ = sqlite3_close(db)
        return nil, false, child_count_error
    }
    root_manifest_ok, root_manifest_error := sqlite_ensure_index_root_manifest_columns(db)
    if !root_manifest_ok {
        _ = sqlite3_close(db)
        return nil, false, root_manifest_error
    }
    run_manifest_parent_ok, run_manifest_parent_error := sqlite_ensure_index_run_manifest_parent_column(db)
    if !run_manifest_parent_ok {
        _ = sqlite3_close(db)
        return nil, false, run_manifest_parent_error
    }
    run_manifest_bounds_ok, run_manifest_bounds_error := sqlite_ensure_index_run_manifest_run_bound_columns(db)
    if !run_manifest_bounds_ok {
        _ = sqlite3_close(db)
        return nil, false, run_manifest_bounds_error
    }
    attr_ranges_ok, attr_ranges_error := sqlite_ensure_index_run_manifest_attr_ranges_table(db)
    if !attr_ranges_ok {
        _ = sqlite3_close(db)
        return nil, false, attr_ranges_error
    }
    entity_attr_ranges_ok, entity_attr_ranges_error := sqlite_ensure_index_run_manifest_entity_attr_ranges_table(db)
    if !entity_attr_ranges_ok {
        _ = sqlite3_close(db)
        return nil, false, entity_attr_ranges_error
    }
    fulltext_ok, _ := sqlite_ensure_fulltext_table(db)
    _ = fulltext_ok
    version_ok, version_error := sqlite_mark_schema_current(db)
    if !version_ok {
        _ = sqlite3_close(db)
        return nil, false, version_error
    }
    partition_ok, partition_error := sqlite_require_entity_partition_layout(db)
    if !partition_ok {
        _ = sqlite3_close(db)
        return nil, false, partition_error
    }
    return db, true, ""
}

sqlite_ensure_datom_log_index_column :: proc(db: ^SQLite3) -> (bool, string) {
    ok, err := sqlite_exec_ok(db, "ALTER TABLE vev_datoms ADD COLUMN log_index INTEGER NOT NULL DEFAULT -1")
    if !ok && !strings.contains(err, "duplicate column name") {
        return false, err
    }
    if !ok { delete(err) }
    index_ok, index_error := sqlite_exec_ok(db, "CREATE INDEX IF NOT EXISTS vev_datoms_log_index ON vev_datoms(log_index)")
    if !index_ok {
        return false, index_error
    }
    return true, ""
}

sqlite_ensure_datom_value_entity_column :: proc(db: ^SQLite3) -> (bool, string) {
    ok, err := sqlite_exec_ok(db, "ALTER TABLE vev_datoms ADD COLUMN value_entity INTEGER NOT NULL DEFAULT -1")
    if !ok && !strings.contains(err, "duplicate column name") {
        return false, err
    }
    if !ok { delete(err) }
    backfill_ok, backfill_error := sqlite_exec_ok(db, "UPDATE vev_datoms SET value_entity = CAST(substr(value_text, 14, length(value_text) - 14) AS INTEGER) WHERE value_entity = -1 AND value_text LIKE '[:vev/entity %]' AND substr(value_text, length(value_text), 1) = ']'")
    if !backfill_ok {
        return false, backfill_error
    }
    index_ok, index_error := sqlite_exec_ok(db, "CREATE INDEX IF NOT EXISTS vev_datoms_vaet_entity ON vev_datoms(value_entity, a, e, tx, added)")
    if !index_ok {
        return false, index_error
    }
    return true, ""
}

sqlite_ensure_index_chunk_child_count_column :: proc(db: ^SQLite3) -> (bool, string) {
    ok, err := sqlite_exec_ok(db, "ALTER TABLE vev_index_chunks ADD COLUMN child_count INTEGER NOT NULL DEFAULT 0")
    if !ok && !strings.contains(err, "duplicate column name") {
        return false, err
    }
    if !ok { delete(err) }
    return true, ""
}

sqlite_ensure_fulltext_table :: proc(db: ^SQLite3) -> (bool, string) {
    table_ok, table_err := sqlite_exec_ok(db, "CREATE VIRTUAL TABLE IF NOT EXISTS vev_fulltext USING fts5(attr UNINDEXED, value_text, log_index UNINDEXED)")
    if !table_ok {
        return false, table_err
    }
    backfill_ok, backfill_err := sqlite_exec_ok(db, "INSERT OR REPLACE INTO vev_fulltext(rowid, attr, value_text, log_index) SELECT log_index, a, value_text, log_index FROM vev_datoms WHERE added = 1 AND log_index >= 0")
    if !backfill_ok {
        return false, backfill_err
    }
    return true, ""
}

sqlite_ensure_text_terms_table :: proc(db: ^SQLite3) -> (bool, string) {
    table_ok, table_err := sqlite_exec_ok(db, "CREATE TABLE IF NOT EXISTS vev_text_terms (attr TEXT NOT NULL, term TEXT NOT NULL, log_index INTEGER NOT NULL, PRIMARY KEY(attr, term, log_index)); CREATE INDEX IF NOT EXISTS vev_text_terms_lookup ON vev_text_terms(attr, term, log_index)")
    if !table_ok {
        return false, table_err
    }
    count := sqlite_text_terms_count_raw(rawptr(db))
    if count == 0 {
        rebuild_ok, rebuild_err := sqlite_rebuild_text_terms_raw(rawptr(db))
        if !rebuild_ok {
            return false, rebuild_err
        }
    }
    return true, ""
}

sqlite_ensure_index_root_manifest_columns :: proc(db: ^SQLite3) -> (bool, string) {
    eavt_ok, eavt_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_roots ADD COLUMN eavt_manifest_id INTEGER NOT NULL DEFAULT 0")
    if !eavt_ok && !strings.contains(eavt_err, "duplicate column name") {
        return false, eavt_err
    }
    if !eavt_ok { delete(eavt_err) }
    aevt_ok, aevt_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_roots ADD COLUMN aevt_manifest_id INTEGER NOT NULL DEFAULT 0")
    if !aevt_ok && !strings.contains(aevt_err, "duplicate column name") {
        return false, aevt_err
    }
    if !aevt_ok { delete(aevt_err) }
    avet_ok, avet_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_roots ADD COLUMN avet_manifest_id INTEGER NOT NULL DEFAULT 0")
    if !avet_ok && !strings.contains(avet_err, "duplicate column name") {
        return false, avet_err
    }
    if !avet_ok { delete(avet_err) }
    vaet_ok, vaet_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_roots ADD COLUMN vaet_manifest_id INTEGER NOT NULL DEFAULT 0")
    if !vaet_ok && !strings.contains(vaet_err, "duplicate column name") {
        return false, vaet_err
    }
    if !vaet_ok { delete(vaet_err) }
    return true, ""
}

sqlite_ensure_index_run_manifest_parent_column :: proc(db: ^SQLite3) -> (bool, string) {
    ok, err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifests ADD COLUMN parent_manifest_id INTEGER NOT NULL DEFAULT 0")
    if !ok && !strings.contains(err, "duplicate column name") {
        return false, err
    }
    if !ok { delete(err) }
    return true, ""
}

sqlite_ensure_index_run_manifest_run_bound_columns :: proc(db: ^SQLite3) -> (bool, string) {
    first_e_ok, first_e_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN first_e INTEGER NOT NULL DEFAULT 0")
    if !first_e_ok && !strings.contains(first_e_err, "duplicate column name") {
        return false, first_e_err
    }
    if !first_e_ok { delete(first_e_err) }
    first_a_ok, first_a_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN first_a TEXT NOT NULL DEFAULT ''")
    if !first_a_ok && !strings.contains(first_a_err, "duplicate column name") {
        return false, first_a_err
    }
    if !first_a_ok { delete(first_a_err) }
    first_value_ok, first_value_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN first_value_text TEXT NOT NULL DEFAULT ''")
    if !first_value_ok && !strings.contains(first_value_err, "duplicate column name") {
        return false, first_value_err
    }
    if !first_value_ok { delete(first_value_err) }
    first_tx_ok, first_tx_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN first_tx INTEGER NOT NULL DEFAULT 0")
    if !first_tx_ok && !strings.contains(first_tx_err, "duplicate column name") {
        return false, first_tx_err
    }
    if !first_tx_ok { delete(first_tx_err) }
    first_added_ok, first_added_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN first_added INTEGER NOT NULL DEFAULT 1")
    if !first_added_ok && !strings.contains(first_added_err, "duplicate column name") {
        return false, first_added_err
    }
    if !first_added_ok { delete(first_added_err) }
    last_e_ok, last_e_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN last_e INTEGER NOT NULL DEFAULT 0")
    if !last_e_ok && !strings.contains(last_e_err, "duplicate column name") {
        return false, last_e_err
    }
    if !last_e_ok { delete(last_e_err) }
    last_a_ok, last_a_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN last_a TEXT NOT NULL DEFAULT ''")
    if !last_a_ok && !strings.contains(last_a_err, "duplicate column name") {
        return false, last_a_err
    }
    if !last_a_ok { delete(last_a_err) }
    last_value_ok, last_value_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN last_value_text TEXT NOT NULL DEFAULT ''")
    if !last_value_ok && !strings.contains(last_value_err, "duplicate column name") {
        return false, last_value_err
    }
    if !last_value_ok { delete(last_value_err) }
    last_tx_ok, last_tx_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN last_tx INTEGER NOT NULL DEFAULT 0")
    if !last_tx_ok && !strings.contains(last_tx_err, "duplicate column name") {
        return false, last_tx_err
    }
    if !last_tx_ok { delete(last_tx_err) }
    last_added_ok, last_added_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_runs ADD COLUMN last_added INTEGER NOT NULL DEFAULT 1")
    if !last_added_ok && !strings.contains(last_added_err, "duplicate column name") {
        return false, last_added_err
    }
    if !last_added_ok { delete(last_added_err) }
    index_ok, index_err := sqlite_exec_ok(db, "CREATE INDEX IF NOT EXISTS vev_index_run_manifest_runs_bounds ON vev_index_run_manifest_runs(manifest_id, first_a, last_a)")
    if !index_ok {
        return false, index_err
    }
    return true, ""
}

sqlite_ensure_index_run_manifest_attr_ranges_table :: proc(db: ^SQLite3) -> (bool, string) {
    table_ok, table_err := sqlite_exec_ok(db, "CREATE TABLE IF NOT EXISTS vev_index_run_manifest_attr_ranges (manifest_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, attr TEXT NOT NULL, first_ordinal INTEGER NOT NULL DEFAULT -1, first_e INTEGER NOT NULL, first_value_text TEXT NOT NULL, first_tx INTEGER NOT NULL, first_added INTEGER NOT NULL, last_ordinal INTEGER NOT NULL DEFAULT -1, last_e INTEGER NOT NULL, last_value_text TEXT NOT NULL, last_tx INTEGER NOT NULL, last_added INTEGER NOT NULL, PRIMARY KEY(manifest_id, ordinal, attr), FOREIGN KEY(manifest_id, ordinal) REFERENCES vev_index_run_manifest_runs(manifest_id, ordinal))")
    if !table_ok {
        return false, table_err
    }
    first_ordinal_ok, first_ordinal_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_attr_ranges ADD COLUMN first_ordinal INTEGER NOT NULL DEFAULT -1")
    if !first_ordinal_ok && !strings.contains(first_ordinal_err, "duplicate column name") {
        return false, first_ordinal_err
    }
    if !first_ordinal_ok { delete(first_ordinal_err) }
    last_ordinal_ok, last_ordinal_err := sqlite_exec_ok(db, "ALTER TABLE vev_index_run_manifest_attr_ranges ADD COLUMN last_ordinal INTEGER NOT NULL DEFAULT -1")
    if !last_ordinal_ok && !strings.contains(last_ordinal_err, "duplicate column name") {
        return false, last_ordinal_err
    }
    if !last_ordinal_ok { delete(last_ordinal_err) }
    index_ok, index_err := sqlite_exec_ok(db, "CREATE INDEX IF NOT EXISTS vev_index_run_manifest_attr_ranges_lookup ON vev_index_run_manifest_attr_ranges(manifest_id, attr, ordinal)")
    if !index_ok {
        return false, index_err
    }
    return true, ""
}

sqlite_ensure_index_run_manifest_entity_attr_ranges_table :: proc(db: ^SQLite3) -> (bool, string) {
    table_ok, table_err := sqlite_exec_ok(db, "CREATE TABLE IF NOT EXISTS vev_index_run_manifest_entity_attr_ranges (manifest_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, order_text TEXT NOT NULL, entity INTEGER NOT NULL, attr TEXT NOT NULL, first_ordinal INTEGER NOT NULL DEFAULT -1, last_ordinal INTEGER NOT NULL DEFAULT -1, PRIMARY KEY(manifest_id, ordinal, order_text, entity, attr), FOREIGN KEY(manifest_id, ordinal) REFERENCES vev_index_run_manifest_runs(manifest_id, ordinal))")
    if !table_ok {
        return false, table_err
    }
    index_ok, index_err := sqlite_exec_ok(db, "CREATE INDEX IF NOT EXISTS vev_index_run_manifest_entity_attr_ranges_lookup ON vev_index_run_manifest_entity_attr_ranges(manifest_id, order_text, entity, attr, ordinal)")
    if !index_ok {
        return false, index_err
    }
    return true, ""
}

sqlite_save_snapshot_text_raw :: proc(path: string, text: string) -> (bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return false, open_error
    }
    defer _ = sqlite3_close(db)
    ok, tx_error := sqlite_exec_ok(db, "BEGIN IMMEDIATE")
    if !ok {
        return false, tx_error
    }
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_snapshots (key, value, updated_at) VALUES ('current', ?, CURRENT_TIMESTAMP)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, sqlite_error_text(db, "sqlite prepare failed")
    }
    defer _ = sqlite3_finalize(stmt)
    text_c, text_c_ok := sqlite_cstring(text)
    if !text_c_ok {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, "failed to allocate sqlite snapshot text"
    }
    defer delete(text_c)
    if sqlite3_bind_text(stmt, 1, text_c, -1, SQLITE_TRANSIENT) != SQLITE_OK {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, sqlite_error_text(db, "sqlite bind failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, sqlite_error_text(db, "sqlite write failed")
    }
    commit_ok, commit_error := sqlite_exec_ok(db, "COMMIT")
    if !commit_ok {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        return false, commit_error
    }
    return true, ""
}

sqlite_load_snapshot_text_handle_raw :: proc(handle: rawptr) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT value FROM vev_snapshots WHERE key = 'current'"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 0)
        if raw == nil {
            return "", false, "sqlite snapshot value was null"
        }
        out, err := strings.clone_from_cstring(raw)
        if err != nil {
            return "", false, "failed to clone sqlite snapshot text"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite DB has no current Vev snapshot"
    }
    return "", false, sqlite_error_text(db, "sqlite read failed")
}

sqlite_load_snapshot_text_raw :: proc(path: string) -> (string, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return "", false, open_error
    }
    defer _ = sqlite3_close(db)
    return sqlite_load_snapshot_text_handle_raw(rawptr(db))
}

sqlite_open_replace_datoms_raw :: proc(path: string) -> (rawptr, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return nil, false, open_error
    }
    begin_ok, tx_error := sqlite_exec_ok(db, "BEGIN IMMEDIATE")
    if !begin_ok {
        _ = sqlite3_close(db)
        return nil, false, tx_error
    }
    _, _ = sqlite_exec_ok(db, "DELETE FROM vev_fulltext")
    clear_ok, clear_error := sqlite_exec_ok(db, "DELETE FROM vev_datoms; DELETE FROM vev_text_terms; DELETE FROM vev_tx_meta; DELETE FROM vev_transactions;")
    if !clear_ok {
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        _ = sqlite3_close(db)
        return nil, false, clear_error
    }
    return rawptr(db), true, ""
}

sqlite_open_append_datoms_raw :: proc(path: string) -> (rawptr, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return nil, false, open_error
    }
    begin_ok, tx_error := sqlite_exec_ok(db, "BEGIN IMMEDIATE")
    if !begin_ok {
        _ = sqlite3_close(db)
        return nil, false, tx_error
    }
    return rawptr(db), true, ""
}

sqlite_open_live_raw :: proc(path: string) -> (rawptr, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return nil, false, open_error
    }
    return rawptr(db), true, ""
}

sqlite_close_live_raw :: proc(handle: rawptr) {
    if handle != nil {
        _ = sqlite3_close((^SQLite3)(handle))
    }
}

sqlite_begin_immediate_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    return sqlite_exec_ok((^SQLite3)(handle), "BEGIN IMMEDIATE")
}

sqlite_begin_query_read_raw :: proc(handle: rawptr) -> (bool, bool, string) {
    if handle == nil {
        return false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    if sqlite3_get_autocommit(db) == 0 {
        return false, true, ""
    }
    ok, err := sqlite_exec_ok(db, "BEGIN")
    return ok, ok, err
}

sqlite_end_query_read_raw :: proc(handle: rawptr, started: bool) {
    if started && handle != nil {
        _, _ = sqlite_exec_ok((^SQLite3)(handle), "ROLLBACK")
    }
}

sqlite_rollback_raw :: proc(handle: rawptr) {
    if handle != nil {
        _, _ = sqlite_exec_ok((^SQLite3)(handle), "ROLLBACK")
    }
}

sqlite_commit_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    return sqlite_exec_ok((^SQLite3)(handle), "COMMIT")
}

sqlite_rollback_close_raw :: proc(handle: rawptr) {
    if handle != nil {
        db := (^SQLite3)(handle)
        _, _ = sqlite_exec_ok(db, "ROLLBACK")
        _ = sqlite3_close(db)
    }
}

sqlite_commit_close_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    ok, err := sqlite_exec_ok(db, "COMMIT")
    _ = sqlite3_close(db)
    if !ok {
        return false, err
    }
    return true, ""
}

sqlite_insert_tx_raw :: proc(handle: rawptr, tx: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR IGNORE INTO vev_transactions (tx) VALUES (?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare tx failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind tx failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert tx failed")
    }
    return true, ""
}

sqlite_tx_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_transactions"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare tx count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite tx count failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_datom_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_datoms"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare datom count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_step(stmt) == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    return 0, false, sqlite_error_text(db, "sqlite datom count failed")
}

sqlite_next_entity_id_at_basis_raw :: proc(handle: rawptr, tx_partition_base, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COALESCE(MAX(e), 0) FROM vev_datoms WHERE e < ? AND tx <= ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare next entity id failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx_partition_base)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(basis_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind next entity id failed")
    }
    if sqlite3_step(stmt) != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite next entity id failed")
    }
    max_entity := u64(sqlite3_column_int64(stmt, 0))
    return max_entity + 1, true, ""
}

sqlite_datom_has_retractions_raw :: proc(handle: rawptr) -> (bool, bool, string) {
    if handle == nil {
        return false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT 1 FROM vev_datoms WHERE added = 0 LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, false, sqlite_error_text(db, "sqlite prepare datom retraction check failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return true, true, ""
    }
    if rc == SQLITE_DONE {
        return false, true, ""
    }
    return false, false, sqlite_error_text(db, "sqlite datom retraction check failed")
}

sqlite_tx_ids_raw :: proc(handle: rawptr) -> ([dynamic]u64, bool, string) {
    out := make([dynamic]u64)
    if handle == nil {
        return out, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT tx FROM vev_transactions ORDER BY tx"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return out, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite prepare tx ids failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return out, false, sqlite_error_text(db, "sqlite tx ids failed")
        }
        append(&out, u64(sqlite3_column_int64(stmt, 0)))
    }
    return out, true, ""
}

sqlite_tx_data_text_raw :: proc(handle: rawptr, tx: u64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE tx = ? ORDER BY log_index, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare tx data read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx)) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind tx data read failed")
    }
    parts := make([dynamic]string)
    append(&parts, "[")
    first := true
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            delete(parts)
            return "", false, sqlite_error_text(db, "sqlite tx data read failed")
        }
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            delete(parts)
            return "", false, "sqlite tx data row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            delete(parts)
            return "", false, "failed to clone sqlite tx data attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            delete(parts)
            return "", false, "failed to clone sqlite tx data value"
        }
        if !first {
            append(&parts, " ")
        }
        first = false
        append(&parts, fmt.tprintf("[%d %s %s %d %v]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text,
            sqlite3_column_int64(stmt, 3),
            sqlite3_column_int(stmt, 4) != 0))
        delete(a_text)
        delete(value_text)
    }
    append(&parts, "]")
    out := strings.concatenate(parts[:])
    delete(parts)
    return out, true, ""
}

sqlite_meta_value_raw :: proc(handle: rawptr, key: string) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT value FROM vev_meta WHERE key = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare metadata read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, key) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind metadata key failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 0)
        if raw == nil {
            return "", false, "sqlite metadata value was null"
        }
        out, err := strings.clone_from_cstring(raw)
        if err != nil {
            return "", false, "failed to clone sqlite metadata value"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite metadata key was not found"
    }
    return "", false, sqlite_error_text(db, "sqlite metadata read failed")
}

sqlite_confirm_entity_partition_layout_raw :: proc(path: string) -> (bool, string) {
    db: ^SQLite3
    path_c, path_c_ok := sqlite_cstring(path)
    if !path_c_ok {
        return false, "failed to allocate sqlite path"
    }
    defer delete(path_c)
    if sqlite3_open(path_c, &db) != SQLITE_OK {
        msg := sqlite_error_text(db, "sqlite open failed")
        if db != nil {
            _ = sqlite3_close(db)
        }
        return false, msg
    }
    defer _ = sqlite3_close(db)
    format, format_ok, format_error := sqlite_meta_value_raw(rawptr(db), "format")
    if !format_ok {
        return false, format_error
    }
    defer delete(format)
    if format != "vev-snapshot-text-v1" {
        return false, strings.clone("database is not a supported Vev SQLite store")
    }
    return sqlite_mark_entity_partition_layout_current(db)
}

sqlite_clear_entity_partition_layout_for_test_raw :: proc(path: string) -> (bool, string) {
    db: ^SQLite3
    path_c, path_c_ok := sqlite_cstring(path)
    if !path_c_ok {
        return false, "failed to allocate sqlite path"
    }
    defer delete(path_c)
    if sqlite3_open(path_c, &db) != SQLITE_OK {
        msg := sqlite_error_text(db, "sqlite open failed")
        if db != nil {
            _ = sqlite3_close(db)
        }
        return false, msg
    }
    defer _ = sqlite3_close(db)
    return sqlite_exec_ok(db, "DELETE FROM vev_meta WHERE key = 'entity-partition-layout'")
}

sqlite_index_root_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_roots"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index root count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite index root count failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_index_root_page_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_root_pages"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index root page count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite index root page count failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_index_chunk_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_chunks"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite index chunk count failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_entry_backed_index_chunk_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_chunks WHERE payload_text = ':entries'"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare entry-backed index chunk count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite entry-backed index chunk count failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_index_tree_stats_raw :: proc(handle: rawptr, root_chunk_id: u64) -> (u64, u64, i64, bool, string) {
    if handle == nil {
        return 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "WITH RECURSIVE tree(chunk_id, level) AS (SELECT c.chunk_id, c.level FROM vev_index_chunks c WHERE c.chunk_id = ? UNION ALL SELECT child.chunk_id, child.level FROM tree JOIN vev_index_chunk_edges edge ON edge.parent_chunk_id = tree.chunk_id JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id) SELECT COUNT(*), COALESCE(SUM(CASE WHEN level = 0 THEN 1 ELSE 0 END), 0), COALESCE(MAX(level), 0) FROM tree"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare index tree stats failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(root_chunk_id)) != SQLITE_OK {
        return 0, 0, 0, false, sqlite_error_text(db, "sqlite bind index tree stats failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), sqlite3_column_int64(stmt, 2), true, ""
    }
    return 0, 0, 0, false, sqlite_error_text(db, "sqlite index tree stats read failed")
}

sqlite_latest_index_root_basis_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT basis_tx FROM vev_index_roots ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare latest index root failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite DB has no Vev index roots"
    }
    return 0, false, sqlite_error_text(db, "sqlite latest index root read failed")
}

sqlite_latest_index_root_identity_raw :: proc(handle: rawptr) -> (u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT basis_tx, root_id FROM vev_index_roots ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite prepare latest index root identity failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, false, "sqlite DB has no Vev index roots"
    }
    return 0, 0, false, sqlite_error_text(db, "sqlite latest index root identity read failed")
}

sqlite_latest_index_chunk_row_count_wide_raw :: proc(handle: rawptr, index_name: string) -> (u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := ""
    switch index_name {
    case ":eavt":
        sql = "SELECT r.basis_tx, c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.eavt_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":aevt":
        sql = "SELECT r.basis_tx, c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.aevt_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":avet":
        sql = "SELECT r.basis_tx, c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.avet_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":vaet":
        sql = "SELECT r.basis_tx, c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.vaet_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case:
        return 0, 0, false, "unknown Vev index name"
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite prepare latest index chunk failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, false, "sqlite DB has no Vev index roots"
    }
    return 0, 0, false, sqlite_error_text(db, "sqlite latest index chunk read failed")
}

sqlite_latest_index_chunk_row_count_raw :: proc(handle: rawptr, index_name: string) -> (u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT r.basis_tx, c.row_count FROM (SELECT root_id, basis_tx FROM vev_index_roots ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id JOIN vev_index_chunks c ON c.chunk_id = p.root_chunk_id WHERE p.index_name = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite prepare latest index page chunk failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite bind latest index page chunk failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), true, ""
    }
    if rc == SQLITE_DONE {
        return sqlite_latest_index_chunk_row_count_wide_raw(handle, index_name)
    }
    return 0, 0, false, sqlite_error_text(db, "sqlite latest index page chunk read failed")
}

sqlite_latest_index_root_chunk_info_wide_raw :: proc(handle: rawptr, index_name: string) -> (u64, u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := ""
    switch index_name {
    case ":eavt":
        sql = "SELECT r.basis_tx, c.row_count, c.chunk_id FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.eavt_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":aevt":
        sql = "SELECT r.basis_tx, c.row_count, c.chunk_id FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.aevt_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":avet":
        sql = "SELECT r.basis_tx, c.row_count, c.chunk_id FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.avet_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case ":vaet":
        sql = "SELECT r.basis_tx, c.row_count, c.chunk_id FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.vaet_chunk_id ORDER BY r.root_id DESC LIMIT 1"
    case:
        return 0, 0, 0, false, "unknown Vev index name"
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare latest index root chunk info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), u64(sqlite3_column_int64(stmt, 2)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, 0, false, "sqlite DB has no Vev index roots"
    }
    return 0, 0, 0, false, sqlite_error_text(db, "sqlite latest index root chunk info read failed")
}

sqlite_latest_index_root_chunk_info_raw :: proc(handle: rawptr, index_name: string) -> (u64, u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT r.basis_tx, c.row_count, c.chunk_id FROM (SELECT root_id, basis_tx FROM vev_index_roots ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id JOIN vev_index_chunks c ON c.chunk_id = p.root_chunk_id WHERE p.index_name = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare latest index root page chunk info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK {
        return 0, 0, 0, false, sqlite_error_text(db, "sqlite bind latest index root page chunk info failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), u64(sqlite3_column_int64(stmt, 2)), true, ""
    }
    if rc == SQLITE_DONE {
        return sqlite_latest_index_root_chunk_info_wide_raw(handle, index_name)
    }
    return 0, 0, 0, false, sqlite_error_text(db, "sqlite latest index root page chunk info read failed")
}

sqlite_index_chunk_row_count_at_basis_wide_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := ""
    switch index_name {
    case ":eavt":
        sql = "SELECT c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.eavt_chunk_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":aevt":
        sql = "SELECT c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.aevt_chunk_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":avet":
        sql = "SELECT c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.avet_chunk_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":vaet":
        sql = "SELECT c.row_count FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.vaet_chunk_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case:
        return 0, false, "unknown Vev index name"
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare basis index chunk failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind basis index chunk failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite DB has no Vev index root for basis"
    }
    return 0, false, sqlite_error_text(db, "sqlite basis index chunk read failed")
}

sqlite_index_chunk_row_count_at_basis_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT c.row_count FROM (SELECT root_id FROM vev_index_roots WHERE basis_tx = ? ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id JOIN vev_index_chunks c ON c.chunk_id = p.root_chunk_id WHERE p.index_name = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare basis index page chunk failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, index_name) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind basis index page chunk failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return sqlite_index_chunk_row_count_at_basis_wide_raw(handle, index_name, basis_tx)
    }
    return 0, false, sqlite_error_text(db, "sqlite basis index page chunk read failed")
}

sqlite_index_root_chunk_info_at_basis_wide_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64) -> (u64, u64, u64, u64, string, i64, i64, bool, string) {
    if handle == nil {
        return 0, 0, 0, 0, "", 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := ""
    switch index_name {
    case ":eavt":
        sql = "SELECT CASE WHEN r.eavt_manifest_id > 0 THEN m.row_count ELSE c.row_count END, c.chunk_id, r.eavt_manifest_id, COALESCE(m.run_count, 0), c.first_key, c.level, CASE WHEN c.level = 0 THEN 0 WHEN c.child_count > 0 THEN c.child_count ELSE (SELECT COUNT(*) FROM vev_index_chunk_edges edge WHERE edge.parent_chunk_id = c.chunk_id) END FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.eavt_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = r.eavt_manifest_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":aevt":
        sql = "SELECT CASE WHEN r.aevt_manifest_id > 0 THEN m.row_count ELSE c.row_count END, c.chunk_id, r.aevt_manifest_id, COALESCE(m.run_count, 0), c.first_key, c.level, CASE WHEN c.level = 0 THEN 0 WHEN c.child_count > 0 THEN c.child_count ELSE (SELECT COUNT(*) FROM vev_index_chunk_edges edge WHERE edge.parent_chunk_id = c.chunk_id) END FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.aevt_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = r.aevt_manifest_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":avet":
        sql = "SELECT CASE WHEN r.avet_manifest_id > 0 THEN m.row_count ELSE c.row_count END, c.chunk_id, r.avet_manifest_id, COALESCE(m.run_count, 0), c.first_key, c.level, CASE WHEN c.level = 0 THEN 0 WHEN c.child_count > 0 THEN c.child_count ELSE (SELECT COUNT(*) FROM vev_index_chunk_edges edge WHERE edge.parent_chunk_id = c.chunk_id) END FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.avet_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = r.avet_manifest_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case ":vaet":
        sql = "SELECT CASE WHEN r.vaet_manifest_id > 0 THEN m.row_count ELSE c.row_count END, c.chunk_id, r.vaet_manifest_id, COALESCE(m.run_count, 0), c.first_key, c.level, CASE WHEN c.level = 0 THEN 0 WHEN c.child_count > 0 THEN c.child_count ELSE (SELECT COUNT(*) FROM vev_index_chunk_edges edge WHERE edge.parent_chunk_id = c.chunk_id) END FROM vev_index_roots r JOIN vev_index_chunks c ON c.chunk_id = r.vaet_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = r.vaet_manifest_id WHERE r.basis_tx = ? ORDER BY r.root_id DESC LIMIT 1"
    case:
        return 0, 0, 0, 0, "", 0, 0, false, "unknown Vev index name"
    }
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, "", 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite prepare basis index root chunk info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite bind basis index root chunk info failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 4)
        if raw == nil {
            return 0, 0, 0, 0, "", 0, 0, false, "sqlite index root first key was null"
        }
        first_key, err := strings.clone_from_cstring(raw)
        if err != nil {
            return 0, 0, 0, 0, "", 0, 0, false, "failed to clone sqlite index root first key"
        }
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), u64(sqlite3_column_int64(stmt, 2)), u64(sqlite3_column_int64(stmt, 3)), first_key, sqlite3_column_int64(stmt, 5), sqlite3_column_int64(stmt, 6), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, 0, 0, "", 0, 0, false, "sqlite DB has no Vev index root for basis"
    }
    return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite basis index root chunk info read failed")
}

sqlite_index_root_chunk_info_at_basis_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64) -> (u64, u64, u64, u64, string, i64, i64, bool, string) {
    if handle == nil {
        return 0, 0, 0, 0, "", 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT CASE WHEN p.manifest_id > 0 THEN m.row_count ELSE c.row_count END, c.chunk_id, p.manifest_id, COALESCE(m.run_count, 0), c.first_key, c.level, CASE WHEN c.level = 0 THEN 0 WHEN c.child_count > 0 THEN c.child_count ELSE (SELECT COUNT(*) FROM vev_index_chunk_edges edge WHERE edge.parent_chunk_id = c.chunk_id) END FROM (SELECT root_id FROM vev_index_roots WHERE basis_tx = ? ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id JOIN vev_index_chunks c ON c.chunk_id = p.root_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = p.manifest_id WHERE p.index_name = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, "", 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite prepare basis index root page chunk info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, index_name) != SQLITE_OK {
        return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite bind basis index root page chunk info failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 4)
        if raw == nil {
            return 0, 0, 0, 0, "", 0, 0, false, "sqlite index root first key was null"
        }
        first_key, err := strings.clone_from_cstring(raw)
        if err != nil {
            return 0, 0, 0, 0, "", 0, 0, false, "failed to clone sqlite index root first key"
        }
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), u64(sqlite3_column_int64(stmt, 2)), u64(sqlite3_column_int64(stmt, 3)), first_key, sqlite3_column_int64(stmt, 5), sqlite3_column_int64(stmt, 6), true, ""
    }
    if rc == SQLITE_DONE {
        return sqlite_index_root_chunk_info_at_basis_wide_raw(handle, index_name, basis_tx)
    }
    return 0, 0, 0, 0, "", 0, 0, false, sqlite_error_text(db, "sqlite basis index root page chunk info read failed")
}

sqlite_index_root_page_set_at_basis_raw :: proc(handle: rawptr, basis_tx: u64) -> (u64, u64, u64, u64, u64, u64, u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COALESCE(MAX(CASE WHEN p.index_name = ':eavt' THEN p.root_chunk_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':aevt' THEN p.root_chunk_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':avet' THEN p.root_chunk_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':vaet' THEN p.root_chunk_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':eavt' THEN p.manifest_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':aevt' THEN p.manifest_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':avet' THEN p.manifest_id END), 0), COALESCE(MAX(CASE WHEN p.index_name = ':vaet' THEN p.manifest_id END), 0), COUNT(*) FROM (SELECT root_id FROM vev_index_roots WHERE basis_tx = ? ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare basis index root page set failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite bind basis index root page set failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        page_count := sqlite3_column_int64(stmt, 8)
        if page_count < 4 {
            return 0, 0, 0, 0, 0, 0, 0, 0, false, "sqlite DB has no normalized Vev index root pages for basis"
        }
        return u64(sqlite3_column_int64(stmt, 0)),
               u64(sqlite3_column_int64(stmt, 1)),
               u64(sqlite3_column_int64(stmt, 2)),
               u64(sqlite3_column_int64(stmt, 3)),
               u64(sqlite3_column_int64(stmt, 4)),
               u64(sqlite3_column_int64(stmt, 5)),
               u64(sqlite3_column_int64(stmt, 6)),
               u64(sqlite3_column_int64(stmt, 7)),
               true,
               ""
    }
    return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite basis index root page set read failed")
}

sqlite_index_root_set_at_basis_wide_raw :: proc(handle: rawptr, basis_tx: u64) -> (u64, u64, u64, u64, u64, u64, u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id FROM vev_index_roots WHERE basis_tx = ? ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare basis index root set failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite bind basis index root set failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)),
               u64(sqlite3_column_int64(stmt, 1)),
               u64(sqlite3_column_int64(stmt, 2)),
               u64(sqlite3_column_int64(stmt, 3)),
               u64(sqlite3_column_int64(stmt, 4)),
               u64(sqlite3_column_int64(stmt, 5)),
               u64(sqlite3_column_int64(stmt, 6)),
               u64(sqlite3_column_int64(stmt, 7)),
               true,
               ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, 0, 0, 0, 0, 0, 0, false, "sqlite DB has no Vev index root for basis"
    }
    return 0, 0, 0, 0, 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite basis index root set read failed")
}

sqlite_index_root_row_id_at_basis_raw :: proc(handle: rawptr, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT root_id FROM vev_index_roots WHERE basis_tx = ? ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare basis index root row id failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind basis index root row id failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite DB has no Vev index root for basis"
    }
    return 0, false, sqlite_error_text(db, "sqlite basis index root row id read failed")
}

sqlite_index_chunk_info_by_id_raw :: proc(handle: rawptr, chunk_id: u64) -> (u64, string, i64, bool, string) {
    if handle == nil {
        return 0, "", 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT row_count, first_key, level FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, "", 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, "", 0, false, sqlite_error_text(db, "sqlite prepare index chunk info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return 0, "", 0, false, sqlite_error_text(db, "sqlite bind index chunk info failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 1)
        if raw == nil {
            return 0, "", 0, false, "sqlite index chunk first key was null"
        }
        first_key, err := strings.clone_from_cstring(raw)
        if err != nil {
            return 0, "", 0, false, "failed to clone sqlite index chunk first key"
        }
        return u64(sqlite3_column_int64(stmt, 0)), first_key, sqlite3_column_int64(stmt, 2), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, "", 0, false, "sqlite index chunk was missing"
    }
    return 0, "", 0, false, sqlite_error_text(db, "sqlite index chunk info read failed")
}

sqlite_index_chunk_bounds_by_id_raw :: proc(handle: rawptr, chunk_id: u64) -> (string, string, bool, string) {
    if handle == nil {
        return "", "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT first_key, last_key FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", "", false, sqlite_error_text(db, "sqlite prepare index chunk bounds failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return "", "", false, sqlite_error_text(db, "sqlite bind index chunk bounds failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw_first := sqlite3_column_text(stmt, 0)
        raw_last := sqlite3_column_text(stmt, 1)
        if raw_first == nil || raw_last == nil {
            return "", "", false, "sqlite index chunk bound key was null"
        }
        first_key, first_err := strings.clone_from_cstring(raw_first)
        if first_err != nil {
            return "", "", false, "failed to clone sqlite index chunk first bound"
        }
        last_key, last_err := strings.clone_from_cstring(raw_last)
        if last_err != nil {
            delete(first_key)
            return "", "", false, "failed to clone sqlite index chunk last bound"
        }
        return first_key, last_key, true, ""
    }
    if rc == SQLITE_DONE {
        return "", "", false, "sqlite index chunk was missing"
    }
    return "", "", false, sqlite_error_text(db, "sqlite index chunk bounds read failed")
}

sqlite_index_child_chunk_id_raw :: proc(handle: rawptr, parent_chunk_id: u64, ordinal: i64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT child_chunk_id FROM vev_index_chunk_edges WHERE parent_chunk_id = ? AND ordinal = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index child chunk failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, ordinal) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index child chunk failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite index child chunk was missing"
    }
    return 0, false, sqlite_error_text(db, "sqlite index child chunk read failed")
}

sqlite_index_child_chunks_with_counts_raw :: proc(handle: rawptr, parent_chunk_id: u64) -> ([dynamic]u64, [dynamic]int, bool, string) {
    roots := make([dynamic]u64)
    counts := make([dynamic]int)
    if handle == nil {
        return roots, counts, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT edge.child_chunk_id, child.row_count FROM vev_index_chunk_edges edge JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id WHERE edge.parent_chunk_id = ? ORDER BY edge.ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return roots, counts, false, "failed to allocate sqlite child chunks SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return roots, counts, false, sqlite_error_text(db, "sqlite prepare index child chunks failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK {
        return roots, counts, false, sqlite_error_text(db, "sqlite bind index child chunks failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return roots, counts, false, sqlite_error_text(db, "sqlite index child chunks read failed")
        }
        append(&roots, u64(sqlite3_column_int64(stmt, 0)))
        append(&counts, int(sqlite3_column_int64(stmt, 1)))
    }
    return roots, counts, true, ""
}

sqlite_index_chunk_entries_page_text_raw :: proc(handle: rawptr, chunk_id: u64, offset: i64, limit: i64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    if offset < 0 {
        return "", false, "sqlite index chunk entries page offset was negative"
    }
    if limit <= 0 {
        return "[]", true, ""
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT '[' || COALESCE(group_concat(entry, ' '), '') || ']' FROM (SELECT entry FROM vev_index_chunk_entries WHERE chunk_id = ? AND ordinal >= ? AND ordinal < ? ORDER BY ordinal)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare index chunk entries page failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, offset) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, offset + limit) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind index chunk entries page failed")
    }
    rc := sqlite3_step(stmt)
    if rc != SQLITE_ROW {
        return "", false, sqlite_error_text(db, "sqlite index chunk entries page read failed")
    }
    raw := sqlite3_column_text(stmt, 0)
    if raw == nil {
        return "", false, "sqlite index chunk entries page was null"
    }
    out, err := strings.clone_from_cstring(raw)
    if err != nil {
        return "", false, "failed to clone sqlite index chunk entries page"
    }
    return out, true, ""
}

sqlite_index_chunk_entries_page_raw :: proc(handle: rawptr, chunk_id: u64, offset: i64, limit: i64) -> ([dynamic]int, bool, string) {
    out := make([dynamic]int, 0, int(limit))
    if handle == nil {
        return out, false, "sqlite handle was nil"
    }
    if offset < 0 {
        return out, false, "sqlite index chunk entries page offset was negative"
    }
    if limit <= 0 {
        return out, true, ""
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT entry FROM vev_index_chunk_entries WHERE chunk_id = ? AND ordinal >= ? AND ordinal < ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return out, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite prepare typed index chunk entries page failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, offset) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, offset + limit) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite bind typed index chunk entries page failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return out, false, sqlite_error_text(db, "sqlite typed index chunk entries page read failed")
        }
        append(&out, int(sqlite3_column_int64(stmt, 0)))
    }
    return out, true, ""
}

sqlite_prepare_index_chunk_entries_page_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT entry FROM vev_index_chunk_entries WHERE chunk_id = ? AND ordinal >= ? AND ordinal < ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite index chunk entries page SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare typed index chunk entries page failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_prepared_index_chunk_entries_page_raw :: proc(handle: rawptr, stmt_handle: rawptr, chunk_id: u64, offset: i64, limit: i64) -> ([dynamic]int, bool, string) {
    out := make([dynamic]int, 0, int(limit))
    if handle == nil {
        return out, false, "sqlite handle was nil"
    }
    if stmt_handle == nil {
        return out, false, "sqlite statement was nil"
    }
    if offset < 0 {
        return out, false, "sqlite index chunk entries page offset was negative"
    }
    if limit <= 0 {
        return out, true, ""
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, offset) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, offset + limit) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite bind typed index chunk entries page failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return out, false, sqlite_error_text(db, "sqlite typed index chunk entries page read failed")
        }
        append(&out, int(sqlite3_column_int64(stmt, 0)))
    }
    return out, true, ""
}

sqlite_index_chunk_entries_windows_raw :: proc(handle: rawptr, chunk_ids: []u64, starts: []int, limits: []int) -> ([dynamic]int, bool, string) {
    total := 0
    for limit in limits {
        total += limit
    }
    out := make([dynamic]int, 0, total)
    if handle == nil {
        return out, false, "sqlite handle was nil"
    }
    if len(chunk_ids) != len(starts) || len(chunk_ids) != len(limits) {
        return out, false, "sqlite batch index entries windows had mismatched input lengths"
    }
    if len(chunk_ids) == 0 || total == 0 {
        return out, true, ""
    }
    parts := make([dynamic]string, 0, len(chunk_ids) * 2 + 2)
    append(&parts, "WITH wanted(chunk_id, local_start, local_end, output_base) AS (VALUES ")
    output_base := 0
    for chunk_id, index in chunk_ids {
        if index > 0 {
            append(&parts, ",")
        }
        start := starts[index]
        limit := limits[index]
        append(&parts, fmt.tprintf("(%d,%d,%d,%d)", chunk_id, start, start + limit, output_base))
        output_base += limit
    }
    append(&parts, ") SELECT ce.entry FROM wanted JOIN vev_index_chunks c ON c.chunk_id = wanted.chunk_id AND c.payload_text = ':entries' JOIN vev_index_chunk_entries ce ON ce.chunk_id = wanted.chunk_id AND ce.ordinal >= wanted.local_start AND ce.ordinal < wanted.local_end ORDER BY wanted.output_base + (ce.ordinal - wanted.local_start)")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return out, false, "failed to allocate sqlite batch index entries SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite prepare batch index entries windows failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return out, false, sqlite_error_text(db, "sqlite batch index entries windows read failed")
        }
        append(&out, int(sqlite3_column_int64(stmt, 0)))
    }
    if len(out) != total {
        return out, false, "sqlite batch index entries windows did not return every requested entry"
    }
    return out, true, ""
}

sqlite_latest_index_entries_text_raw :: proc(handle: rawptr, index_name: string) -> (string, bool, string) {
    basis, row_count, root_id, root_ok, root_error := sqlite_latest_index_root_chunk_info_raw(handle, index_name)
    _ = basis
    if !root_ok {
        return "", false, root_error
    }
    text, base_offset, text_ok, text_error := sqlite_index_entries_page_text_for_root_raw(handle, root_id, 0, i64(row_count))
    _ = base_offset
    return text, text_ok, text_error
}

sqlite_latest_index_entries_page_text_raw :: proc(handle: rawptr, index_name: string, offset: i64, limit: i64) -> (string, i64, bool, string) {
    if offset < 0 {
        return "", 0, false, "sqlite index page offset was negative"
    }
    if limit <= 0 {
        return "[]", offset, true, ""
    }
    basis, row_count, root_id, root_ok, root_error := sqlite_latest_index_root_chunk_info_raw(handle, index_name)
    _ = basis
    _ = row_count
    if !root_ok {
        return "", 0, false, root_error
    }
    return sqlite_index_entries_page_text_for_root_raw(handle, root_id, offset, limit)
}

sqlite_index_entries_page_text_at_basis_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64, offset: i64, limit: i64) -> (string, i64, bool, string) {
    if offset < 0 {
        return "", 0, false, "sqlite index page offset was negative"
    }
    if limit <= 0 {
        return "[]", offset, true, ""
    }
    row_count, root_id, manifest_id, run_count, first_key, level, child_count, root_ok, root_error := sqlite_index_root_chunk_info_at_basis_raw(handle, index_name, basis_tx)
    _ = row_count
    _ = manifest_id
    _ = run_count
    _ = level
    _ = child_count
    if root_ok {
        delete(first_key)
        return sqlite_index_entries_page_text_for_root_raw(handle, root_id, offset, limit)
    }
    return "", 0, false, root_error
}

sqlite_index_entries_page_text_for_root_raw :: proc(handle: rawptr, root_id: u64, offset: i64, limit: i64) -> (string, i64, bool, string) {
    if handle == nil {
        return "", 0, false, "sqlite handle was nil"
    }
    if offset < 0 {
        return "", 0, false, "sqlite index root page offset was negative"
    }
    if limit <= 0 {
        return "[]", offset, true, ""
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT level, payload_text, row_count FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite prepare index root page failed")
    }
    if sqlite3_bind_int64(stmt, 1, i64(root_id)) != SQLITE_OK {
        _ = sqlite3_finalize(stmt)
        return "", 0, false, sqlite_error_text(db, "sqlite bind index root page failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_DONE {
        _ = sqlite3_finalize(stmt)
        return "", 0, false, "sqlite index root chunk was missing"
    }
    if rc != SQLITE_ROW {
        _ = sqlite3_finalize(stmt)
        return "", 0, false, sqlite_error_text(db, "sqlite index root page read failed")
    }
    level := sqlite3_column_int64(stmt, 0)
    if level == 0 {
        raw := sqlite3_column_text(stmt, 1)
        if raw == nil {
            _ = sqlite3_finalize(stmt)
            return "", 0, false, "sqlite index chunk payload was null"
        }
        out, out_ok := sqlite_column_text_owned(stmt, 1)
        _ = sqlite3_finalize(stmt)
        if !out_ok {
            return "", 0, false, "failed to clone sqlite index chunk payload"
        }
        if out == ":entries" {
            delete(out)
            entries, entries_ok, entries_error := sqlite_index_chunk_entries_page_text_raw(handle, root_id, offset, limit)
            return entries, offset, entries_ok, entries_error
        }
        return out, 0, true, ""
    }
    _ = sqlite3_finalize(stmt)

    child_stmt: ^SQLite3_Stmt
    child_sql := "WITH RECURSIVE tree(chunk_id, level, path, row_count, payload_text) AS (SELECT c.chunk_id, c.level, printf('%012d', 0), c.row_count, c.payload_text FROM vev_index_chunks c WHERE c.chunk_id = ? UNION ALL SELECT child.chunk_id, child.level, tree.path || '.' || printf('%012d', edge.ordinal), child.row_count, child.payload_text FROM tree JOIN vev_index_chunk_edges edge ON edge.parent_chunk_id = tree.chunk_id JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id), payloads AS (SELECT chunk_id, CASE WHEN level = 0 THEN path ELSE path || '.999999999999' END AS payload_path, CASE WHEN level = 0 THEN row_count ELSE row_count - COALESCE((SELECT SUM(child.row_count) FROM vev_index_chunk_edges edge JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id WHERE edge.parent_chunk_id = tree.chunk_id), 0) END AS row_count, payload_text FROM tree WHERE payload_text != '[]'), leaves AS (SELECT chunk_id, payload_path, row_count, payload_text, COALESCE(SUM(row_count) OVER (ORDER BY payload_path ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS base FROM payloads), selected AS (SELECT base, payload_path, chunk_id, row_count, payload_text FROM leaves WHERE base < ? AND base + row_count > ? ORDER BY payload_path), selected_payloads AS (SELECT base, payload_path, CASE WHEN payload_text = ':entries' THEN (SELECT COALESCE(group_concat(entry, ' '), '') FROM (SELECT entry FROM vev_index_chunk_entries WHERE chunk_id = selected.chunk_id ORDER BY ordinal)) ELSE substr(payload_text, 2, length(payload_text) - 2) END AS payload FROM selected) SELECT '[' || COALESCE(group_concat(payload, ' '), '') || ']', COALESCE(MIN(base), ?) FROM selected_payloads"
    child_sql_c, child_sql_c_ok := sqlite_cstring(child_sql)
    if !child_sql_c_ok {
        return "", 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(child_sql_c)
    if sqlite3_prepare_v2(db, child_sql_c, -1, &child_stmt, nil) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite prepare index root child page failed")
    }
    defer _ = sqlite3_finalize(child_stmt)
    if sqlite3_bind_int64(child_stmt, 1, i64(root_id)) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite bind index root child page failed")
    }
    if sqlite3_bind_int64(child_stmt, 2, offset + limit) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite bind index root child page offset failed")
    }
    if sqlite3_bind_int64(child_stmt, 3, offset) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite bind index root child page limit failed")
    }
    if sqlite3_bind_int64(child_stmt, 4, offset) != SQLITE_OK {
        return "", 0, false, sqlite_error_text(db, "sqlite bind index root child page base failed")
    }
    child_rc := sqlite3_step(child_stmt)
    if child_rc != SQLITE_ROW {
        return "", 0, false, sqlite_error_text(db, "sqlite index root child page read failed")
    }
    raw := sqlite3_column_text(child_stmt, 0)
    if raw == nil {
        return "", 0, false, "sqlite index root child page was null"
    }
    out, err := strings.clone_from_cstring(raw)
    if err != nil {
        return "", 0, false, "failed to clone sqlite index root child page"
    }
    return out, sqlite3_column_int64(child_stmt, 1), true, ""
}

sqlite_index_entry_runs_for_root_raw :: proc(handle: rawptr, root_id: u64) -> ([dynamic]u64, [dynamic]int, [dynamic]int, [dynamic]bool, bool, string) {
    roots := make([dynamic]u64)
    bases := make([dynamic]int)
    counts := make([dynamic]int)
    entry_payloads := make([dynamic]bool)
    if handle == nil {
        return roots, bases, counts, entry_payloads, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "WITH RECURSIVE tree(chunk_id, level, path, row_count, payload_text) AS (SELECT c.chunk_id, c.level, printf('%012d', 0), c.row_count, c.payload_text FROM vev_index_chunks c WHERE c.chunk_id = ? UNION ALL SELECT child.chunk_id, child.level, tree.path || '.' || printf('%012d', edge.ordinal), child.row_count, child.payload_text FROM tree JOIN vev_index_chunk_edges edge ON edge.parent_chunk_id = tree.chunk_id JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id), payloads AS (SELECT chunk_id, CASE WHEN level = 0 THEN path ELSE path || '.999999999999' END AS payload_path, CASE WHEN level = 0 THEN row_count ELSE row_count - COALESCE((SELECT SUM(child.row_count) FROM vev_index_chunk_edges edge JOIN vev_index_chunks child ON child.chunk_id = edge.child_chunk_id WHERE edge.parent_chunk_id = tree.chunk_id), 0) END AS row_count, payload_text FROM tree WHERE payload_text != '[]'), runs AS (SELECT chunk_id, payload_path, row_count, payload_text, COALESCE(SUM(row_count) OVER (ORDER BY payload_path ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS base FROM payloads WHERE row_count > 0) SELECT chunk_id, base, row_count, payload_text = ':entries' FROM runs ORDER BY payload_path"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return roots, bases, counts, entry_payloads, false, "failed to allocate sqlite index entry runs SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return roots, bases, counts, entry_payloads, false, sqlite_error_text(db, "sqlite prepare index entry runs failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(root_id)) != SQLITE_OK {
        return roots, bases, counts, entry_payloads, false, sqlite_error_text(db, "sqlite bind index entry runs failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return roots, bases, counts, entry_payloads, false, sqlite_error_text(db, "sqlite index entry runs read failed")
        }
        append(&roots, u64(sqlite3_column_int64(stmt, 0)))
        append(&bases, int(sqlite3_column_int64(stmt, 1)))
        append(&counts, int(sqlite3_column_int64(stmt, 2)))
        append(&entry_payloads, sqlite3_column_int(stmt, 3) != 0)
    }
    return roots, bases, counts, entry_payloads, true, ""
}

sqlite_clear_index_storage_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    return sqlite_exec_ok((^SQLite3)(handle), "DELETE FROM vev_index_roots; DELETE FROM vev_index_run_manifest_entity_attr_ranges; DELETE FROM vev_index_run_manifest_attr_ranges; DELETE FROM vev_index_run_manifest_runs; DELETE FROM vev_index_run_manifests; DELETE FROM vev_index_chunk_entries; DELETE FROM vev_index_chunk_edges; DELETE FROM vev_index_chunks;")
}

sqlite_insert_index_chunk_raw :: proc(handle: rawptr, index_name: string, level: i64, first_key: string, last_key: string, row_count: i64, child_count: i64, payload_text: string, checksum: string, created_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunks (index_name, level, first_key, last_key, row_count, child_count, payload_text, checksum, created_tx) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, level) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, first_key) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 4, last_key) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, row_count) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, child_count) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 7, payload_text) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 8, checksum) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, i64(created_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index chunk insert failed")
    }
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_prepare_insert_index_chunk_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunks (index_name, level, first_key, last_key, row_count, child_count, payload_text, checksum, created_tx) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index chunk insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_chunk_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, index_name: string, level: i64, first_key: string, last_key: string, row_count: i64, child_count: i64, payload_text: string, checksum: string, created_tx: u64) -> (u64, bool, string) {
    if handle == nil || stmt_handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, level) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, first_key) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 4, last_key) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, row_count) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, child_count) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 7, payload_text) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 8, checksum) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, i64(created_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index chunk insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_insert_index_chunk_entries_raw :: proc(handle: rawptr, chunk_id: u64, items: []int) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_entries (chunk_id, ordinal, entry) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index chunk entries insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for ordinal in 0..<len(items) {
        if sqlite3_reset(stmt) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite reset index chunk entries insert failed")
        }
        if sqlite3_clear_bindings(stmt) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite clear index chunk entries insert failed")
        }
        if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 3, i64(items[ordinal])) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite bind index chunk entries insert failed")
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            return false, sqlite_error_text(db, "sqlite index chunk entries insert failed")
        }
    }
    return true, ""
}

sqlite_prepare_insert_index_chunk_entry_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_entries (chunk_id, ordinal, entry) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index chunk entry insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_chunk_entry_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, chunk_id: u64, ordinal: i64, entry: i64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, entry) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk entry insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk entry insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_insert_index_root_with_manifests_raw :: proc(handle: rawptr, basis_tx: u64, eavt_chunk_id: u64, aevt_chunk_id: u64, avet_chunk_id: u64, vaet_chunk_id: u64, eavt_manifest_id: u64, aevt_manifest_id: u64, avet_manifest_id: u64, vaet_manifest_id: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_roots (basis_tx, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id) VALUES (?, 'single-chunk-index-v0', ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index root insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(eavt_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(aevt_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(avet_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(vaet_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(eavt_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(aevt_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 8, i64(avet_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, i64(vaet_manifest_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index root insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index root insert failed")
    }
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_prepare_insert_index_root_with_manifests_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_roots (basis_tx, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id) VALUES (?, 'single-chunk-index-v0', ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index root insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_root_with_manifests_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, basis_tx: u64, eavt_chunk_id: u64, aevt_chunk_id: u64, avet_chunk_id: u64, vaet_chunk_id: u64, eavt_manifest_id: u64, aevt_manifest_id: u64, avet_manifest_id: u64, vaet_manifest_id: u64) -> (u64, bool, string) {
    if handle == nil || stmt_handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(eavt_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(aevt_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(avet_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(vaet_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(eavt_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(aevt_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 8, i64(avet_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, i64(vaet_manifest_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index root insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index root insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_insert_index_root_raw :: proc(handle: rawptr, basis_tx: u64, eavt_chunk_id: u64, aevt_chunk_id: u64, avet_chunk_id: u64, vaet_chunk_id: u64) -> (u64, bool, string) {
    return sqlite_insert_index_root_with_manifests_raw(handle, basis_tx, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, 0, 0, 0, 0)
}

sqlite_insert_index_root_copy_latest_raw :: proc(handle: rawptr, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_roots (basis_tx, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id) SELECT ?, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id FROM vev_index_roots ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index root copy failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index root copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index root copy failed")
    }
    if sqlite3_changes(db) == 0 {
        return 0, false, "sqlite DB has no Vev index roots"
    }
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_prepare_insert_index_root_copy_latest_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_roots (basis_tx, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id) SELECT ?, format, eavt_chunk_id, aevt_chunk_id, avet_chunk_id, vaet_chunk_id, eavt_manifest_id, aevt_manifest_id, avet_manifest_id, vaet_manifest_id FROM vev_index_roots ORDER BY root_id DESC LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index root copy failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_root_copy_latest_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, basis_tx: u64) -> (u64, bool, string) {
    if handle == nil || stmt_handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(basis_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index root copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index root copy failed")
    }
    if sqlite3_changes(db) == 0 {
        return 0, false, "sqlite DB has no Vev index roots"
    }
    _ = sqlite3_clear_bindings(stmt)
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_insert_index_root_page_raw :: proc(handle: rawptr, root_id: u64, index_name: string, root_chunk_id: u64, manifest_id: u64, ordinal: i64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_root_pages (root_id, index_name, root_chunk_id, manifest_id, ordinal) VALUES (?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index root page insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(root_id)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(root_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index root page insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index root page insert failed")
    }
    return true, ""
}

sqlite_prepare_insert_index_root_page_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_root_pages (root_id, index_name, root_chunk_id, manifest_id, ordinal) VALUES (?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index root page insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_root_page_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, root_id: u64, index_name: string, root_chunk_id: u64, manifest_id: u64, ordinal: i64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(root_id)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(root_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index root page insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index root page insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_clear_latest_index_root_wide_columns_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    return sqlite_exec_ok(db, "UPDATE vev_index_roots SET eavt_chunk_id = NULL, aevt_chunk_id = NULL, avet_chunk_id = NULL, vaet_chunk_id = NULL, eavt_manifest_id = 0, aevt_manifest_id = 0, avet_manifest_id = 0, vaet_manifest_id = 0 WHERE root_id = (SELECT root_id FROM vev_index_roots ORDER BY root_id DESC LIMIT 1)")
}

sqlite_insert_index_run_manifest_with_parent_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64, parent_manifest_id: u64, base_chunk_id: u64, row_count: u64, run_count: u64, created_tx: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_run_manifests (index_name, basis_tx, parent_manifest_id, base_chunk_id, row_count, run_count, created_tx) VALUES (?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index run manifest insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(basis_tx)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(parent_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(base_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(row_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(run_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(created_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index run manifest insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index run manifest insert failed")
    }
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_insert_index_run_manifest_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64, base_chunk_id: u64, row_count: u64, run_count: u64, created_tx: u64) -> (u64, bool, string) {
    return sqlite_insert_index_run_manifest_with_parent_raw(handle, index_name, basis_tx, 0, base_chunk_id, row_count, run_count, created_tx)
}

sqlite_prepare_insert_index_run_manifest_with_parent_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_run_manifests (index_name, basis_tx, parent_manifest_id, base_chunk_id, row_count, run_count, created_tx) VALUES (?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index run manifest insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_run_manifest_with_parent_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, index_name: string, basis_tx: u64, parent_manifest_id: u64, base_chunk_id: u64, row_count: u64, run_count: u64, created_tx: u64) -> (u64, bool, string) {
    if handle == nil || stmt_handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(basis_tx)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(parent_manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(base_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(row_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(run_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(created_tx)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index run manifest insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return 0, false, sqlite_error_text(db, "sqlite index run manifest insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return u64(sqlite3_last_insert_rowid(db)), true, ""
}

sqlite_insert_index_run_manifest_run_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, run_chunk_id: u64, row_count: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_run_manifest_runs (manifest_id, ordinal, run_chunk_id, row_count, first_e, first_a, first_value_text, first_tx, first_added, last_e, last_a, last_value_text, last_tx, last_added) SELECT ?, ?, ?, ?, fd.e, fd.a, fd.value_text, fd.tx, fd.added, ld.e, ld.a, ld.value_text, ld.tx, ld.added FROM vev_index_chunks c JOIN vev_datoms fd ON fd.log_index = CAST(c.first_key AS INTEGER) JOIN vev_datoms ld ON ld.log_index = CAST(c.last_key AS INTEGER) WHERE c.chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index run manifest run insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(run_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(row_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(run_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest run insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest run insert failed")
    }
    return true, ""
}

sqlite_prepare_insert_index_run_manifest_run_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_run_manifest_runs (manifest_id, ordinal, run_chunk_id, row_count, first_e, first_a, first_value_text, first_tx, first_added, last_e, last_a, last_value_text, last_tx, last_added) SELECT ?, ?, ?, ?, fd.e, fd.a, fd.value_text, fd.tx, fd.added, ld.e, ld.a, ld.value_text, ld.tx, ld.added FROM vev_index_chunks c JOIN vev_datoms fd ON fd.log_index = CAST(c.first_key AS INTEGER) JOIN vev_datoms ld ON ld.log_index = CAST(c.last_key AS INTEGER) WHERE c.chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index run manifest run insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_run_manifest_run_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, manifest_id: u64, ordinal: u64, run_chunk_id: u64, row_count: u64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(run_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(row_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(run_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest run insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest run insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_prepare_insert_index_run_manifest_run_bounds_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_run_manifest_runs (manifest_id, ordinal, run_chunk_id, row_count, first_e, first_a, first_value_text, first_tx, first_added, last_e, last_a, last_value_text, last_tx, last_added) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index run manifest bounded run insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_run_manifest_run_bounds_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, manifest_id: u64, ordinal: u64, run_chunk_id: u64, row_count: u64, first_e: u64, first_a: string, first_value_text: string, first_tx: u64, first_added: bool, last_e: u64, last_a: string, last_value_text: string, last_tx: u64, last_added: bool) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(run_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(row_count)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(first_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 6, first_a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 7, first_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 8, i64(first_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 9, c.int(first_added ? 1 : 0)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 10, i64(last_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 11, last_a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 12, last_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 13, i64(last_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 14, c.int(last_added ? 1 : 0)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest bounded run insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest bounded run insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_insert_index_run_manifest_attr_ranges_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, run_chunk_id: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_run_manifest_attr_ranges (manifest_id, ordinal, attr, first_ordinal, first_e, first_value_text, first_tx, first_added, last_ordinal, last_e, last_value_text, last_tx, last_added) WITH ranked AS (SELECT d.a AS attr, ce.ordinal AS entry_ordinal, d.e AS e, d.value_text AS value_text, d.tx AS tx, d.added AS added, ROW_NUMBER() OVER (PARTITION BY d.a ORDER BY ce.ordinal) AS first_rank, ROW_NUMBER() OVER (PARTITION BY d.a ORDER BY ce.ordinal DESC) AS last_rank FROM vev_index_chunk_entries ce JOIN vev_datoms d ON d.log_index = ce.entry WHERE ce.chunk_id = ?), firsts AS (SELECT * FROM ranked WHERE first_rank = 1), lasts AS (SELECT * FROM ranked WHERE last_rank = 1) SELECT ?, ?, firsts.attr, firsts.entry_ordinal, firsts.e, firsts.value_text, firsts.tx, firsts.added, lasts.entry_ordinal, lasts.e, lasts.value_text, lasts.tx, lasts.added FROM firsts JOIN lasts ON lasts.attr = firsts.attr"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index run manifest attr ranges insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(run_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(ordinal)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest attr ranges insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest attr ranges insert failed")
    }
    return true, ""
}

sqlite_insert_index_run_manifest_attr_range_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, attr: string, first_ordinal: i64, first_e: u64, first_value_text: string, first_tx: u64, first_added: bool, last_ordinal: i64, last_e: u64, last_value_text: string, last_tx: u64, last_added: bool) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_run_manifest_attr_ranges (manifest_id, ordinal, attr, first_ordinal, first_e, first_value_text, first_tx, first_added, last_ordinal, last_e, last_value_text, last_tx, last_added) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index run manifest attr range direct insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, attr) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, first_ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(first_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 6, first_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(first_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 8, c.int(first_added ? 1 : 0)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, last_ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 10, i64(last_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 11, last_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 12, i64(last_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 13, c.int(last_added ? 1 : 0)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest attr range direct insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest attr range direct insert failed")
    }
    return true, ""
}

sqlite_prepare_insert_index_run_manifest_attr_range_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_run_manifest_attr_ranges (manifest_id, ordinal, attr, first_ordinal, first_e, first_value_text, first_tx, first_added, last_ordinal, last_e, last_value_text, last_tx, last_added) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index run manifest attr range direct insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_run_manifest_attr_range_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, manifest_id: u64, ordinal: u64, attr: string, first_ordinal: i64, first_e: u64, first_value_text: string, first_tx: u64, first_added: bool, last_ordinal: i64, last_e: u64, last_value_text: string, last_tx: u64, last_added: bool) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, attr) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, first_ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, i64(first_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 6, first_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, i64(first_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 8, c.int(first_added ? 1 : 0)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 9, last_ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 10, i64(last_e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 11, last_value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 12, i64(last_tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 13, c.int(last_added ? 1 : 0)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest attr range direct insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest attr range direct insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_index_run_manifest_entity_attr_range_parts_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, order_text: string, entity: u64, attr: string) -> (i64, i64, bool, bool, string) {
    if handle == nil {
        return -1, -1, false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT first_ordinal, last_ordinal FROM vev_index_run_manifest_entity_attr_ranges WHERE manifest_id = ? AND ordinal = ? AND order_text = ? AND entity = ? AND attr = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return -1, -1, false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return -1, -1, false, false, sqlite_error_text(db, "sqlite prepare index run manifest entity/attr range read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, order_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(entity)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 5, attr) != SQLITE_OK {
        return -1, -1, false, false, sqlite_error_text(db, "sqlite bind index run manifest entity/attr range read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return sqlite3_column_int64(stmt, 0), sqlite3_column_int64(stmt, 1), true, true, ""
    }
    if rc == SQLITE_DONE {
        return -1, -1, false, true, ""
    }
    return -1, -1, false, false, sqlite_error_text(db, "sqlite index run manifest entity/attr range read failed")
}

sqlite_insert_index_run_manifest_entity_attr_range_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, order_text: string, entity: u64, attr: string, first_ordinal: i64, last_ordinal: i64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_index_run_manifest_entity_attr_ranges (manifest_id, ordinal, order_text, entity, attr, first_ordinal, last_ordinal) VALUES (?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index run manifest entity/attr range direct insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, order_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, i64(entity)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 5, attr) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, first_ordinal) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 7, last_ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index run manifest entity/attr range direct insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index run manifest entity/attr range direct insert failed")
    }
    return true, ""
}

sqlite_index_run_manifest_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_run_manifests"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index run manifest count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    return 0, false, sqlite_error_text(db, "sqlite index run manifest count read failed")
}

sqlite_index_run_manifest_run_count_raw :: proc(handle: rawptr, manifest_id: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_run_manifest_runs WHERE manifest_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index run manifest run count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index run manifest run count failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    return 0, false, sqlite_error_text(db, "sqlite index run manifest run count read failed")
}

sqlite_index_run_manifest_info_raw :: proc(handle: rawptr, manifest_id: u64) -> (u64, u64, u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT parent_manifest_id, base_chunk_id, row_count, run_count FROM vev_index_run_manifests WHERE manifest_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare index run manifest info failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK {
        return 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite bind index run manifest info failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), u64(sqlite3_column_int64(stmt, 2)), u64(sqlite3_column_int64(stmt, 3)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, 0, 0, false, "sqlite index run manifest was not found"
    }
    return 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite index run manifest info read failed")
}

sqlite_index_run_manifest_run_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64) -> (u64, u64, bool, string) {
    if handle == nil {
        return 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT run_chunk_id, row_count FROM vev_index_run_manifest_runs WHERE manifest_id = ? AND ordinal = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite prepare index run manifest run read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK {
        return 0, 0, false, sqlite_error_text(db, "sqlite bind index run manifest run read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), u64(sqlite3_column_int64(stmt, 1)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, false, "sqlite index run manifest run was not found"
    }
    return 0, 0, false, sqlite_error_text(db, "sqlite index run manifest run read failed")
}

sqlite_index_run_manifest_run_bound_parts_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64) -> (u64, u64, u64, string, string, u64, bool, u64, string, string, u64, bool, bool, string) {
    if handle == nil {
        return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT run_chunk_id, row_count, first_e, first_a, first_value_text, first_tx, first_added, last_e, last_a, last_value_text, last_tx, last_added FROM vev_index_run_manifest_runs WHERE manifest_id = ? AND ordinal = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, sqlite_error_text(db, "sqlite prepare index run manifest bound read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK {
        return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, sqlite_error_text(db, "sqlite bind index run manifest bound read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        first_a_raw := sqlite3_column_text(stmt, 3)
        first_value_raw := sqlite3_column_text(stmt, 4)
        last_a_raw := sqlite3_column_text(stmt, 8)
        last_value_raw := sqlite3_column_text(stmt, 9)
        if first_a_raw == nil || first_value_raw == nil || last_a_raw == nil || last_value_raw == nil {
            return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "sqlite index run manifest bound text was null"
        }
        first_a, first_a_err := strings.clone_from_cstring(first_a_raw)
        if first_a_err != nil {
            return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "failed to clone sqlite index run manifest first attr"
        }
        first_value, first_value_err := strings.clone_from_cstring(first_value_raw)
        if first_value_err != nil {
            delete(first_a)
            return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "failed to clone sqlite index run manifest first value"
        }
        last_a, last_a_err := strings.clone_from_cstring(last_a_raw)
        if last_a_err != nil {
            delete(first_a)
            delete(first_value)
            return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "failed to clone sqlite index run manifest last attr"
        }
        last_value, last_value_err := strings.clone_from_cstring(last_value_raw)
        if last_value_err != nil {
            delete(first_a)
            delete(first_value)
            delete(last_a)
            return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "failed to clone sqlite index run manifest last value"
        }
        return u64(sqlite3_column_int64(stmt, 0)),
               u64(sqlite3_column_int64(stmt, 1)),
               u64(sqlite3_column_int64(stmt, 2)),
               first_a,
               first_value,
               u64(sqlite3_column_int64(stmt, 5)),
               sqlite3_column_int(stmt, 6) != 0,
               u64(sqlite3_column_int64(stmt, 7)),
               last_a,
               last_value,
               u64(sqlite3_column_int64(stmt, 10)),
               sqlite3_column_int(stmt, 11) != 0,
               true,
               ""
    }
    if rc == SQLITE_DONE {
        return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, "sqlite index run manifest bound row was not found"
    }
    return 0, 0, 0, "", "", 0, false, 0, "", "", 0, false, false, sqlite_error_text(db, "sqlite index run manifest bound read failed")
}

sqlite_index_run_manifest_run_bounds_parts_raw :: proc(handle: rawptr, manifest_id: u64) -> ([dynamic]u64, [dynamic]u64, [dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, [dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, bool, string) {
    roots := make([dynamic]u64)
    counts := make([dynamic]u64)
    first_entities := make([dynamic]u64)
    first_attrs := make([dynamic]string)
    first_values := make([dynamic]string)
    first_txs := make([dynamic]u64)
    first_added := make([dynamic]bool)
    last_entities := make([dynamic]u64)
    last_attrs := make([dynamic]string)
    last_values := make([dynamic]string)
    last_txs := make([dynamic]u64)
    last_added := make([dynamic]bool)
    if handle == nil {
        return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT run_chunk_id, row_count, first_e, first_a, first_value_text, first_tx, first_added, last_e, last_a, last_value_text, last_tx, last_added FROM vev_index_run_manifest_runs WHERE manifest_id = ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, sqlite_error_text(db, "sqlite prepare index run manifest bounds read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK {
        return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, sqlite_error_text(db, "sqlite bind index run manifest bounds read failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, true, ""
        }
        if rc != SQLITE_ROW {
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, sqlite_error_text(db, "sqlite index run manifest bounds read failed")
        }
        first_a_raw := sqlite3_column_text(stmt, 3)
        first_value_raw := sqlite3_column_text(stmt, 4)
        last_a_raw := sqlite3_column_text(stmt, 8)
        last_value_raw := sqlite3_column_text(stmt, 9)
        if first_a_raw == nil || first_value_raw == nil || last_a_raw == nil || last_value_raw == nil {
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "sqlite index run manifest bound text was null"
        }
        first_a, first_a_err := strings.clone_from_cstring(first_a_raw)
        if first_a_err != nil {
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "failed to clone sqlite index run manifest first attr"
        }
        first_value, first_value_err := strings.clone_from_cstring(first_value_raw)
        if first_value_err != nil {
            delete(first_a)
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "failed to clone sqlite index run manifest first value"
        }
        last_a, last_a_err := strings.clone_from_cstring(last_a_raw)
        if last_a_err != nil {
            delete(first_a)
            delete(first_value)
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "failed to clone sqlite index run manifest last attr"
        }
        last_value, last_value_err := strings.clone_from_cstring(last_value_raw)
        if last_value_err != nil {
            delete(first_a)
            delete(first_value)
            delete(last_a)
            return roots, counts, first_entities, first_attrs, first_values, first_txs, first_added, last_entities, last_attrs, last_values, last_txs, last_added, false, "failed to clone sqlite index run manifest last value"
        }
        append(&roots, u64(sqlite3_column_int64(stmt, 0)))
        append(&counts, u64(sqlite3_column_int64(stmt, 1)))
        append(&first_entities, u64(sqlite3_column_int64(stmt, 2)))
        append(&first_attrs, first_a)
        append(&first_values, first_value)
        append(&first_txs, u64(sqlite3_column_int64(stmt, 5)))
        append(&first_added, sqlite3_column_int(stmt, 6) != 0)
        append(&last_entities, u64(sqlite3_column_int64(stmt, 7)))
        append(&last_attrs, last_a)
        append(&last_values, last_value)
        append(&last_txs, u64(sqlite3_column_int64(stmt, 10)))
        append(&last_added, sqlite3_column_int(stmt, 11) != 0)
    }
}

sqlite_index_run_manifest_attr_range_parts_raw :: proc(handle: rawptr, manifest_id: u64, ordinal: u64, attr: string) -> (i64, u64, string, u64, bool, i64, u64, string, u64, bool, bool, bool, string) {
    if handle == nil {
        return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT first_ordinal, first_e, first_value_text, first_tx, first_added, last_ordinal, last_e, last_value_text, last_tx, last_added FROM vev_index_run_manifest_attr_ranges WHERE manifest_id = ? AND ordinal = ? AND attr = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, sqlite_error_text(db, "sqlite prepare index run manifest attr range read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(manifest_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(ordinal)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, attr) != SQLITE_OK {
        return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, sqlite_error_text(db, "sqlite bind index run manifest attr range read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        first_value_raw := sqlite3_column_text(stmt, 2)
        last_value_raw := sqlite3_column_text(stmt, 7)
        if first_value_raw == nil || last_value_raw == nil {
            return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, "sqlite index run manifest attr range value was null"
        }
        first_value, first_value_err := strings.clone_from_cstring(first_value_raw)
        if first_value_err != nil {
            return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, "failed to clone sqlite index run manifest attr first value"
        }
        last_value, last_value_err := strings.clone_from_cstring(last_value_raw)
        if last_value_err != nil {
            delete(first_value)
            return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, "failed to clone sqlite index run manifest attr last value"
        }
        return sqlite3_column_int64(stmt, 0),
               u64(sqlite3_column_int64(stmt, 1)),
               first_value,
               u64(sqlite3_column_int64(stmt, 3)),
               sqlite3_column_int(stmt, 4) != 0,
               sqlite3_column_int64(stmt, 5),
               u64(sqlite3_column_int64(stmt, 6)),
               last_value,
               u64(sqlite3_column_int64(stmt, 8)),
               sqlite3_column_int(stmt, 9) != 0,
               true,
               true,
               ""
    }
    if rc == SQLITE_DONE {
        return -1, 0, "", 0, false, -1, 0, "", 0, false, false, true, ""
    }
    return -1, 0, "", 0, false, -1, 0, "", 0, false, false, false, sqlite_error_text(db, "sqlite index run manifest attr range read failed")
}

sqlite_enqueue_index_maintenance_raw :: proc(handle: rawptr, index_name: string, basis_tx: u64, root_chunk_id: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR IGNORE INTO vev_index_maintenance (index_name, basis_tx, root_chunk_id) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index maintenance enqueue failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(basis_tx)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, i64(root_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index maintenance enqueue failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index maintenance enqueue failed")
    }
    return true, ""
}

sqlite_delete_index_maintenance_for_index_raw :: proc(handle: rawptr, index_name: string) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "DELETE FROM vev_index_maintenance WHERE index_name = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index maintenance delete-by-index failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, index_name) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index maintenance delete-by-index failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index maintenance delete-by-index failed")
    }
    return true, ""
}

sqlite_next_index_maintenance_raw :: proc(handle: rawptr) -> (u64, string, u64, u64, bool, bool, string) {
    if handle == nil {
        return 0, "", 0, 0, false, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT id, index_name, basis_tx, root_chunk_id FROM vev_index_maintenance ORDER BY id LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, "", 0, 0, false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, "", 0, 0, false, false, sqlite_error_text(db, "sqlite prepare index maintenance next failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_DONE {
        return 0, "", 0, 0, false, true, ""
    }
    if rc != SQLITE_ROW {
        return 0, "", 0, 0, false, false, sqlite_error_text(db, "sqlite index maintenance next read failed")
    }
    raw := sqlite3_column_text(stmt, 1)
    if raw == nil {
        return 0, "", 0, 0, false, false, "sqlite index maintenance name was null"
    }
    index_name_out, err := strings.clone_from_cstring(raw)
    if err != nil {
        return 0, "", 0, 0, false, false, "failed to clone sqlite index maintenance name"
    }
    return u64(sqlite3_column_int64(stmt, 0)), index_name_out, u64(sqlite3_column_int64(stmt, 2)), u64(sqlite3_column_int64(stmt, 3)), true, true, ""
}

sqlite_delete_index_maintenance_raw :: proc(handle: rawptr, id: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "DELETE FROM vev_index_maintenance WHERE id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index maintenance delete failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index maintenance delete failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index maintenance delete failed")
    }
    return true, ""
}

sqlite_index_maintenance_count_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_index_maintenance"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index maintenance count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    return 0, false, sqlite_error_text(db, "sqlite index maintenance count read failed")
}

sqlite_insert_index_chunk_edge_raw :: proc(handle: rawptr, parent_chunk_id: u64, child_chunk_id: u64, ordinal: i64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index chunk edge insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(child_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk edge insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk edge insert failed")
    }
    return true, ""
}

sqlite_prepare_insert_index_chunk_edge_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index chunk edge insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_index_chunk_edge_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, parent_chunk_id: u64, child_chunk_id: u64, ordinal: i64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(child_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk edge insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk edge insert failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_insert_index_chunk_edges_raw :: proc(handle: rawptr, parent_chunk_id: u64, child_chunk_ids: []u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index chunk edge insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for ordinal in 0..<len(child_chunk_ids) {
        if sqlite3_reset(stmt) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite reset index chunk edge insert failed")
        }
        if sqlite3_clear_bindings(stmt) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite clear index chunk edge insert failed")
        }
        if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 2, i64(child_chunk_ids[ordinal])) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 3, i64(ordinal)) != SQLITE_OK {
            return false, sqlite_error_text(db, "sqlite bind index chunk edge insert failed")
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            return false, sqlite_error_text(db, "sqlite index chunk edge insert failed")
        }
    }
    return true, ""
}

sqlite_index_chunk_level_raw :: proc(handle: rawptr, chunk_id: u64) -> (i64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT level FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk level failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk level failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return sqlite3_column_int64(stmt, 0), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite index chunk was missing"
    }
    return 0, false, sqlite_error_text(db, "sqlite index chunk level read failed")
}

sqlite_index_chunk_payload_text_raw :: proc(handle: rawptr, chunk_id: u64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT payload_text FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare index chunk payload failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind index chunk payload failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 0)
        if raw == nil {
            return "", false, "sqlite index chunk payload was null"
        }
        out, err := strings.clone_from_cstring(raw)
        if err != nil {
            return "", false, "failed to clone sqlite index chunk payload"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite index chunk was missing"
    }
    return "", false, sqlite_error_text(db, "sqlite index chunk payload read failed")
}

sqlite_index_chunk_checksum_text_raw :: proc(handle: rawptr, chunk_id: u64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT checksum FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare index chunk checksum failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind index chunk checksum failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        raw := sqlite3_column_text(stmt, 0)
        if raw == nil {
            return "", false, "sqlite index chunk checksum was null"
        }
        out, err := strings.clone_from_cstring(raw)
        if err != nil {
            return "", false, "failed to clone sqlite index chunk checksum"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite index chunk was missing"
    }
    return "", false, sqlite_error_text(db, "sqlite index chunk checksum read failed")
}

sqlite_index_chunk_row_count_by_id_raw :: proc(handle: rawptr, chunk_id: u64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT row_count FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk row count failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(chunk_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk row count failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite index chunk was missing"
    }
    return 0, false, sqlite_error_text(db, "sqlite index chunk row count read failed")
}

sqlite_index_chunk_child_count_raw :: proc(handle: rawptr, parent_chunk_id: u64) -> (i64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT level, child_count FROM vev_index_chunks WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk child count metadata failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk child count metadata failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        level := sqlite3_column_int64(stmt, 0)
        child_count := sqlite3_column_int64(stmt, 1)
        if level == 0 || child_count > 0 {
            return child_count, true, ""
        }
    } else if rc == SQLITE_DONE {
        return 0, false, "sqlite index chunk was missing"
    } else {
        return 0, false, sqlite_error_text(db, "sqlite index chunk child count metadata read failed")
    }
    edge_stmt: ^SQLite3_Stmt
    edge_sql := "SELECT COUNT(*) FROM vev_index_chunk_edges WHERE parent_chunk_id = ?"
    edge_sql_c, edge_sql_c_ok := sqlite_cstring(edge_sql)
    if !edge_sql_c_ok {
        return 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(edge_sql_c)
    if sqlite3_prepare_v2(db, edge_sql_c, -1, &edge_stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare index chunk child count failed")
    }
    defer _ = sqlite3_finalize(edge_stmt)
    if sqlite3_bind_int64(edge_stmt, 1, i64(parent_chunk_id)) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind index chunk child count failed")
    }
    edge_rc := sqlite3_step(edge_stmt)
    if edge_rc == SQLITE_ROW {
        return sqlite3_column_int64(edge_stmt, 0), true, ""
    }
    return 0, false, sqlite_error_text(db, "sqlite index chunk child count read failed")
}

sqlite_clear_index_chunk_child_count_raw :: proc(handle: rawptr, parent_chunk_id: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "UPDATE vev_index_chunks SET child_count = 0 WHERE chunk_id = ?"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index chunk child count clear failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk child count clear failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk child count clear failed")
    }
    return true, ""
}

sqlite_copy_index_chunk_edges_raw :: proc(handle: rawptr, parent_chunk_id: u64, source_parent_chunk_id: u64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) SELECT ?, child_chunk_id, ordinal FROM vev_index_chunk_edges WHERE parent_chunk_id = ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare index chunk edge copy failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(source_parent_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk edge copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk edge copy failed")
    }
    return true, ""
}

sqlite_prepare_copy_index_chunk_edges_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) SELECT ?, child_chunk_id, ordinal FROM vev_index_chunk_edges WHERE parent_chunk_id = ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare index chunk edge copy failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_copy_index_chunk_edges_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, parent_chunk_id: u64, source_parent_chunk_id: u64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(source_parent_chunk_id)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind index chunk edge copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite index chunk edge copy failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_copy_index_chunk_edges_before_ordinal_raw :: proc(handle: rawptr, parent_chunk_id: u64, source_parent_chunk_id: u64, before_ordinal: i64) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    if before_ordinal <= 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) SELECT ?, child_chunk_id, ordinal FROM vev_index_chunk_edges WHERE parent_chunk_id = ? AND ordinal < ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare bounded index chunk edge copy failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(source_parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, before_ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind bounded index chunk edge copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite bounded index chunk edge copy failed")
    }
    return true, ""
}

sqlite_prepare_copy_index_chunk_edges_before_ordinal_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_index_chunk_edges (parent_chunk_id, child_chunk_id, ordinal) SELECT ?, child_chunk_id, ordinal FROM vev_index_chunk_edges WHERE parent_chunk_id = ? AND ordinal < ? ORDER BY ordinal"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare bounded index chunk edge copy failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_copy_index_chunk_edges_before_ordinal_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, parent_chunk_id: u64, source_parent_chunk_id: u64, before_ordinal: i64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    if before_ordinal <= 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(source_parent_chunk_id)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, before_ordinal) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind bounded index chunk edge copy failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite bounded index chunk edge copy failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_insert_datom_raw :: proc(handle: rawptr, log_index: i64, e: u64, a: string, value_text: string, value_entity: i64, tx: u64, added: bool) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    tx_ok, tx_error := sqlite_insert_tx_raw(handle, tx)
    if !tx_ok {
        return false, tx_error
    }
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_datoms (log_index, e, a, value_text, value_entity, tx, added) VALUES (?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare datom failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 4, value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, value_entity) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 7, c.int(added ? 1 : 0)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind datom failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert datom failed")
    }
    _, _ = sqlite_insert_fulltext_datom_raw(handle, log_index, a, value_text, added)
    terms_ok, terms_error := sqlite_insert_text_terms_for_datom_raw(handle, log_index, a, value_text, added)
    if !terms_ok {
        return false, terms_error
    }
    return true, ""
}

sqlite_insert_fulltext_datom_raw :: proc(handle: rawptr, log_index: i64, a: string, value_text: string, added: bool) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    if !added || log_index < 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_fulltext(rowid, attr, value_text, log_index) VALUES (?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite fulltext insert SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare fulltext datom failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, log_index) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind fulltext datom failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert fulltext datom failed")
    }
    return true, ""
}

sqlite_prepare_insert_fulltext_datom_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR REPLACE INTO vev_fulltext(rowid, attr, value_text, log_index) VALUES (?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite fulltext insert SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare fulltext datom failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_fulltext_datom_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64, a: string, value_text: string, added: bool) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    if !added || log_index < 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 4, log_index) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind fulltext datom failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert fulltext datom failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_text_term_char_ok :: proc(ch: u8) -> bool {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
}

sqlite_text_term_lower :: proc(ch: u8) -> u8 {
    if ch >= 'A' && ch <= 'Z' {
        return ch + ('a' - 'A')
    }
    return ch
}

sqlite_insert_text_term_raw :: proc(db: ^SQLite3, log_index: i64, a: string, term: string) -> (bool, string) {
    if len(term) == 0 {
        return true, ""
    }
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR IGNORE INTO vev_text_terms(attr, term, log_index) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite text term insert SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare text term insert failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, term) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, log_index) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind text term insert failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert text term failed")
    }
    return true, ""
}

sqlite_prepare_insert_text_term_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR IGNORE INTO vev_text_terms(attr, term, log_index) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite text term insert SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare text term insert failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_text_term_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64, a: string, term: string) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    if len(term) == 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, term) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 3, log_index) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind text term failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert text term failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_insert_text_terms_for_datom_raw :: proc(handle: rawptr, log_index: i64, a: string, value_text: string, added: bool) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    if !added || log_index < 0 {
        return true, ""
    }
    db := (^SQLite3)(handle)
    token := make([dynamic]u8, 0, 32)
    defer delete(token)
    flush_token :: proc(db: ^SQLite3, log_index: i64, a: string, token: ^[dynamic]u8) -> (bool, string) {
        if len(token^) == 0 {
            return true, ""
        }
        term := string(token^[:])
        ok, err := sqlite_insert_text_term_raw(db, log_index, a, term)
        clear(token)
        return ok, err
    }
    for i := 0; i < len(value_text); i += 1 {
        ch := value_text[i]
        if sqlite_text_term_char_ok(ch) {
            append(&token, sqlite_text_term_lower(ch))
        } else {
            ok, err := flush_token(db, log_index, a, &token)
            if !ok {
                return false, err
            }
        }
    }
    return flush_token(db, log_index, a, &token)
}

sqlite_insert_text_terms_for_datom_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64, a: string, value_text: string, added: bool) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    if !added || log_index < 0 {
        return true, ""
    }
    token := make([dynamic]u8, 0, 32)
    defer delete(token)
    flush_token :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64, a: string, token: ^[dynamic]u8) -> (bool, string) {
        if len(token^) == 0 {
            return true, ""
        }
        term := string(token^[:])
        ok, err := sqlite_step_text_term_stmt_raw(handle, stmt_handle, log_index, a, term)
        clear(token)
        return ok, err
    }
    for i := 0; i < len(value_text); i += 1 {
        ch := value_text[i]
        if sqlite_text_term_char_ok(ch) {
            append(&token, sqlite_text_term_lower(ch))
        } else {
            ok, err := flush_token(handle, stmt_handle, log_index, a, &token)
            if !ok {
                return false, err
            }
        }
    }
    return flush_token(handle, stmt_handle, log_index, a, &token)
}

sqlite_text_terms_count_raw :: proc(handle: rawptr) -> i64 {
    if handle == nil {
        return -1
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT COUNT(*) FROM vev_text_terms"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return -1
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return -1
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_step(stmt) == SQLITE_ROW {
        return sqlite3_column_int64(stmt, 0)
    }
    return -1
}

sqlite_rebuild_text_terms_raw :: proc(handle: rawptr) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    clear_ok, clear_err := sqlite_exec_ok(db, "DELETE FROM vev_text_terms")
    if !clear_ok {
        return false, clear_err
    }
    stmt: ^SQLite3_Stmt
    sql := "SELECT log_index, a, value_text, added FROM vev_datoms WHERE added = 1 AND log_index >= 0 ORDER BY log_index, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite text term rebuild SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare text term rebuild failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return false, sqlite_error_text(db, "sqlite text term rebuild read failed")
        }
        a_text, a_ok := sqlite_column_text_owned(stmt, 1)
        if !a_ok {
            return false, "sqlite text term rebuild row had null attr text"
        }
        value_text, value_ok := sqlite_column_text_owned(stmt, 2)
        if !value_ok {
            delete(a_text)
            return false, "sqlite text term rebuild row had null value text"
        }
        ok, err := sqlite_insert_text_terms_for_datom_raw(handle, sqlite3_column_int64(stmt, 0), a_text, value_text, sqlite3_column_int(stmt, 3) != 0)
        delete(a_text)
        delete(value_text)
        if !ok {
            return false, err
        }
    }
    return true, ""
}

sqlite_prepare_insert_tx_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT OR IGNORE INTO vev_transactions (tx) VALUES (?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare tx failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_prepare_insert_datom_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_datoms (log_index, e, a, value_text, value_entity, tx, added) VALUES (?, ?, ?, ?, ?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare datom failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_prepare_datom_by_log_index_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE log_index = ? ORDER BY id LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare datom log-index read failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_finalize_stmt_raw :: proc(stmt_handle: rawptr) {
    if stmt_handle != nil {
        _ = sqlite3_finalize((^SQLite3_Stmt)(stmt_handle))
    }
}

sqlite_step_tx_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, tx: u64) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind tx failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert tx failed")
    }
    return true, ""
}

sqlite_step_prepared_datom_by_log_index_text_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    if stmt_handle == nil {
        return "", false, "sqlite datom text statement was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind datom log-index read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            return "", false, "sqlite datom row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            return "", false, "failed to clone sqlite datom attr"
        }
        defer delete(a_text)
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            return "", false, "failed to clone sqlite datom value"
        }
        defer delete(value_text)
        formatted := fmt.tprintf("[%d %s %s %d %v]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text,
            sqlite3_column_int64(stmt, 3),
            sqlite3_column_int(stmt, 4) != 0)
        out, out_err := strings.clone(formatted)
        if out_err != nil {
            return "", false, "failed to clone sqlite datom log-index text"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite datom log-index not found"
    }
    return "", false, sqlite_error_text(db, "sqlite datom log-index read failed")
}

sqlite_step_prepared_datom_by_log_index_parts_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64) -> (u64, string, string, u64, bool, bool, string) {
    if handle == nil {
        return 0, "", "", 0, false, false, "sqlite handle was nil"
    }
    if stmt_handle == nil {
        return 0, "", "", 0, false, false, "sqlite datom parts statement was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK {
        return 0, "", "", 0, false, false, sqlite_error_text(db, "sqlite bind datom log-index read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            return 0, "", "", 0, false, false, "sqlite datom row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            return 0, "", "", 0, false, false, "failed to clone sqlite datom attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            return 0, "", "", 0, false, false, "failed to clone sqlite datom value"
        }
        return u64(sqlite3_column_int64(stmt, 0)),
               a_text,
               value_text,
               u64(sqlite3_column_int64(stmt, 3)),
               sqlite3_column_int(stmt, 4) != 0,
               true,
               ""
    }
    if rc == SQLITE_DONE {
        return 0, "", "", 0, false, false, "sqlite datom log-index not found"
    }
    return 0, "", "", 0, false, false, sqlite_error_text(db, "sqlite datom log-index read failed")
}

sqlite_step_prepared_datom_entity_by_log_index_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    if stmt_handle == nil {
        return 0, false, "sqlite datom entity statement was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite bind datom log-index entity read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return u64(sqlite3_column_int64(stmt, 0)), true, ""
    }
    if rc == SQLITE_DONE {
        return 0, false, "sqlite datom log-index not found"
    }
    return 0, false, sqlite_error_text(db, "sqlite datom log-index entity read failed")
}

sqlite_step_prepared_datom_attr_by_log_index_raw :: proc(handle: rawptr, stmt_handle: rawptr, log_index: i64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    if stmt_handle == nil {
        return "", false, "sqlite datom attr statement was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind datom log-index attr read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        a_raw := sqlite3_column_text(stmt, 1)
        if a_raw == nil {
            return "", false, "sqlite datom row had null attr text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            return "", false, "failed to clone sqlite datom attr"
        }
        return a_text, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite datom log-index not found"
    }
    return "", false, sqlite_error_text(db, "sqlite datom log-index attr read failed")
}

sqlite_load_datoms_by_log_indexes_parts_raw :: proc(handle: rawptr, entries: []int) -> ([dynamic]int, [dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, bool, string) {
    ordinals := make([dynamic]int, 0, len(entries))
    entities := make([dynamic]u64, 0, len(entries))
    attrs := make([dynamic]string, 0, len(entries))
    values := make([dynamic]string, 0, len(entries))
    txs := make([dynamic]u64, 0, len(entries))
    added := make([dynamic]bool, 0, len(entries))
    if handle == nil {
        return ordinals, entities, attrs, values, txs, added, false, "sqlite handle was nil"
    }
    if len(entries) == 0 {
        return ordinals, entities, attrs, values, txs, added, true, ""
    }
    parts := make([dynamic]string, 0, len(entries) * 2 + 2)
    append(&parts, "WITH wanted(log_index, ordinal) AS (VALUES ")
    for entry, index in entries {
        if index > 0 {
            append(&parts, ",")
        }
        append(&parts, fmt.tprintf("(%d,%d)", entry, index))
    }
    append(&parts, ") SELECT wanted.ordinal, d.e, d.a, d.value_text, d.tx, d.added FROM wanted JOIN vev_datoms d ON d.log_index = wanted.log_index ORDER BY wanted.ordinal")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return ordinals, entities, attrs, values, txs, added, false, "failed to allocate sqlite batch datom SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return ordinals, entities, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite prepare batch datom read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return ordinals, entities, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite batch datom read failed")
        }
        a_text, a_ok := sqlite_column_text_owned(stmt, 2)
        if !a_ok {
            return ordinals, entities, attrs, values, txs, added, false, "sqlite batch datom row had null attr text"
        }
        value_text, value_ok := sqlite_column_text_owned(stmt, 3)
        if !value_ok {
            delete(a_text)
            return ordinals, entities, attrs, values, txs, added, false, "sqlite batch datom row had null value text"
        }
        append(&ordinals, int(sqlite3_column_int64(stmt, 0)))
        append(&entities, u64(sqlite3_column_int64(stmt, 1)))
        append(&attrs, a_text)
        append(&values, value_text)
        append(&txs, u64(sqlite3_column_int64(stmt, 4)))
        append(&added, sqlite3_column_int(stmt, 5) != 0)
    }
    return ordinals, entities, attrs, values, txs, added, true, ""
}

sqlite_direct_frontier_log_indexes_raw :: proc(handle: rawptr, order_text: string, entities: []u64, attr: string) -> ([dynamic]int, bool, string) {
    out := make([dynamic]int)
    if handle == nil {
        return out, false, "sqlite handle was nil"
    }
    if len(entities) == 0 {
        return out, true, ""
    }
    if len(entities) == 1 {
        db := (^SQLite3)(handle)
        stmt: ^SQLite3_Stmt
        sql := ""
        if order_text == ":eavt" {
            sql = "SELECT d.log_index FROM vev_datoms d INDEXED BY vev_datoms_eavt WHERE d.e = ? AND d.a = ? ORDER BY d.value_text, d.tx, d.added"
        } else if order_text == ":vaet" {
            sql = "SELECT d.log_index FROM vev_datoms d INDEXED BY vev_datoms_vaet_entity WHERE d.value_entity = ? AND d.a = ? ORDER BY d.e, d.tx, d.added"
        } else {
            return out, false, "sqlite direct frontier only supports :eavt and :vaet"
        }
        sql_c, sql_c_ok := sqlite_cstring(sql)
        if !sql_c_ok {
            return out, false, "failed to allocate sqlite direct frontier SQL text"
        }
        defer delete(sql_c)
        if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
            return out, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
        }
        defer _ = sqlite3_finalize(stmt)
        if sqlite3_bind_int64(stmt, 1, i64(entities[0])) != SQLITE_OK ||
           sqlite_bind_text_borrowed(stmt, 2, attr) != SQLITE_OK {
            return out, false, sqlite_error_text(db, "sqlite bind direct frontier prefix failed")
        }
        for {
            rc := sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                break
            }
            if rc != SQLITE_ROW {
                return out, false, sqlite_error_text(db, "sqlite direct frontier read failed")
            }
            append(&out, int(sqlite3_column_int64(stmt, 0)))
        }
        return out, true, ""
    }
    if len(entities) <= 256 {
        db := (^SQLite3)(handle)
        stmt: ^SQLite3_Stmt
        sql := ""
        if order_text == ":eavt" {
            sql = "SELECT d.log_index FROM vev_datoms d INDEXED BY vev_datoms_eavt WHERE d.e = ? AND d.a = ? ORDER BY d.value_text, d.tx, d.added"
        } else if order_text == ":vaet" {
            sql = "SELECT d.log_index FROM vev_datoms d INDEXED BY vev_datoms_vaet_entity WHERE d.value_entity = ? AND d.a = ? ORDER BY d.e, d.tx, d.added"
        } else {
            return out, false, "sqlite direct frontier only supports :eavt and :vaet"
        }
        sql_c, sql_c_ok := sqlite_cstring(sql)
        if !sql_c_ok {
            return out, false, "failed to allocate sqlite direct frontier SQL text"
        }
        defer delete(sql_c)
        if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
            return out, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
        }
        defer _ = sqlite3_finalize(stmt)
        for entity in entities {
            if sqlite3_reset(stmt) != SQLITE_OK ||
               sqlite3_clear_bindings(stmt) != SQLITE_OK ||
               sqlite3_bind_int64(stmt, 1, i64(entity)) != SQLITE_OK ||
               sqlite_bind_text_borrowed(stmt, 2, attr) != SQLITE_OK {
                return out, false, sqlite_error_text(db, "sqlite bind direct frontier prefix failed")
            }
            for {
                rc := sqlite3_step(stmt)
                if rc == SQLITE_DONE {
                    break
                }
                if rc != SQLITE_ROW {
                    return out, false, sqlite_error_text(db, "sqlite direct frontier read failed")
                }
                append(&out, int(sqlite3_column_int64(stmt, 0)))
            }
        }
        return out, true, ""
    }
    parts := make([dynamic]string, 0, len(entities) * 2 + 2)
    if order_text == ":eavt" {
        append(&parts, "WITH wanted(e, ordinal) AS (VALUES ")
        for entity, index in entities {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, fmt.tprintf("(%d,%d)", entity, index))
        }
        append(&parts, ") SELECT d.log_index FROM wanted JOIN vev_datoms d INDEXED BY vev_datoms_eavt ON d.e = wanted.e AND d.a = ? ORDER BY wanted.ordinal, d.value_text, d.tx, d.added")
    } else if order_text == ":vaet" {
        append(&parts, "WITH wanted(value_entity, ordinal) AS (VALUES ")
        for entity, index in entities {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, fmt.tprintf("(%d,%d)", entity, index))
        }
        append(&parts, ") SELECT d.log_index FROM wanted JOIN vev_datoms d INDEXED BY vev_datoms_vaet_entity ON d.value_entity = wanted.value_entity AND d.a = ? ORDER BY wanted.ordinal, d.e, d.tx, d.added")
    } else {
        delete(parts)
        return out, false, "sqlite direct frontier only supports :eavt and :vaet"
    }
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return out, false, "failed to allocate sqlite direct frontier SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return out, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if order_text == ":eavt" {
        if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK {
            return out, false, sqlite_error_text(db, "sqlite bind direct eavt frontier attr failed")
        }
    } else {
        if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK {
            return out, false, sqlite_error_text(db, "sqlite bind direct vaet frontier attr failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return out, false, sqlite_error_text(db, "sqlite direct frontier read failed")
        }
        append(&out, int(sqlite3_column_int64(stmt, 0)))
    }
    return out, true, ""
}

sqlite_direct_frontier_datom_parts_raw :: proc(handle: rawptr, order_text: string, entities: []u64, attr: string) -> ([dynamic]u64, [dynamic]string, [dynamic]i64, [dynamic]u64, [dynamic]bool, bool, string) {
    entities_out := make([dynamic]u64, 0)
    values := make([dynamic]string, 0)
    value_entities := make([dynamic]i64, 0)
    txs := make([dynamic]u64, 0)
    added := make([dynamic]bool, 0)
    if handle == nil {
        return entities_out, values, value_entities, txs, added, false, "sqlite handle was nil"
    }
    if len(entities) == 0 {
        return entities_out, values, value_entities, txs, added, true, ""
    }
    if len(entities) == 1 {
        db := (^SQLite3)(handle)
        stmt: ^SQLite3_Stmt
        sql := ""
        if order_text == ":eavt" {
            sql = "SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_eavt_entity_cover WHERE d.e = ? AND d.a = ? ORDER BY d.value_text, d.tx, d.added"
        } else if order_text == ":vaet" {
            sql = "SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_vaet_entity WHERE d.value_entity = ? AND d.a = ? ORDER BY d.e, d.tx, d.added"
        } else {
            return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier only supports :eavt and :vaet"
        }
        sql_c, sql_c_ok := sqlite_cstring(sql)
        if !sql_c_ok {
            return entities_out, values, value_entities, txs, added, false, "failed to allocate sqlite direct frontier SQL text"
        }
        defer delete(sql_c)
        if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
        }
        defer _ = sqlite3_finalize(stmt)
        if sqlite3_bind_int64(stmt, 1, i64(entities[0])) != SQLITE_OK ||
           sqlite_bind_text_borrowed(stmt, 2, attr) != SQLITE_OK {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct frontier prefix failed")
        }
        for {
            rc := sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                break
            }
            if rc != SQLITE_ROW {
                return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite direct frontier read failed")
            }
            append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
            value_entity := sqlite3_column_int64(stmt, 2)
            append(&value_entities, value_entity)
            if value_entity >= 0 {
                append(&values, strings.clone(""))
            } else {
                value_text, value_ok := sqlite_column_text_owned(stmt, 1)
                if !value_ok {
                    return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier row had null value text"
                }
                append(&values, value_text)
            }
            append(&txs, u64(sqlite3_column_int64(stmt, 3)))
            append(&added, sqlite3_column_int(stmt, 4) != 0)
        }
        return entities_out, values, value_entities, txs, added, true, ""
    }
    if len(entities) <= 256 {
        db := (^SQLite3)(handle)
        stmt: ^SQLite3_Stmt
        sql := ""
        if order_text == ":eavt" {
            sql = "SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_eavt_entity_cover WHERE d.e = ? AND d.a = ? ORDER BY d.value_text, d.tx, d.added"
        } else if order_text == ":vaet" {
            sql = "SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_vaet_entity WHERE d.value_entity = ? AND d.a = ? ORDER BY d.e, d.tx, d.added"
        } else {
            return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier only supports :eavt and :vaet"
        }
        sql_c, sql_c_ok := sqlite_cstring(sql)
        if !sql_c_ok {
            return entities_out, values, value_entities, txs, added, false, "failed to allocate sqlite direct frontier SQL text"
        }
        defer delete(sql_c)
        if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
        }
        defer _ = sqlite3_finalize(stmt)
        for entity in entities {
            if sqlite3_reset(stmt) != SQLITE_OK ||
               sqlite3_clear_bindings(stmt) != SQLITE_OK ||
               sqlite3_bind_int64(stmt, 1, i64(entity)) != SQLITE_OK ||
               sqlite_bind_text_borrowed(stmt, 2, attr) != SQLITE_OK {
                return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct frontier prefix failed")
            }
            for {
                rc := sqlite3_step(stmt)
                if rc == SQLITE_DONE {
                    break
                }
                if rc != SQLITE_ROW {
                    return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite direct frontier read failed")
                }
                append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
                value_entity := sqlite3_column_int64(stmt, 2)
                append(&value_entities, value_entity)
                if value_entity >= 0 {
                    append(&values, strings.clone(""))
                } else {
                    value_text, value_ok := sqlite_column_text_owned(stmt, 1)
                    if !value_ok {
                        return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier row had null value text"
                    }
                    append(&values, value_text)
                }
                append(&txs, u64(sqlite3_column_int64(stmt, 3)))
                append(&added, sqlite3_column_int(stmt, 4) != 0)
            }
        }
        return entities_out, values, value_entities, txs, added, true, ""
    }
    parts := make([dynamic]string, 0, len(entities) * 2 + 2)
    if order_text == ":eavt" {
        append(&parts, "WITH wanted(e, ordinal) AS (VALUES ")
        for entity, index in entities {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, fmt.tprintf("(%d,%d)", entity, index))
        }
        append(&parts, ") SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM wanted JOIN vev_datoms d INDEXED BY vev_datoms_eavt_entity_cover ON d.e = wanted.e AND d.a = ? ORDER BY wanted.ordinal, d.value_text, d.tx, d.added")
    } else if order_text == ":vaet" {
        append(&parts, "WITH wanted(value_entity, ordinal) AS (VALUES ")
        for entity, index in entities {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, fmt.tprintf("(%d,%d)", entity, index))
        }
        append(&parts, ") SELECT d.e, d.value_text, d.value_entity, d.tx, d.added FROM wanted JOIN vev_datoms d INDEXED BY vev_datoms_vaet_entity ON d.value_entity = wanted.value_entity AND d.a = ? ORDER BY wanted.ordinal, d.e, d.tx, d.added")
    } else {
        delete(parts)
        return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier only supports :eavt and :vaet"
    }
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return entities_out, values, value_entities, txs, added, false, "failed to allocate sqlite direct frontier SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite prepare direct frontier read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if order_text == ":eavt" {
        if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct eavt frontier attr failed")
        }
    } else {
        if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct vaet frontier attr failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return entities_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite direct frontier read failed")
        }
        append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
        value_entity := sqlite3_column_int64(stmt, 2)
        append(&value_entities, value_entity)
        if value_entity >= 0 {
            append(&values, strings.clone(""))
        } else {
            value_text, value_ok := sqlite_column_text_owned(stmt, 1)
            if !value_ok {
                return entities_out, values, value_entities, txs, added, false, "sqlite direct frontier row had null value text"
            }
            append(&values, value_text)
        }
        append(&txs, u64(sqlite3_column_int64(stmt, 3)))
        append(&added, sqlite3_column_int(stmt, 4) != 0)
    }
    return entities_out, values, value_entities, txs, added, true, ""
}

sqlite_direct_same_entity_ref_fanout_parts_raw :: proc(handle: rawptr, name_attr: string, edge_attr: string, wanted_names: []string) -> ([dynamic]string, [dynamic]string, bool, string) {
    left_values := make([dynamic]string)
    right_values := make([dynamic]string)
    if handle == nil {
        return left_values, right_values, false, "sqlite handle was nil"
    }
    if len(wanted_names) == 0 {
        return left_values, right_values, true, ""
    }
    parts := make([dynamic]string, 0, len(wanted_names) * 2 + 2)
    append(&parts, "SELECT n1.value_text, n2.value_text FROM vev_datoms n1 JOIN vev_datoms edge1 ON edge1.value_entity = n1.e AND edge1.a = ? JOIN vev_datoms edge2 ON edge2.e = edge1.e AND edge2.a = ? AND edge2.value_entity <> n1.e JOIN vev_datoms n2 ON n2.e = edge2.value_entity AND n2.a = ? WHERE n1.a = ? AND n1.value_text IN (")
    for _, index in wanted_names {
        if index > 0 {
            append(&parts, ",")
        }
        append(&parts, "?")
    }
    append(&parts, ") GROUP BY n1.value_text, n2.value_text")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return left_values, right_values, false, "failed to allocate sqlite same-entity ref fanout SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return left_values, right_values, false, sqlite_error_text(db, "sqlite prepare same-entity ref fanout read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, edge_attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, edge_attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, name_attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 4, name_attr) != SQLITE_OK {
        return left_values, right_values, false, sqlite_error_text(db, "sqlite bind same-entity ref fanout attrs failed")
    }
    for wanted_name, index in wanted_names {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 5, wanted_name) != SQLITE_OK {
            return left_values, right_values, false, sqlite_error_text(db, "sqlite bind same-entity ref fanout value failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return left_values, right_values, false, sqlite_error_text(db, "sqlite same-entity ref fanout read failed")
        }
        left, left_ok := sqlite_column_text_owned(stmt, 0)
        if !left_ok {
            return left_values, right_values, false, "sqlite same-entity ref fanout row had null left value"
        }
        right, right_ok := sqlite_column_text_owned(stmt, 1)
        if !right_ok {
            delete(left)
            return left_values, right_values, false, "sqlite same-entity ref fanout row had null right value"
        }
        append(&left_values, left)
        append(&right_values, right)
    }
    return left_values, right_values, true, ""
}

sqlite_direct_same_value_collaborator_parts_raw :: proc(handle: rawptr, anchor_name_attr: string, edge_attr: string, shared_value_attr: string, output_name_attr: string, anchor_value: string, excluded_values: []string) -> ([dynamic]string, [dynamic]string, bool, string) {
    output_values := make([dynamic]string)
    shared_values := make([dynamic]string)
    if handle == nil {
        return output_values, shared_values, false, "sqlite handle was nil"
    }
    parts := make([dynamic]string, 0, len(excluded_values) * 2 + 3)
    append(&parts, "SELECT output_name.value_text, shared_value.value_text FROM vev_datoms anchor_name INDEXED BY vev_datoms_avet CROSS JOIN vev_datoms anchor_edge INDEXED BY vev_datoms_vaet_entity ON anchor_edge.value_entity = anchor_name.e AND anchor_edge.a = ? CROSS JOIN vev_datoms shared_value INDEXED BY vev_datoms_eavt_entity_cover ON shared_value.e = anchor_edge.e AND shared_value.a = ? CROSS JOIN vev_datoms same_value INDEXED BY vev_datoms_avet ON same_value.a = ? AND same_value.value_text = shared_value.value_text CROSS JOIN vev_datoms collaborator_edge INDEXED BY vev_datoms_eavt_entity_cover ON collaborator_edge.e = same_value.e AND collaborator_edge.a = ? AND collaborator_edge.value_entity <> anchor_name.e CROSS JOIN vev_datoms output_name INDEXED BY vev_datoms_eavt_entity_cover ON output_name.e = collaborator_edge.value_entity AND output_name.a = ? WHERE anchor_name.a = ? AND anchor_name.value_text = ?")
    if len(excluded_values) > 0 {
        append(&parts, " AND shared_value.value_text NOT IN (")
        for _, index in excluded_values {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, "?")
        }
        append(&parts, ")")
    }
    append(&parts, " GROUP BY output_name.value_text, shared_value.value_text")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return output_values, shared_values, false, "failed to allocate sqlite same-value collaborator SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return output_values, shared_values, false, sqlite_error_text(db, "sqlite prepare same-value collaborator read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    bindings := []string{edge_attr, shared_value_attr, shared_value_attr, edge_attr, output_name_attr, anchor_name_attr, anchor_value}
    for binding, index in bindings {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 1, binding) != SQLITE_OK {
            return output_values, shared_values, false, sqlite_error_text(db, "sqlite bind same-value collaborator read failed")
        }
    }
    for excluded_value, index in excluded_values {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 8, excluded_value) != SQLITE_OK {
            return output_values, shared_values, false, sqlite_error_text(db, "sqlite bind same-value collaborator exclusion failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return output_values, shared_values, false, sqlite_error_text(db, "sqlite same-value collaborator read failed")
        }
        output_value, output_ok := sqlite_column_text_owned(stmt, 0)
        if !output_ok {
            return output_values, shared_values, false, "sqlite same-value collaborator row had null output value"
        }
        shared_value, shared_ok := sqlite_column_text_owned(stmt, 1)
        if !shared_ok {
            delete(output_value)
            return output_values, shared_values, false, "sqlite same-value collaborator row had null shared value"
        }
        append(&output_values, output_value)
        append(&shared_values, shared_value)
    }
    return output_values, shared_values, true, ""
}

sqlite_direct_collab_net_two_parts_raw :: proc(handle: rawptr, anchor_name_attr: string, output_name_attr: string, edge_attr: string, input_names: []string) -> ([dynamic]string, [dynamic]string, bool, string) {
    input_values := make([dynamic]string)
    output_values := make([dynamic]string)
    if handle == nil {
        return input_values, output_values, false, "sqlite handle was nil"
    }
    if len(input_names) == 0 {
        return input_values, output_values, true, ""
    }
    parts := make([dynamic]string, 0, len(input_names) * 2 + 3)
    append(&parts, "WITH anchor(anchor_e, input_name) AS MATERIALIZED (SELECT e, value_text FROM vev_datoms INDEXED BY vev_datoms_avet WHERE a = ? AND value_text IN (")
    for _, index in input_names {
        if index > 0 {
            append(&parts, ",")
        }
        append(&parts, "?")
    }
    append(&parts, ")), direct(anchor_e, neighbor_e) AS MATERIALIZED (SELECT anchor.anchor_e, edge2.value_entity FROM anchor CROSS JOIN vev_datoms edge1 INDEXED BY vev_datoms_vaet_entity ON edge1.value_entity = anchor.anchor_e AND edge1.a = ? CROSS JOIN vev_datoms edge2 INDEXED BY vev_datoms_eavt_entity_cover ON edge2.e = edge1.e AND edge2.a = ? AND edge2.value_entity <> anchor.anchor_e GROUP BY anchor.anchor_e, edge2.value_entity), reach(anchor_e, neighbor_e) AS (SELECT anchor_e, neighbor_e FROM direct UNION SELECT direct.anchor_e, edge4.value_entity FROM direct CROSS JOIN vev_datoms edge3 INDEXED BY vev_datoms_vaet_entity ON edge3.value_entity = direct.neighbor_e AND edge3.a = ? CROSS JOIN vev_datoms edge4 INDEXED BY vev_datoms_eavt_entity_cover ON edge4.e = edge3.e AND edge4.a = ? AND edge4.value_entity <> direct.neighbor_e AND edge4.value_entity <> direct.anchor_e) SELECT anchor.input_name, output_name.value_text FROM anchor CROSS JOIN reach ON reach.anchor_e = anchor.anchor_e CROSS JOIN vev_datoms output_name INDEXED BY vev_datoms_eavt_entity_cover ON output_name.e = reach.neighbor_e AND output_name.a = ? GROUP BY anchor.input_name, output_name.value_text")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return input_values, output_values, false, "failed to allocate sqlite collaboration depth-2 SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return input_values, output_values, false, sqlite_error_text(db, "sqlite prepare collaboration depth-2 read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, anchor_name_attr) != SQLITE_OK {
        return input_values, output_values, false, sqlite_error_text(db, "sqlite bind collaboration depth-2 anchor attr failed")
    }
    for input_name, index in input_names {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 2, input_name) != SQLITE_OK {
            return input_values, output_values, false, sqlite_error_text(db, "sqlite bind collaboration depth-2 input failed")
        }
    }
    attr_start := i32(len(input_names)) + 2
    attr_bindings := []string{edge_attr, edge_attr, edge_attr, edge_attr, output_name_attr}
    for attr, index in attr_bindings {
        if sqlite_bind_text_borrowed(stmt, attr_start + i32(index), attr) != SQLITE_OK {
            return input_values, output_values, false, sqlite_error_text(db, "sqlite bind collaboration depth-2 attr failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return input_values, output_values, false, sqlite_error_text(db, "sqlite collaboration depth-2 read failed")
        }
        input_value, input_ok := sqlite_column_text_owned(stmt, 0)
        if !input_ok {
            return input_values, output_values, false, "sqlite collaboration depth-2 row had null input value"
        }
        output_value, output_ok := sqlite_column_text_owned(stmt, 1)
        if !output_ok {
            delete(input_value)
            return input_values, output_values, false, "sqlite collaboration depth-2 row had null output value"
        }
        append(&input_values, input_value)
        append(&output_values, output_value)
    }
    return input_values, output_values, true, ""
}

sqlite_direct_input_ref_value_parts_raw :: proc(handle: rawptr, anchor_attr: string, anchor_value: string, ref_attr: string, output_attr: string) -> ([dynamic]string, bool, string) {
    output_values := make([dynamic]string)
    if handle == nil {
        return output_values, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT output.value_text FROM vev_datoms anchor INDEXED BY vev_datoms_avet CROSS JOIN vev_datoms edge INDEXED BY vev_datoms_vaet_entity ON edge.value_entity = anchor.e AND edge.a = ? CROSS JOIN vev_datoms output INDEXED BY vev_datoms_eavt_entity_cover ON output.e = edge.e AND output.a = ? WHERE anchor.a = ? AND anchor.value_text = ? GROUP BY output.value_text"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return output_values, false, "failed to allocate sqlite input-ref-value SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return output_values, false, sqlite_error_text(db, "sqlite prepare input-ref-value read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    bindings := []string{ref_attr, output_attr, anchor_attr, anchor_value}
    for binding, index in bindings {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 1, binding) != SQLITE_OK {
            return output_values, false, sqlite_error_text(db, "sqlite bind input-ref-value read failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return output_values, false, sqlite_error_text(db, "sqlite input-ref-value read failed")
        }
        output_value, output_ok := sqlite_column_text_owned(stmt, 0)
        if !output_ok {
            return output_values, false, "sqlite input-ref-value row had null output value"
        }
        append(&output_values, output_value)
    }
    return output_values, true, ""
}

sqlite_direct_track_release_parts_raw :: proc(handle: rawptr, artist_name_attr: string, artist_name: string, track_artist_attr: string, track_name_attr: string, medium_track_attr: string, release_media_attr: string, release_name_attr: string, release_year_attr: string) -> ([dynamic]string, [dynamic]string, [dynamic]string, bool, string) {
    titles := make([dynamic]string)
    albums := make([dynamic]string)
    years := make([dynamic]string)
    if handle == nil {
        return titles, albums, years, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT title.value_text, album.value_text, release_year.value_text FROM vev_datoms artist_name INDEXED BY vev_datoms_avet CROSS JOIN vev_datoms track_artist INDEXED BY vev_datoms_vaet_entity ON track_artist.value_entity = artist_name.e AND track_artist.a = ? CROSS JOIN vev_datoms title INDEXED BY vev_datoms_eavt_entity_cover ON title.e = track_artist.e AND title.a = ? CROSS JOIN vev_datoms medium_track INDEXED BY vev_datoms_vaet_entity ON medium_track.value_entity = track_artist.e AND medium_track.a = ? CROSS JOIN vev_datoms release_media INDEXED BY vev_datoms_vaet_entity ON release_media.value_entity = medium_track.e AND release_media.a = ? CROSS JOIN vev_datoms album INDEXED BY vev_datoms_eavt_entity_cover ON album.e = release_media.e AND album.a = ? CROSS JOIN vev_datoms release_year INDEXED BY vev_datoms_eavt_entity_cover ON release_year.e = release_media.e AND release_year.a = ? WHERE artist_name.a = ? AND artist_name.value_text = ? GROUP BY title.value_text, album.value_text, release_year.value_text"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return titles, albums, years, false, "failed to allocate sqlite track-release SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return titles, albums, years, false, sqlite_error_text(db, "sqlite prepare track-release read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    bindings := []string{track_artist_attr, track_name_attr, medium_track_attr, release_media_attr, release_name_attr, release_year_attr, artist_name_attr, artist_name}
    for binding, index in bindings {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 1, binding) != SQLITE_OK {
            return titles, albums, years, false, sqlite_error_text(db, "sqlite bind track-release read failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return titles, albums, years, false, sqlite_error_text(db, "sqlite track-release read failed")
        }
        title, title_ok := sqlite_column_text_owned(stmt, 0)
        if !title_ok {
            return titles, albums, years, false, "sqlite track-release row had null title"
        }
        album, album_ok := sqlite_column_text_owned(stmt, 1)
        if !album_ok {
            delete(title)
            return titles, albums, years, false, "sqlite track-release row had null album"
        }
        year, year_ok := sqlite_column_text_owned(stmt, 2)
        if !year_ok {
            delete(title)
            delete(album)
            return titles, albums, years, false, "sqlite track-release row had null year"
        }
        append(&titles, title)
        append(&albums, album)
        append(&years, year)
    }
    return titles, albums, years, true, ""
}

sqlite_direct_fulltext_track_info_parts_raw :: proc(handle: rawptr, fulltext_attr: string, search: string, track_artist_attr: string, artist_name_attr: string, medium_track_attr: string, release_medium_attr: string, first_release_attr: string, second_release_attr: string) -> ([dynamic]string, [dynamic]string, [dynamic]string, [dynamic]string, bool, string) {
    titles := make([dynamic]string)
    artists := make([dynamic]string)
    first_release_values := make([dynamic]string)
    second_release_values := make([dynamic]string)
    if handle == nil {
        return titles, artists, first_release_values, second_release_values, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT title.value_text, artist_name.value_text, first_release.value_text, second_release.value_text FROM vev_fulltext fulltext CROSS JOIN vev_datoms title INDEXED BY vev_datoms_log_index ON title.log_index = fulltext.log_index CROSS JOIN vev_datoms track_artist INDEXED BY vev_datoms_eavt_entity_cover ON track_artist.e = title.e AND track_artist.a = ? CROSS JOIN vev_datoms artist_name INDEXED BY vev_datoms_eavt_entity_cover ON artist_name.e = track_artist.value_entity AND artist_name.a = ? CROSS JOIN vev_datoms medium_track INDEXED BY vev_datoms_vaet_entity ON medium_track.value_entity = title.e AND medium_track.a = ? CROSS JOIN vev_datoms release_medium INDEXED BY vev_datoms_vaet_entity ON release_medium.value_entity = medium_track.e AND release_medium.a = ? CROSS JOIN vev_datoms first_release INDEXED BY vev_datoms_eavt_entity_cover ON first_release.e = release_medium.e AND first_release.a = ? CROSS JOIN vev_datoms second_release INDEXED BY vev_datoms_eavt_entity_cover ON second_release.e = release_medium.e AND second_release.a = ? WHERE fulltext.attr = ? AND vev_fulltext MATCH ? GROUP BY title.value_text, artist_name.value_text, first_release.value_text, second_release.value_text"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return titles, artists, first_release_values, second_release_values, false, "failed to allocate sqlite fulltext track info SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return titles, artists, first_release_values, second_release_values, false, sqlite_error_text(db, "sqlite prepare fulltext track info read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    bindings := []string{track_artist_attr, artist_name_attr, medium_track_attr, release_medium_attr, first_release_attr, second_release_attr, fulltext_attr, search}
    for binding, index in bindings {
        if sqlite_bind_text_borrowed(stmt, i32(index) + 1, binding) != SQLITE_OK {
            return titles, artists, first_release_values, second_release_values, false, sqlite_error_text(db, "sqlite bind fulltext track info read failed")
        }
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return titles, artists, first_release_values, second_release_values, false, sqlite_error_text(db, "sqlite fulltext track info read failed")
        }
        title, title_ok := sqlite_column_text_owned(stmt, 0)
        if !title_ok {
            return titles, artists, first_release_values, second_release_values, false, "sqlite fulltext track info row had null title"
        }
        artist, artist_ok := sqlite_column_text_owned(stmt, 1)
        if !artist_ok {
            delete(title)
            return titles, artists, first_release_values, second_release_values, false, "sqlite fulltext track info row had null artist"
        }
        first_release_value, first_release_ok := sqlite_column_text_owned(stmt, 2)
        if !first_release_ok {
            delete(title)
            delete(artist)
            return titles, artists, first_release_values, second_release_values, false, "sqlite fulltext track info row had null first release value"
        }
        second_release_value, second_release_ok := sqlite_column_text_owned(stmt, 3)
        if !second_release_ok {
            delete(title)
            delete(artist)
            delete(first_release_value)
            return titles, artists, first_release_values, second_release_values, false, "sqlite fulltext track info row had null second release value"
        }
        append(&titles, title)
        append(&artists, artist)
        append(&first_release_values, first_release_value)
        append(&second_release_values, second_release_value)
    }
    return titles, artists, first_release_values, second_release_values, true, ""
}

sqlite_direct_eavt_entity_attrs_datom_parts_raw :: proc(handle: rawptr, entities: []u64, attrs: []string) -> ([dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]i64, [dynamic]u64, [dynamic]bool, bool, string) {
    entities_out := make([dynamic]u64)
    attrs_out := make([dynamic]string)
    values := make([dynamic]string)
    value_entities := make([dynamic]i64)
    txs := make([dynamic]u64)
    added := make([dynamic]bool)
    if handle == nil {
        return entities_out, attrs_out, values, value_entities, txs, added, false, "sqlite handle was nil"
    }
    if len(entities) == 0 || len(attrs) == 0 {
        return entities_out, attrs_out, values, value_entities, txs, added, true, ""
    }
    min_entity := entities[0]
    max_entity := entities[len(entities) - 1]
    span := max_entity - min_entity + 1
    if len(entities) > 256 && span <= u64(len(entities)) * 16 {
        entity_set := make(map[u64]struct{}, len(entities))
        defer delete(entity_set)
        for entity in entities {
            entity_set[entity] = {}
        }
        parts := make([dynamic]string, 0, len(attrs) * 2 + 2)
        append(&parts, "SELECT d.e, d.a, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_eavt_entity_cover WHERE d.e >= ? AND d.e <= ? AND d.a IN (")
        for _, index in attrs {
            if index > 0 {
                append(&parts, ",")
            }
            append(&parts, "?")
        }
        append(&parts, ") ORDER BY d.e, d.a, d.value_text, d.tx, d.added")
        sql := strings.concatenate(parts[:])
        delete(parts)
        defer delete(sql)
        db := (^SQLite3)(handle)
        stmt: ^SQLite3_Stmt
        sql_c, sql_c_ok := sqlite_cstring(sql)
        if !sql_c_ok {
            return entities_out, attrs_out, values, value_entities, txs, added, false, "failed to allocate sqlite dense EAVT entity attrs SQL text"
        }
        defer delete(sql_c)
        if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
            return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite prepare dense EAVT entity attrs read failed")
        }
        defer _ = sqlite3_finalize(stmt)
        if sqlite3_bind_int64(stmt, 1, i64(min_entity)) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 2, i64(max_entity)) != SQLITE_OK {
            return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind dense EAVT entity attrs range failed")
        }
        for attr, index in attrs {
            if sqlite_bind_text_borrowed(stmt, i32(index) + 3, attr) != SQLITE_OK {
                return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind dense EAVT entity attrs attr failed")
            }
        }
        for {
            rc := sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                break
            }
            if rc != SQLITE_ROW {
                return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite dense EAVT entity attrs read failed")
            }
            entity := u64(sqlite3_column_int64(stmt, 0))
            if _, wanted := entity_set[entity]; !wanted {
                continue
            }
            attr_text, attr_ok := sqlite_column_text_owned(stmt, 1)
            if !attr_ok {
                return entities_out, attrs_out, values, value_entities, txs, added, false, "sqlite dense EAVT entity attrs row had null attr"
            }
            value_entity := sqlite3_column_int64(stmt, 3)
            value_text := strings.clone("")
            if value_entity < 0 {
                delete(value_text)
                value_text_ok: bool
                value_text, value_text_ok = sqlite_column_text_owned(stmt, 2)
                if !value_text_ok {
                    delete(attr_text)
                    return entities_out, attrs_out, values, value_entities, txs, added, false, "sqlite dense EAVT entity attrs row had null value"
                }
            }
            append(&entities_out, entity)
            append(&attrs_out, attr_text)
            append(&values, value_text)
            append(&value_entities, value_entity)
            append(&txs, u64(sqlite3_column_int64(stmt, 4)))
            append(&added, sqlite3_column_int(stmt, 5) != 0)
        }
        return entities_out, attrs_out, values, value_entities, txs, added, true, ""
    }
    parts := make([dynamic]string, 0, len(attrs) * 2 + 2)
    append(&parts, "SELECT d.e, d.a, d.value_text, d.value_entity, d.tx, d.added FROM vev_datoms d INDEXED BY vev_datoms_eavt_entity_cover WHERE d.e = ? AND d.a IN (")
    for _, index in attrs {
        if index > 0 {
            append(&parts, ",")
        }
        append(&parts, "?")
    }
    append(&parts, ") ORDER BY d.a, d.value_text, d.tx, d.added")
    sql := strings.concatenate(parts[:])
    delete(parts)
    defer delete(sql)
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return entities_out, attrs_out, values, value_entities, txs, added, false, "failed to allocate sqlite direct EAVT entity attrs SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite prepare direct EAVT entity attrs read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    for entity in entities {
        if sqlite3_reset(stmt) != SQLITE_OK ||
           sqlite3_clear_bindings(stmt) != SQLITE_OK ||
           sqlite3_bind_int64(stmt, 1, i64(entity)) != SQLITE_OK {
            return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct EAVT entity attrs entity failed")
        }
        for attr, index in attrs {
            if sqlite_bind_text_borrowed(stmt, i32(index) + 2, attr) != SQLITE_OK {
                return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite bind direct EAVT entity attrs attr failed")
            }
        }
        for {
            rc := sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                break
            }
            if rc != SQLITE_ROW {
                return entities_out, attrs_out, values, value_entities, txs, added, false, sqlite_error_text(db, "sqlite direct EAVT entity attrs read failed")
            }
            attr_text, attr_ok := sqlite_column_text_owned(stmt, 1)
            if !attr_ok {
                return entities_out, attrs_out, values, value_entities, txs, added, false, "sqlite direct EAVT entity attrs row had null attr"
            }
            value_entity := sqlite3_column_int64(stmt, 3)
            value_text := strings.clone("")
            if value_entity < 0 {
                delete(value_text)
                value_text_ok: bool
                value_text, value_text_ok = sqlite_column_text_owned(stmt, 2)
                if !value_text_ok {
                    delete(attr_text)
                    return entities_out, attrs_out, values, value_entities, txs, added, false, "sqlite direct EAVT entity attrs row had null value"
                }
            }
            append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
            append(&attrs_out, attr_text)
            append(&values, value_text)
            append(&value_entities, value_entity)
            append(&txs, u64(sqlite3_column_int64(stmt, 4)))
            append(&added, sqlite3_column_int(stmt, 5) != 0)
        }
    }
    return entities_out, attrs_out, values, value_entities, txs, added, true, ""
}

sqlite_attr_string_contains_datom_parts_raw :: proc(handle: rawptr, attr: string, search: string) -> ([dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, bool, string) {
    entities_out := make([dynamic]u64, 0)
    attrs := make([dynamic]string, 0)
    values := make([dynamic]string, 0)
    txs := make([dynamic]u64, 0)
    added := make([dynamic]bool, 0)
    if handle == nil {
        return entities_out, attrs, values, txs, added, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE a = ? AND added = 1 AND instr(lower(value_text), lower(?)) > 0 ORDER BY log_index, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return entities_out, attrs, values, txs, added, false, "failed to allocate sqlite attr string contains SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite prepare attr string contains read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, search) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite bind attr string contains read failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite attr string contains read failed")
        }
        a_text, a_ok := sqlite_column_text_owned(stmt, 1)
        if !a_ok {
            return entities_out, attrs, values, txs, added, false, "sqlite attr string contains row had null attr text"
        }
        value_text, value_ok := sqlite_column_text_owned(stmt, 2)
        if !value_ok {
            delete(a_text)
            return entities_out, attrs, values, txs, added, false, "sqlite attr string contains row had null value text"
        }
        append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
        append(&attrs, a_text)
        append(&values, value_text)
        append(&txs, u64(sqlite3_column_int64(stmt, 3)))
        append(&added, sqlite3_column_int(stmt, 4) != 0)
    }
    return entities_out, attrs, values, txs, added, true, ""
}

sqlite_attr_string_fts_datom_parts_raw :: proc(handle: rawptr, attr: string, search: string) -> ([dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, bool, string) {
    entities_out := make([dynamic]u64, 0)
    attrs := make([dynamic]string, 0)
    values := make([dynamic]string, 0)
    txs := make([dynamic]u64, 0)
    added := make([dynamic]bool, 0)
    if handle == nil {
        return entities_out, attrs, values, txs, added, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT d.e, d.a, d.value_text, d.tx, d.added FROM vev_fulltext f JOIN vev_datoms d ON d.log_index = f.log_index WHERE f.attr = ? AND vev_fulltext MATCH ? AND d.added = 1 ORDER BY d.log_index, d.id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return entities_out, attrs, values, txs, added, false, "failed to allocate sqlite attr string fts SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite prepare attr string fts read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, search) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite bind attr string fts read failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite attr string fts read failed")
        }
        a_text, a_ok := sqlite_column_text_owned(stmt, 1)
        if !a_ok {
            return entities_out, attrs, values, txs, added, false, "sqlite attr string fts row had null attr text"
        }
        value_text, value_ok := sqlite_column_text_owned(stmt, 2)
        if !value_ok {
            delete(a_text)
            return entities_out, attrs, values, txs, added, false, "sqlite attr string fts row had null value text"
        }
        append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
        append(&attrs, a_text)
        append(&values, value_text)
        append(&txs, u64(sqlite3_column_int64(stmt, 3)))
        append(&added, sqlite3_column_int(stmt, 4) != 0)
    }
    return entities_out, attrs, values, txs, added, true, ""
}

sqlite_attr_string_term_datom_parts_raw :: proc(handle: rawptr, attr: string, search: string) -> ([dynamic]u64, [dynamic]string, [dynamic]string, [dynamic]u64, [dynamic]bool, bool, string) {
    entities_out := make([dynamic]u64, 0)
    attrs := make([dynamic]string, 0)
    values := make([dynamic]string, 0)
    txs := make([dynamic]u64, 0)
    added := make([dynamic]bool, 0)
    if handle == nil {
        return entities_out, attrs, values, txs, added, false, "sqlite handle was nil"
    }
    term_buf := make([dynamic]u8, 0, len(search))
    defer delete(term_buf)
    for i := 0; i < len(search); i += 1 {
        ch := search[i]
        if !sqlite_text_term_char_ok(ch) {
            return entities_out, attrs, values, txs, added, false, "search text was not a simple indexed term"
        }
        append(&term_buf, sqlite_text_term_lower(ch))
    }
    if len(term_buf) == 0 {
        return entities_out, attrs, values, txs, added, false, "search text was empty"
    }
    term := string(term_buf[:])
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT d.e, d.a, d.value_text, d.tx, d.added FROM vev_text_terms t JOIN vev_datoms d ON d.log_index = t.log_index WHERE t.attr = ? AND t.term = ? AND d.added = 1 ORDER BY t.log_index"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return entities_out, attrs, values, txs, added, false, "failed to allocate sqlite attr string term SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite prepare attr string term read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, term) != SQLITE_OK {
        return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite bind attr string term read failed")
    }
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            return entities_out, attrs, values, txs, added, false, sqlite_error_text(db, "sqlite attr string term read failed")
        }
        a_text, a_ok := sqlite_column_text_owned(stmt, 1)
        if !a_ok {
            return entities_out, attrs, values, txs, added, false, "sqlite attr string term row had null attr text"
        }
        value_text, value_ok := sqlite_column_text_owned(stmt, 2)
        if !value_ok {
            delete(a_text)
            return entities_out, attrs, values, txs, added, false, "sqlite attr string term row had null value text"
        }
        append(&entities_out, u64(sqlite3_column_int64(stmt, 0)))
        append(&attrs, a_text)
        append(&values, value_text)
        append(&txs, u64(sqlite3_column_int64(stmt, 3)))
        append(&added, sqlite3_column_int(stmt, 4) != 0)
    }
    return entities_out, attrs, values, txs, added, true, ""
}

sqlite_step_datom_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, fulltext_stmt_handle: rawptr, text_term_stmt_handle: rawptr, log_index: i64, e: u64, a: string, value_text: string, value_entity: i64, tx: u64, added: bool) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(e)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 4, value_text) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 5, value_entity) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 6, i64(tx)) != SQLITE_OK ||
       sqlite3_bind_int(stmt, 7, c.int(added ? 1 : 0)) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind datom failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert datom failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    if fulltext_stmt_handle != nil || text_term_stmt_handle != nil {
        if fulltext_stmt_handle == nil || text_term_stmt_handle == nil {
            return false, "sqlite secondary text statement was nil"
        }
        fulltext_ok, fulltext_error := sqlite_step_fulltext_datom_stmt_raw(handle, fulltext_stmt_handle, log_index, a, value_text, added)
        if !fulltext_ok {
            return false, fulltext_error
        }
        terms_ok, terms_error := sqlite_insert_text_terms_for_datom_stmt_raw(handle, text_term_stmt_handle, log_index, a, value_text, added)
        if !terms_ok {
            return false, terms_error
        }
    }
    return true, ""
}

sqlite_insert_tx_meta_raw :: proc(handle: rawptr, tx: u64, a: string, value_text: string) -> (bool, string) {
    if handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    tx_ok, tx_error := sqlite_insert_tx_raw(handle, tx)
    if !tx_ok {
        return false, tx_error
    }
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_tx_meta (tx, a, value_text) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite prepare tx metadata failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, value_text) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind tx metadata failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert tx metadata failed")
    }
    return true, ""
}

sqlite_prepare_insert_tx_meta_raw :: proc(handle: rawptr) -> (rawptr, bool, string) {
    if handle == nil {
        return nil, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "INSERT INTO vev_tx_meta (tx, a, value_text) VALUES (?, ?, ?)"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return nil, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return nil, false, sqlite_error_text(db, "sqlite prepare tx metadata failed")
    }
    return rawptr(stmt), true, ""
}

sqlite_step_tx_meta_stmt_raw :: proc(handle: rawptr, stmt_handle: rawptr, tx: u64, a: string, value_text: string) -> (bool, string) {
    if handle == nil || stmt_handle == nil {
        return false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt := (^SQLite3_Stmt)(stmt_handle)
    _ = sqlite3_reset(stmt)
    _ = sqlite3_clear_bindings(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(tx)) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, a) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 3, value_text) != SQLITE_OK {
        return false, sqlite_error_text(db, "sqlite bind tx metadata failed")
    }
    if sqlite3_step(stmt) != SQLITE_DONE {
        return false, sqlite_error_text(db, "sqlite insert tx metadata failed")
    }
    _ = sqlite3_clear_bindings(stmt)
    return true, ""
}

sqlite_rows_exist_raw :: proc(db: ^SQLite3) -> (bool, bool, string) {
    stmt: ^SQLite3_Stmt
    sql := "SELECT 1 FROM vev_datoms LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return false, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return false, false, sqlite_error_text(db, "sqlite prepare exists failed")
    }
    defer _ = sqlite3_finalize(stmt)
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        return true, true, ""
    }
    if rc == SQLITE_DONE {
        return false, true, ""
    }
    return false, false, sqlite_error_text(db, "sqlite exists failed")
}

sqlite_load_datom_rows_text_handle_raw :: proc(handle: rawptr) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    any_rows, exists_ok, exists_error := sqlite_rows_exist_raw(db)
    if !exists_ok {
        return "", false, exists_error
    }
    if !any_rows {
        return "", false, "sqlite DB has no Vev datom rows"
    }
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms ORDER BY log_index, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare datom read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    parts := make([dynamic]string)
    append(&parts, "[")
    first := true
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            delete(parts)
            return "", false, sqlite_error_text(db, "sqlite datom read failed")
        }
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            delete(parts)
            return "", false, "sqlite datom row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            delete(parts)
            return "", false, "failed to clone sqlite datom attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            delete(parts)
            return "", false, "failed to clone sqlite datom value"
        }
        if !first {
            append(&parts, " ")
        }
        first = false
        append(&parts, fmt.tprintf("[%d %s %s %d %v]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text,
            sqlite3_column_int64(stmt, 3),
            sqlite3_column_int(stmt, 4) != 0))
        delete(a_text)
        delete(value_text)
    }
    append(&parts, "]")
    out := strings.concatenate(parts[:])
    delete(parts)
    return out, true, ""
}

sqlite_load_datom_rows_text_raw :: proc(path: string) -> (string, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return "", false, open_error
    }
    defer _ = sqlite3_close(db)
    return sqlite_load_datom_rows_text_handle_raw(rawptr(db))
}

sqlite_load_datom_by_log_index_text_raw :: proc(handle: rawptr, log_index: i64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE log_index = ? ORDER BY id LIMIT 1"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare datom log-index read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, log_index) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind datom log-index read failed")
    }
    rc := sqlite3_step(stmt)
    if rc == SQLITE_ROW {
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            return "", false, "sqlite datom row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            return "", false, "failed to clone sqlite datom attr"
        }
        defer delete(a_text)
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            return "", false, "failed to clone sqlite datom value"
        }
        defer delete(value_text)
        formatted := fmt.tprintf("[%d %s %s %d %v]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text,
            sqlite3_column_int64(stmt, 3),
            sqlite3_column_int(stmt, 4) != 0)
        out, out_err := strings.clone(formatted)
        if out_err != nil {
            return "", false, "failed to clone sqlite datom log-index text"
        }
        return out, true, ""
    }
    if rc == SQLITE_DONE {
        return "", false, "sqlite datom log-index not found"
    }
    return "", false, sqlite_error_text(db, "sqlite datom log-index read failed")
}

sqlite_load_attr_string_contains_rows_text_raw :: proc(handle: rawptr, attr: string, search: string) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE a = ? AND added = 1 AND instr(lower(value_text), lower(?)) > 0 ORDER BY log_index, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare attr string contains read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite_bind_text_borrowed(stmt, 1, attr) != SQLITE_OK ||
       sqlite_bind_text_borrowed(stmt, 2, search) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind attr string contains read failed")
    }
    parts := make([dynamic]string)
    append(&parts, "[")
    first := true
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            delete(parts)
            return "", false, sqlite_error_text(db, "sqlite attr string contains read failed")
        }
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            delete(parts)
            return "", false, "sqlite attr string contains row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            delete(parts)
            return "", false, "failed to clone sqlite attr string contains attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            delete(parts)
            return "", false, "failed to clone sqlite attr string contains value"
        }
        if !first {
            append(&parts, " ")
        }
        first = false
        append(&parts, fmt.tprintf("[%d %s %s %d %v]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text,
            sqlite3_column_int64(stmt, 3),
            sqlite3_column_int(stmt, 4) != 0))
        delete(a_text)
        delete(value_text)
    }
    append(&parts, "]")
    out := strings.concatenate(parts[:])
    delete(parts)
    return out, true, ""
}

sqlite_load_tx_meta_rows_text_raw :: proc(path: string) -> (string, bool, string) {
    db, open_ok, open_error := sqlite_open_initialized(path)
    if !open_ok {
        return "", false, open_error
    }
    defer _ = sqlite3_close(db)
    stmt: ^SQLite3_Stmt
    sql := "SELECT tx, a, value_text FROM vev_tx_meta ORDER BY id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare tx metadata read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    parts := make([dynamic]string)
    append(&parts, "[")
    first := true
    for {
        rc := sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            break
        }
        if rc != SQLITE_ROW {
            delete(parts)
            return "", false, sqlite_error_text(db, "sqlite tx metadata read failed")
        }
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            delete(parts)
            return "", false, "sqlite tx metadata row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            delete(parts)
            return "", false, "failed to clone sqlite tx metadata attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            delete(parts)
            return "", false, "failed to clone sqlite tx metadata value"
        }
        if !first {
            append(&parts, " ")
        }
        first = false
        append(&parts, fmt.tprintf("[%d %s %s]",
            sqlite3_column_int64(stmt, 0),
            sqlite_attr_serializable_text(a_text),
            value_text))
        delete(a_text)
        delete(value_text)
    }
    append(&parts, "]")
    out := strings.concatenate(parts[:])
    delete(parts)
    return out, true, ""
}
