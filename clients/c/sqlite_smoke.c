// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vev.h"

#define CHECK(condition, message)                 \
    do {                                          \
        if (!(condition)) {                       \
            fprintf(stderr, "%s\n", (message));   \
            return 1;                             \
        }                                         \
    } while (0)

static int check_error(vev_sqlite_db_t db, const char *context) {
    const char *message = vev_sqlite_db_error(db);
    fprintf(
        stderr,
        "%s: code=%d extended=%d message=%s\n",
        context,
        vev_sqlite_db_error_code(db),
        vev_sqlite_db_extended_error_code(db),
        message == NULL ? "" : message);
    vev_string_free(message);
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(
            stderr,
            "usage: sqlite-smoke <database-path> <vev-store-path>\n");
        return 2;
    }

    const char *version = vev_sqlite_version();
    const char *source_id = vev_sqlite_source_id();
    CHECK(version != NULL && strlen(version) > 0, "missing SQLite version");
    CHECK(source_id != NULL && strlen(source_id) > 0, "missing SQLite source id");
    vev_string_free(version);
    vev_string_free(source_id);
    CHECK(
        vev_sqlite_compile_option_used("ENABLE_FTS5"),
        "bundled SQLite is missing FTS5");

    vev_sqlite_db_t null_path = vev_sqlite_open(NULL);
    CHECK(null_path != NULL, "null path returned no error handle");
    CHECK(!vev_sqlite_db_ok(null_path), "null path unexpectedly opened");
    CHECK(
        vev_sqlite_db_error_code(null_path) == VEV_SQLITE_MISUSE,
        "null path returned the wrong error");
    vev_sqlite_db_close(null_path);

    char missing_path[4096];
    int missing_length = snprintf(
        missing_path,
        sizeof(missing_path),
        "%s-missing/child.sqlite",
        argv[1]);
    CHECK(
        missing_length > 0 && (size_t)missing_length < sizeof(missing_path),
        "could not construct missing SQLite path");
    vev_sqlite_db_t missing = vev_sqlite_open(missing_path);
    CHECK(missing != NULL, "failed open returned no error handle");
    CHECK(!vev_sqlite_db_ok(missing), "missing parent unexpectedly opened");
    CHECK(
        vev_sqlite_db_error_code(missing) == VEV_SQLITE_CANTOPEN,
        "failed open returned the wrong error");
    const char *missing_error = vev_sqlite_db_error(missing);
    CHECK(
        missing_error != NULL && strlen(missing_error) > 0,
        "failed open returned no message");
    vev_string_free(missing_error);
    vev_sqlite_db_close(missing);

    vev_sqlite_db_t db = vev_sqlite_open(argv[1]);
    CHECK(db != NULL, "SQLite open returned no handle");
    if (!vev_sqlite_db_ok(db)) {
        return check_error(db, "open");
    }
    CHECK(
        vev_sqlite_busy_timeout(db, 50) == VEV_SQLITE_OK,
        "could not set busy timeout");

    int rc = vev_sqlite_exec(
        db,
        "create table email ("
        "id integer primary key,"
        "label text not null,"
        "payload blob not null,"
        "attempts integer not null,"
        "score real not null,"
        "optional text)");
    if (rc != VEV_SQLITE_OK) {
        return check_error(db, "create table");
    }

    vev_sqlite_stmt_t insert = vev_sqlite_prepare(
        db,
        "insert into email(label, payload, attempts, score, optional) "
        "values(:label, :payload, :attempts, :score, :optional)");
    if (insert == NULL) {
        return check_error(db, "prepare insert");
    }
    CHECK(!vev_sqlite_stmt_readonly(insert), "insert marked readonly");
    CHECK(
        vev_sqlite_bind_parameter_count(insert) == 5,
        "wrong bind parameter count");
    CHECK(
        vev_sqlite_bind_parameter_index(insert, ":payload") == 2,
        "wrong named parameter index");
    const char *parameter_name = vev_sqlite_bind_parameter_name(insert, 1);
    CHECK(
        parameter_name != NULL && strcmp(parameter_name, ":label") == 0,
        "wrong parameter name");
    vev_string_free(parameter_name);

    const unsigned char label[] = {'a', '\0', 'b'};
    const unsigned char payload[] = {0, 1, 2, 0, 255};
    CHECK(
        vev_sqlite_bind_text(insert, 1, label, sizeof(label)) == VEV_SQLITE_OK,
        "could not bind text");
    CHECK(
        vev_sqlite_bind_blob(insert, 2, payload, sizeof(payload)) ==
            VEV_SQLITE_OK,
        "could not bind blob");
    CHECK(
        vev_sqlite_bind_int64(insert, 3, INT64_C(9223372036854770000)) ==
            VEV_SQLITE_OK,
        "could not bind int64");
    CHECK(
        vev_sqlite_bind_double(insert, 4, 3.25) == VEV_SQLITE_OK,
        "could not bind double");
    CHECK(
        vev_sqlite_bind_null(insert, 5) == VEV_SQLITE_OK,
        "could not bind null");
    rc = vev_sqlite_stmt_step(insert);
    if (rc != VEV_SQLITE_DONE) {
        return check_error(db, "step insert");
    }
    CHECK(vev_sqlite_changes(db) == 1, "wrong change count");
    CHECK(vev_sqlite_total_changes(db) == 1, "wrong total change count");
    CHECK(vev_sqlite_last_insert_rowid(db) == 1, "wrong inserted row id");
    CHECK(
        vev_sqlite_stmt_reset(insert) == VEV_SQLITE_OK,
        "could not reset insert");
    CHECK(
        vev_sqlite_stmt_clear_bindings(insert) == VEV_SQLITE_OK,
        "could not clear bindings");
    CHECK(
        vev_sqlite_stmt_finalize(insert) == VEV_SQLITE_OK,
        "could not finalize insert");

    vev_sqlite_stmt_t select = vev_sqlite_prepare(
        db,
        "select id, label, payload, attempts, score, optional "
        "from email where id = ?");
    if (select == NULL) {
        return check_error(db, "prepare select");
    }
    CHECK(vev_sqlite_stmt_readonly(select), "select not marked readonly");
    CHECK(
        vev_sqlite_bind_int64(select, 1, 1) == VEV_SQLITE_OK,
        "could not bind select id");
    CHECK(vev_sqlite_stmt_step(select) == VEV_SQLITE_ROW, "missing row");
    CHECK(vev_sqlite_column_count(select) == 6, "wrong column count");
    const char *column_name = vev_sqlite_column_name(select, 1);
    CHECK(
        column_name != NULL && strcmp(column_name, "label") == 0,
        "wrong column name");
    vev_string_free(column_name);
    CHECK(
        vev_sqlite_column_type(select, 0) == VEV_SQLITE_INTEGER,
        "id is not integer");
    CHECK(vev_sqlite_column_int64(select, 0) == 1, "wrong id");
    CHECK(
        vev_sqlite_column_type(select, 1) == VEV_SQLITE_TEXT,
        "label is not text");
    CHECK(
        vev_sqlite_column_bytes(select, 1) == (int)sizeof(label),
        "wrong text byte length");
    CHECK(
        memcmp(vev_sqlite_column_text(select, 1), label, sizeof(label)) == 0,
        "text with embedded NUL did not round-trip");
    CHECK(
        vev_sqlite_column_type(select, 2) == VEV_SQLITE_BLOB,
        "payload is not blob");
    CHECK(
        vev_sqlite_column_bytes(select, 2) == (int)sizeof(payload),
        "wrong blob length");
    CHECK(
        memcmp(
            vev_sqlite_column_blob(select, 2),
            payload,
            sizeof(payload)) == 0,
        "blob did not round-trip");
    CHECK(
        vev_sqlite_column_int64(select, 3) ==
            INT64_C(9223372036854770000),
        "int64 did not round-trip");
    CHECK(
        fabs(vev_sqlite_column_double(select, 4) - 3.25) < 0.000001,
        "double did not round-trip");
    CHECK(
        vev_sqlite_column_type(select, 5) == VEV_SQLITE_NULL,
        "null did not round-trip");
    CHECK(
        vev_sqlite_stmt_step(select) == VEV_SQLITE_DONE,
        "select returned an extra row");
    CHECK(
        vev_sqlite_stmt_finalize(select) == VEV_SQLITE_OK,
        "could not finalize select");

    CHECK(vev_sqlite_autocommit(db), "autocommit should start enabled");
    CHECK(
        vev_sqlite_exec(db, "begin immediate") == VEV_SQLITE_OK,
        "could not begin transaction");
    CHECK(!vev_sqlite_autocommit(db), "transaction did not disable autocommit");
    CHECK(
        vev_sqlite_exec(db, "insert into email values(2,'x',x'',1,1.0,null)") ==
            VEV_SQLITE_OK,
        "transaction insert failed");
    CHECK(
        vev_sqlite_exec(db, "rollback") == VEV_SQLITE_OK,
        "rollback failed");
    CHECK(vev_sqlite_autocommit(db), "rollback did not restore autocommit");

    rc = vev_sqlite_exec(db, "this is not SQL");
    CHECK(rc != VEV_SQLITE_OK, "invalid SQL unexpectedly succeeded");
    const char *error = vev_sqlite_db_error(db);
    CHECK(error != NULL && strlen(error) > 0, "missing SQL error message");
    vev_string_free(error);

    vev_sqlite_db_t competing = vev_sqlite_open(argv[1]);
    CHECK(
        competing != NULL && vev_sqlite_db_ok(competing),
        "could not open competing connection");
    CHECK(
        vev_sqlite_busy_timeout(competing, 0) == VEV_SQLITE_OK,
        "could not configure competing connection");
    CHECK(
        vev_sqlite_exec(db, "begin immediate") == VEV_SQLITE_OK,
        "could not take write lock");
    rc = vev_sqlite_exec(
        competing,
        "insert into email values(3,'locked',x'',1,1.0,null)");
    CHECK(
        rc == VEV_SQLITE_BUSY || rc == VEV_SQLITE_LOCKED,
        "competing writer did not report busy/locked");
    CHECK(
        vev_sqlite_exec(db, "rollback") == VEV_SQLITE_OK,
        "could not release write lock");
    vev_sqlite_db_close(competing);
    vev_sqlite_db_close(db);

    vev_sqlite_db_t readonly = vev_sqlite_open_v2(
        argv[1],
        VEV_SQLITE_OPEN_READONLY | VEV_SQLITE_OPEN_FULLMUTEX);
    CHECK(readonly != NULL && vev_sqlite_db_ok(readonly), "readonly open failed");
    rc = vev_sqlite_exec(
        readonly,
        "insert into email values(4,'readonly',x'',1,1.0,null)");
    CHECK(rc == VEV_SQLITE_READONLY, "readonly write returned wrong result");
    vev_sqlite_db_close(readonly);

    vev_connection_t facts = vev_connect(argv[2]);
    CHECK(
        facts != NULL && vev_connection_ok(facts),
        "could not create VevDB safety-test store");
    vev_connection_close(facts);
    vev_sqlite_db_t protected_store = vev_sqlite_open(argv[2]);
    CHECK(protected_store != NULL, "protected open returned no wrapper");
    CHECK(
        !vev_sqlite_db_ok(protected_store),
        "raw SQLite unexpectedly opened a VevDB store");
    CHECK(
        vev_sqlite_db_error_code(protected_store) == VEV_SQLITE_AUTH,
        "protected VevDB store returned the wrong error");
    error = vev_sqlite_db_error(protected_store);
    CHECK(
        error != NULL && strstr(error, "VevDB") != NULL,
        "protected VevDB store returned an unclear error");
    vev_string_free(error);
    vev_sqlite_db_close(protected_store);

    puts(":vev-sqlite-c-ok");
    return 0;
}
