// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#ifndef VEV_SQLITE_H
#define VEV_SQLITE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef void *vev_sqlite_db_t;
typedef void *vev_sqlite_stmt_t;

/* Stable values matching SQLite's primary result codes. */
enum {
    VEV_SQLITE_OK = 0,
    VEV_SQLITE_ERROR = 1,
    VEV_SQLITE_INTERNAL = 2,
    VEV_SQLITE_PERM = 3,
    VEV_SQLITE_ABORT = 4,
    VEV_SQLITE_BUSY = 5,
    VEV_SQLITE_LOCKED = 6,
    VEV_SQLITE_NOMEM = 7,
    VEV_SQLITE_READONLY = 8,
    VEV_SQLITE_INTERRUPT = 9,
    VEV_SQLITE_IOERR = 10,
    VEV_SQLITE_CORRUPT = 11,
    VEV_SQLITE_NOTFOUND = 12,
    VEV_SQLITE_FULL = 13,
    VEV_SQLITE_CANTOPEN = 14,
    VEV_SQLITE_PROTOCOL = 15,
    VEV_SQLITE_EMPTY = 16,
    VEV_SQLITE_SCHEMA = 17,
    VEV_SQLITE_TOOBIG = 18,
    VEV_SQLITE_CONSTRAINT = 19,
    VEV_SQLITE_MISMATCH = 20,
    VEV_SQLITE_MISUSE = 21,
    VEV_SQLITE_NOLFS = 22,
    VEV_SQLITE_AUTH = 23,
    VEV_SQLITE_FORMAT = 24,
    VEV_SQLITE_RANGE = 25,
    VEV_SQLITE_NOTADB = 26,
    VEV_SQLITE_NOTICE = 27,
    VEV_SQLITE_WARNING = 28,
    VEV_SQLITE_ROW = 100,
    VEV_SQLITE_DONE = 101,
};

enum {
    VEV_SQLITE_INTEGER = 1,
    VEV_SQLITE_FLOAT = 2,
    VEV_SQLITE_TEXT = 3,
    VEV_SQLITE_BLOB = 4,
    VEV_SQLITE_NULL = 5,
};

enum {
    VEV_SQLITE_OPEN_READONLY = 0x00000001,
    VEV_SQLITE_OPEN_READWRITE = 0x00000002,
    VEV_SQLITE_OPEN_CREATE = 0x00000004,
    VEV_SQLITE_OPEN_URI = 0x00000040,
    VEV_SQLITE_OPEN_MEMORY = 0x00000080,
    VEV_SQLITE_OPEN_NOMUTEX = 0x00008000,
    VEV_SQLITE_OPEN_FULLMUTEX = 0x00010000,
};

/*
 * vev_sqlite_open uses READWRITE | CREATE | FULLMUTEX. It returns a handle
 * even when opening fails so callers can inspect the error and close it.
 */
vev_sqlite_db_t vev_sqlite_open(const char *path);
vev_sqlite_db_t vev_sqlite_open_v2(const char *path, int flags);
bool vev_sqlite_db_ok(vev_sqlite_db_t db);
int vev_sqlite_db_error_code(vev_sqlite_db_t db);
int vev_sqlite_db_extended_error_code(vev_sqlite_db_t db);
/* Returned error text must be released with vev_string_free. */
const char *vev_sqlite_db_error(vev_sqlite_db_t db);
void vev_sqlite_db_close(vev_sqlite_db_t db);

int vev_sqlite_exec(vev_sqlite_db_t db, const char *sql);
vev_sqlite_stmt_t vev_sqlite_prepare(
    vev_sqlite_db_t db,
    const char *sql);
int vev_sqlite_stmt_finalize(vev_sqlite_stmt_t statement);
int vev_sqlite_stmt_reset(vev_sqlite_stmt_t statement);
int vev_sqlite_stmt_clear_bindings(vev_sqlite_stmt_t statement);
int vev_sqlite_stmt_step(vev_sqlite_stmt_t statement);
bool vev_sqlite_stmt_readonly(vev_sqlite_stmt_t statement);

/* Bind indexes are one-based, as in SQLite. Input bytes are copied. */
int vev_sqlite_bind_null(vev_sqlite_stmt_t statement, int index);
int vev_sqlite_bind_int64(
    vev_sqlite_stmt_t statement,
    int index,
    int64_t value);
int vev_sqlite_bind_double(
    vev_sqlite_stmt_t statement,
    int index,
    double value);
int vev_sqlite_bind_text(
    vev_sqlite_stmt_t statement,
    int index,
    const void *data,
    uint64_t length);
int vev_sqlite_bind_blob(
    vev_sqlite_stmt_t statement,
    int index,
    const void *data,
    uint64_t length);
int vev_sqlite_bind_parameter_count(vev_sqlite_stmt_t statement);
int vev_sqlite_bind_parameter_index(
    vev_sqlite_stmt_t statement,
    const char *name);
/* Returned parameter name must be released with vev_string_free. */
const char *vev_sqlite_bind_parameter_name(
    vev_sqlite_stmt_t statement,
    int index);

/* Column indexes are zero-based and valid while step returns ROW. */
int vev_sqlite_column_count(vev_sqlite_stmt_t statement);
/* Returned column name must be released with vev_string_free. */
const char *vev_sqlite_column_name(
    vev_sqlite_stmt_t statement,
    int index);
int vev_sqlite_column_type(vev_sqlite_stmt_t statement, int index);
int64_t vev_sqlite_column_int64(
    vev_sqlite_stmt_t statement,
    int index);
double vev_sqlite_column_double(
    vev_sqlite_stmt_t statement,
    int index);
/*
 * Text/blob pointers are borrowed. They remain valid only until the next
 * step, reset, or finalize on the statement. Use column_bytes for the length.
 */
const void *vev_sqlite_column_text(
    vev_sqlite_stmt_t statement,
    int index);
const void *vev_sqlite_column_blob(
    vev_sqlite_stmt_t statement,
    int index);
int vev_sqlite_column_bytes(vev_sqlite_stmt_t statement, int index);

int64_t vev_sqlite_changes(vev_sqlite_db_t db);
int64_t vev_sqlite_total_changes(vev_sqlite_db_t db);
int64_t vev_sqlite_last_insert_rowid(vev_sqlite_db_t db);
bool vev_sqlite_autocommit(vev_sqlite_db_t db);
int vev_sqlite_busy_timeout(vev_sqlite_db_t db, int milliseconds);
void vev_sqlite_interrupt(vev_sqlite_db_t db);

/* Returned version/source strings must be released with vev_string_free. */
const char *vev_sqlite_version(void);
const char *vev_sqlite_source_id(void);
bool vev_sqlite_compile_option_used(const char *option);

#ifdef __cplusplus
}
#endif

#endif
