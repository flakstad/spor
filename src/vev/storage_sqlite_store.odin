package vev

import "core:fmt"
import "core:strings"
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

// Opens an existing Vev store strictly for metadata inspection. Unlike the
// live open path this never creates a database, initializes schema, or runs
// any storage maintenance.
sqlite_open_inspection_raw :: proc(path: string) -> (rawptr, bool, string) {
    db: ^SQLite3
    path_c, path_c_ok := sqlite_cstring(path)
    if !path_c_ok {
        return nil, false, "failed to allocate sqlite path"
    }
    defer delete(path_c)
    if sqlite3_open_v2(path_c, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
        error := sqlite_error_text(db, "sqlite read-only inspection open failed")
        if db != nil {
            _ = sqlite3_close_v2(db)
        }
        return nil, false, error
    }
    if !sqlite_app_is_vev_store(db) {
        _ = sqlite3_close_v2(db)
        return nil, false, "storage path is not a Vev store"
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
