package vev

import c "core:c"
import "core:strings"
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
CREATE INDEX IF NOT EXISTS vev_datoms_avet ON vev_datoms(a, value_text, e, tx, added);
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

SQLITE_SCHEMA_VERSION :: "2"
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
        "INSERT OR REPLACE INTO vev_meta (key, value) VALUES ('schema-version', '2')",
    )
}

sqlite_drop_derived_legacy_datom_indexes :: proc(db: ^SQLite3) -> (bool, string) {
    // AEVT and VAET ordering is published by the immutable derived roots.
    // Canonical SQLite reads use EAVT/EAVT-cover, AVET, VAET-entity, and the
    // log-index lookup; keeping these two unused indexes would only amplify
    // every durable datom insert.
    ok, err := sqlite_exec_ok(
        db,
        "DROP INDEX IF EXISTS vev_datoms_aevt; DROP INDEX IF EXISTS vev_datoms_vaet;",
    )
    return ok, err
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
    legacy_indexes_ok, legacy_indexes_error := sqlite_drop_derived_legacy_datom_indexes(db)
    if !legacy_indexes_ok {
        _ = sqlite3_close(db)
        return nil, false, legacy_indexes_error
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
