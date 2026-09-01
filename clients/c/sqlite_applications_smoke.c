#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vev.h"

#define REQUIRE(condition, message)              \
    do {                                         \
        if (!(condition)) {                      \
            fprintf(stderr, "%s\n", (message));  \
            goto fail;                           \
        }                                        \
    } while (0)

static void print_error(vev_sqlite_db_t db, const char *context) {
    const char *message = vev_sqlite_db_error(db);
    fprintf(
        stderr,
        "%s: code=%d extended=%d message=%s\n",
        context,
        vev_sqlite_db_error_code(db),
        vev_sqlite_db_extended_error_code(db),
        message == NULL ? "" : message);
    vev_string_free(message);
}

static int execute(vev_sqlite_db_t db, const char *sql) {
    int code = vev_sqlite_exec(db, sql);
    if (code != VEV_SQLITE_OK) print_error(db, sql);
    return code;
}

static int bind_text(vev_sqlite_stmt_t stmt, int index, const char *value) {
    return vev_sqlite_bind_text(stmt, index, value, strlen(value));
}

static int scalar_int64(
    vev_sqlite_db_t db,
    const char *sql,
    int64_t *value
) {
    vev_sqlite_stmt_t stmt = vev_sqlite_prepare(db, sql);
    if (stmt == NULL) return vev_sqlite_db_error_code(db);
    int code = vev_sqlite_stmt_step(stmt);
    if (code == VEV_SQLITE_ROW) {
        *value = vev_sqlite_column_int64(stmt, 0);
        code = vev_sqlite_stmt_step(stmt);
    }
    int finalize_code = vev_sqlite_stmt_finalize(stmt);
    if (code != VEV_SQLITE_DONE) return code;
    return finalize_code;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: sqlite-applications-smoke <database-path>\n");
        return 2;
    }

    int result = 1;
    vev_sqlite_db_t db = vev_sqlite_open(argv[1]);
    vev_sqlite_db_t second = NULL;
    vev_sqlite_stmt_t stmt = NULL;
    REQUIRE(db != NULL && vev_sqlite_db_ok(db), "could not open app database");
    REQUIRE(
        vev_sqlite_busy_timeout(db, 1000) == VEV_SQLITE_OK,
        "could not set busy timeout");
    REQUIRE(
        execute(
            db,
            "pragma foreign_keys=on;"
            "pragma journal_mode=wal;"
            "create table cache_entries("
            " cache_key text primary key,"
            " value blob not null,"
            " encoding text not null,"
            " expires_at integer,"
            " updated_at integer not null"
            ");"
            "create index cache_expiry on cache_entries(expires_at);"
            "create table jobs("
            " id integer primary key,"
            " queue text not null,"
            " payload text not null,"
            " priority integer not null default 0,"
            " available_at integer not null,"
            " attempts integer not null default 0,"
            " locked_by text,"
            " locked_at integer,"
            " unique_key text unique"
            ");"
            "create index jobs_ready "
            " on jobs(queue, available_at, priority desc, id);"
            "create table mailboxes("
            " id integer primary key,"
            " address text not null unique"
            ");"
            "create table emails("
            " id integer primary key,"
            " mailbox_id integer not null references mailboxes(id),"
            " message_id text not null unique,"
            " subject text not null,"
            " body text not null,"
            " raw_message blob not null,"
            " received_at integer not null"
            ");"
            "create virtual table email_search using "
            " fts5(subject, body, content='emails', content_rowid='id');"
            "create table outbox("
            " id integer primary key,"
            " email_id integer not null references emails(id),"
            " state text not null,"
            " attempts integer not null default 0"
            ");") == VEV_SQLITE_OK,
        "could not create application schemas");

    /* Cache: arbitrary strings, EDN, blobs, UPSERT, and TTL eviction. */
    stmt = vev_sqlite_prepare(
        db,
        "insert into cache_entries(cache_key,value,encoding,expires_at,updated_at)"
        " values(?,?,?,?,?)"
        " on conflict(cache_key) do update set"
        " value=excluded.value,encoding=excluded.encoding,"
        " expires_at=excluded.expires_at,updated_at=excluded.updated_at");
    REQUIRE(stmt != NULL, "could not prepare cache put");
    const char *cache_keys[] = {"session:1", "result:edn", "plain:string"};
    const char *cache_values[] = {
        "opaque-session-token",
        "{:answer 42 :tags #{:cached :edn}}",
        "just a string"};
    const char *cache_encodings[] = {"text", "edn", "text"};
    int64_t expiries[] = {2000, 0, 900};
    for (int index = 0; index < 3; index++) {
        REQUIRE(bind_text(stmt, 1, cache_keys[index]) == VEV_SQLITE_OK, "cache key bind failed");
        REQUIRE(bind_text(stmt, 2, cache_values[index]) == VEV_SQLITE_OK, "cache value bind failed");
        REQUIRE(bind_text(stmt, 3, cache_encodings[index]) == VEV_SQLITE_OK, "cache encoding bind failed");
        if (expiries[index] == 0) {
            REQUIRE(vev_sqlite_bind_null(stmt, 4) == VEV_SQLITE_OK, "cache nil expiry bind failed");
        } else {
            REQUIRE(vev_sqlite_bind_int64(stmt, 4, expiries[index]) == VEV_SQLITE_OK, "cache expiry bind failed");
        }
        REQUIRE(vev_sqlite_bind_int64(stmt, 5, 1000 + index) == VEV_SQLITE_OK, "cache timestamp bind failed");
        REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_DONE, "cache put failed");
        REQUIRE(vev_sqlite_stmt_reset(stmt) == VEV_SQLITE_OK, "cache reset failed");
        REQUIRE(vev_sqlite_stmt_clear_bindings(stmt) == VEV_SQLITE_OK, "cache clear failed");
    }
    REQUIRE(vev_sqlite_stmt_finalize(stmt) == VEV_SQLITE_OK, "cache finalize failed");
    stmt = NULL;

    const unsigned char calculated[] = {0, 255, 7, 0, 9};
    stmt = vev_sqlite_prepare(
        db,
        "insert into cache_entries values('result:binary',?,'bytes',null,1003)");
    REQUIRE(stmt != NULL, "could not prepare binary cache put");
    REQUIRE(
        vev_sqlite_bind_blob(stmt, 1, calculated, sizeof(calculated)) == VEV_SQLITE_OK,
        "binary cache bind failed");
    REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_DONE, "binary cache put failed");
    REQUIRE(vev_sqlite_stmt_finalize(stmt) == VEV_SQLITE_OK, "binary cache finalize failed");
    stmt = NULL;

    REQUIRE(
        execute(
            db,
            "delete from cache_entries "
            "where expires_at is not null and expires_at <= 1000") == VEV_SQLITE_OK,
        "cache eviction failed");
    int64_t count = 0;
    REQUIRE(
        scalar_int64(db, "select count(*) from cache_entries", &count) == VEV_SQLITE_OK,
        "cache count failed");
    REQUIRE(count == 3, "cache eviction removed the wrong entries");

    /* Queue: atomic claim with RETURNING, acknowledgement, and retry. */
    REQUIRE(
        execute(
            db,
            "insert into jobs(queue,payload,priority,available_at,unique_key) values"
            " ('mail','{:email/id 1}',5,100,'send-1'),"
            " ('mail','plain payload',10,100,'send-2'),"
            " ('mail','later',100,500,'send-3')") == VEV_SQLITE_OK,
        "queue enqueue failed");
    REQUIRE(execute(db, "begin immediate") == VEV_SQLITE_OK, "queue begin failed");
    REQUIRE(!vev_sqlite_autocommit(db), "queue transaction not active");
    stmt = vev_sqlite_prepare(
        db,
        "update jobs set locked_by=?,locked_at=?,attempts=attempts+1"
        " where id=("
        "  select id from jobs"
        "  where queue=? and available_at<=? and locked_by is null"
        "  order by priority desc,id limit 1"
        " ) returning id,payload,attempts");
    REQUIRE(stmt != NULL, "could not prepare queue claim");
    REQUIRE(bind_text(stmt, 1, "worker-c") == VEV_SQLITE_OK, "worker bind failed");
    REQUIRE(vev_sqlite_bind_int64(stmt, 2, 101) == VEV_SQLITE_OK, "lock time bind failed");
    REQUIRE(bind_text(stmt, 3, "mail") == VEV_SQLITE_OK, "queue bind failed");
    REQUIRE(vev_sqlite_bind_int64(stmt, 4, 101) == VEV_SQLITE_OK, "ready time bind failed");
    REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_ROW, "queue claim returned no job");
    int64_t claimed_id = vev_sqlite_column_int64(stmt, 0);
    REQUIRE(claimed_id == 2, "queue did not claim highest priority ready job");
    REQUIRE(vev_sqlite_column_int64(stmt, 2) == 1, "queue attempts not incremented");
    REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_DONE, "queue claim returned extra job");
    REQUIRE(vev_sqlite_stmt_finalize(stmt) == VEV_SQLITE_OK, "queue claim finalize failed");
    stmt = NULL;
    REQUIRE(execute(db, "commit") == VEV_SQLITE_OK, "queue commit failed");
    stmt = vev_sqlite_prepare(db, "delete from jobs where id=? and locked_by=?");
    REQUIRE(stmt != NULL, "could not prepare queue ack");
    REQUIRE(vev_sqlite_bind_int64(stmt, 1, claimed_id) == VEV_SQLITE_OK, "ack id bind failed");
    REQUIRE(bind_text(stmt, 2, "worker-c") == VEV_SQLITE_OK, "ack worker bind failed");
    REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_DONE, "queue ack failed");
    REQUIRE(vev_sqlite_changes(db) == 1, "queue ack changed wrong row count");
    REQUIRE(vev_sqlite_stmt_finalize(stmt) == VEV_SQLITE_OK, "queue ack finalize failed");
    stmt = NULL;
    REQUIRE(
        execute(
            db,
            "update jobs set locked_by=null,locked_at=null,available_at=200 "
            "where id=1") == VEV_SQLITE_OK,
        "queue retry scheduling failed");

    /* Email: foreign keys, binary raw message, transaction, join, and FTS5. */
    REQUIRE(execute(db, "begin") == VEV_SQLITE_OK, "email begin failed");
    REQUIRE(
        execute(db, "insert into mailboxes(address) values('ada@example.com')") ==
            VEV_SQLITE_OK,
        "mailbox insert failed");
    stmt = vev_sqlite_prepare(
        db,
        "insert into emails("
        " mailbox_id,message_id,subject,body,raw_message,received_at"
        ") values(?,?,?,?,?,?)");
    REQUIRE(stmt != NULL, "could not prepare email insert");
    const unsigned char raw_mail[] = {
        'F','r','o','m',':',' ','x','\r','\n','\r','\n',0,'b','o','d','y'};
    REQUIRE(vev_sqlite_bind_int64(stmt, 1, 1) == VEV_SQLITE_OK, "mailbox id bind failed");
    REQUIRE(bind_text(stmt, 2, "<message-1@example.com>") == VEV_SQLITE_OK, "message id bind failed");
    REQUIRE(bind_text(stmt, 3, "Quarterly cache report") == VEV_SQLITE_OK, "subject bind failed");
    REQUIRE(bind_text(stmt, 4, "Queue processing completed") == VEV_SQLITE_OK, "body bind failed");
    REQUIRE(vev_sqlite_bind_blob(stmt, 5, raw_mail, sizeof(raw_mail)) == VEV_SQLITE_OK, "raw mail bind failed");
    REQUIRE(vev_sqlite_bind_int64(stmt, 6, 1234567890) == VEV_SQLITE_OK, "received time bind failed");
    REQUIRE(vev_sqlite_stmt_step(stmt) == VEV_SQLITE_DONE, "email insert failed");
    REQUIRE(vev_sqlite_stmt_finalize(stmt) == VEV_SQLITE_OK, "email finalize failed");
    stmt = NULL;
    REQUIRE(
        execute(
            db,
            "insert into email_search(rowid,subject,body)"
            " select id,subject,body from emails where id=1;"
            "insert into outbox(email_id,state) values(1,'pending');"
            "commit") == VEV_SQLITE_OK,
        "email indexing/outbox commit failed");
    REQUIRE(
        scalar_int64(
            db,
            "select count(*) from email_search where email_search match 'queue'",
            &count) == VEV_SQLITE_OK,
        "email search failed");
    REQUIRE(count == 1, "email search returned wrong result");

    int rc = vev_sqlite_exec(
        db,
        "insert into outbox(email_id,state) values(999,'pending')");
    REQUIRE(
        (rc & 0xff) == VEV_SQLITE_CONSTRAINT,
        "email foreign-key violation returned wrong code");

    second = vev_sqlite_open(argv[1]);
    REQUIRE(second != NULL && vev_sqlite_db_ok(second), "second connection failed");
    REQUIRE(
        scalar_int64(second, "select count(*) from cache_entries", &count) ==
            VEV_SQLITE_OK,
        "second connection could not see committed cache rows");
    REQUIRE(count == 3, "second connection saw wrong cache count");
    vev_sqlite_db_close(second);
    second = NULL;

    result = 0;
    puts(":vev-sqlite-applications-c-ok");

fail:
    if (stmt != NULL) vev_sqlite_stmt_finalize(stmt);
    if (second != NULL) vev_sqlite_db_close(second);
    if (db != NULL) {
        if (!vev_sqlite_autocommit(db)) vev_sqlite_exec(db, "rollback");
        vev_sqlite_db_close(db);
    }
    return result;
}
