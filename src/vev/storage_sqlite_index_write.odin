// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import c "core:c"
import "core:strings"
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
