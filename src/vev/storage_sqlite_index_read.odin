// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

sqlite_storage_head_basis_raw :: proc(handle: rawptr) -> (u64, bool, string) {
    if handle == nil {
        return 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := cstring("SELECT COALESCE(MAX(tx), 0) FROM vev_transactions")
    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
        return 0, false, sqlite_error_text(db, "sqlite prepare storage head basis failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_step(stmt) != SQLITE_ROW {
        return 0, false, sqlite_error_text(db, "sqlite storage head basis read failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)), true, ""
}

sqlite_index_lag_stats_raw :: proc(handle: rawptr) -> (head_basis: u64, indexed_basis: u64, tail_transactions: u64, tail_datoms: u64, ok: bool, error: string) {
    if handle == nil {
        return 0, 0, 0, 0, false, "sqlite handle was nil"
    }
    db := (^SQLite3)(handle)
    stmt: ^SQLite3_Stmt
    sql := "WITH head(basis) AS (SELECT COALESCE(MAX(tx), 0) FROM vev_transactions), indexed(basis) AS (SELECT COALESCE(MAX(basis_tx), 0) FROM vev_index_roots) SELECT head.basis, indexed.basis, (SELECT COUNT(*) FROM vev_transactions WHERE tx > indexed.basis), (SELECT COUNT(*) FROM vev_datoms WHERE tx > indexed.basis) FROM head, indexed"
    sql_c, sql_c_ok := sqlite_cstring(sql)
    if !sql_c_ok {
        return 0, 0, 0, 0, false, "failed to allocate sqlite SQL text"
    }
    defer delete(sql_c)
    if sqlite3_prepare_v2(db, sql_c, -1, &stmt, nil) != SQLITE_OK {
        return 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite prepare index lag stats failed")
    }
    defer _ = sqlite3_finalize(stmt)
    if sqlite3_step(stmt) != SQLITE_ROW {
        return 0, 0, 0, 0, false, sqlite_error_text(db, "sqlite index lag stats read failed")
    }
    return u64(sqlite3_column_int64(stmt, 0)),
           u64(sqlite3_column_int64(stmt, 1)),
           u64(sqlite3_column_int64(stmt, 2)),
           u64(sqlite3_column_int64(stmt, 3)),
           true,
           ""
}

import c "core:c"
import "core:fmt"
import "core:strings"
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
    sql := "SELECT r.basis_tx, COALESCE(m.row_count, c.row_count) FROM (SELECT root_id, basis_tx FROM vev_index_roots ORDER BY root_id DESC LIMIT 1) r JOIN vev_index_root_pages p ON p.root_id = r.root_id JOIN vev_index_chunks c ON c.chunk_id = p.root_chunk_id LEFT JOIN vev_index_run_manifests m ON m.manifest_id = p.manifest_id WHERE p.index_name = ?"
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
