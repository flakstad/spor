package vev

import c "core:c"
import "core:fmt"
import "core:strings"
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

// Load only the canonical novelty after an index checkpoint.  The caller is
// expected to hold a SQLite read transaction while it reads the root and this
// tail, so the two pieces describe one committed database generation.
sqlite_load_datom_rows_text_after_basis_handle_raw :: proc(handle: rawptr, after_basis: u64, through_basis: u64) -> (string, bool, string) {
    if handle == nil {
        return "", false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "SELECT e, a, value_text, tx, added FROM vev_datoms WHERE tx > ? AND tx <= ? ORDER BY tx, id"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return "", false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite prepare datom tail read failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_bind_int64(stmt, 1, i64(after_basis)) != SQLITE_OK ||
       sqlite3_bind_int64(stmt, 2, i64(through_basis)) != SQLITE_OK {
        return "", false, sqlite_error_text(db, "sqlite bind datom tail read failed")
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
            return "", false, sqlite_error_text(db, "sqlite datom tail read failed")
        }
        a_raw := sqlite3_column_text(stmt, 1)
        value_raw := sqlite3_column_text(stmt, 2)
        if a_raw == nil || value_raw == nil {
            delete(parts)
            return "", false, "sqlite datom tail row had null text"
        }
        a_text, a_err := strings.clone_from_cstring(a_raw)
        if a_err != nil {
            delete(parts)
            return "", false, "failed to clone sqlite datom tail attr"
        }
        value_text, value_err := strings.clone_from_cstring(value_raw)
        if value_err != nil {
            delete(a_text)
            delete(parts)
            return "", false, "failed to clone sqlite datom tail value"
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
