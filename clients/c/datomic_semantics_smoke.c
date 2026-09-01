#include "vev.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

static int report_ok(vev_tx_report_t report) {
    if (report == NULL) return 0;
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t ok = vev_value_map_get(value, ":ok");
    return ok != NULL &&
           vev_value_kind(ok) == VEV_VALUE_BOOL &&
           vev_value_bool(ok);
}

int main(void) {
    const char *uuid = vev_squuid();
    long long uuid_time = vev_squuid_time_millis(uuid);
    long long now = (long long)time(NULL) * 1000;
    if (uuid == NULL || strlen(uuid) != 36 ||
        uuid_time < now - 1000 || uuid_time > now + 1000 ||
        uuid_time % 1000 != 0) {
        fprintf(stderr, "C squuid contract failed\n");
        if (uuid != NULL) vev_string_free(uuid);
        return 1;
    }
    vev_string_free(uuid);

    vev_conn_t conn = vev_conn_open_memory();
    if (conn == NULL) return 1;

    vev_tx_report_t schema = vev_transact_edn_report(
        conn,
        "[{:db/id 100 :db/ident :person/email"
        "  :db/valueType :db.type/string"
        "  :db/cardinality :db.cardinality/one"
        "  :db/unique :db.unique/identity}"
        " {:db/id 101 :db/ident :person/number"
        "  :db/valueType :db.type/long"
        "  :db/cardinality :db.cardinality/one"
        "  :db/unique :db.unique/identity}"
        " {:db/id 102 :db/ident :person/friend"
        "  :db/valueType :db.type/ref"
        "  :db/cardinality :db.cardinality/one}]");
    if (!report_ok(schema)) {
        fprintf(stderr, "schema transaction failed\n");
        vev_tx_report_free(schema);
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_free(schema);

    vev_tx_report_t data = vev_transact_edn_report(
        conn,
        "[{:db/id \"ada\" :person/email \"ada@example.com\" :person/number 1815"
        "  :person/friend \"grace\"}"
        " {:db/id \"grace\" :person/email \"grace@example.com\" :person/number 1906}]");
    if (!report_ok(data)) {
        fprintf(stderr, "data transaction failed\n");
        vev_tx_report_free(data);
        vev_conn_close(conn);
        return 1;
    }
    unsigned long long ada =
        vev_tx_report_resolve_tempid_edn(data, "\"ada\"");
    if (ada == 0) {
        fprintf(stderr, "C tempid resolution failed\n");
        vev_tx_report_free(data);
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_free(data);

    vev_db_t db = vev_conn_db(conn);
    vev_value_handle_t stats = vev_db_stats_value(db);
    vev_value_t stats_value =
        stats == NULL ? NULL : vev_value_handle_value(stats);
    vev_value_t datom_count =
        stats_value == NULL ? NULL : vev_value_map_get(stats_value, ":datoms");
    vev_value_t attrs =
        stats_value == NULL ? NULL : vev_value_map_get(stats_value, ":attrs");
    vev_value_t email_stats =
        attrs == NULL ? NULL : vev_value_map_get(attrs, ":person/email");
    vev_value_t email_count =
        email_stats == NULL ? NULL : vev_value_map_get(email_stats, ":count");
    if (stats == NULL ||
        datom_count == NULL || vev_value_int(datom_count) <= 0 ||
        email_count == NULL || vev_value_int(email_count) != 2) {
        fprintf(stderr, "C DB stats contract failed\n");
        if (stats != NULL) {
            const char *stats_edn = vev_value_handle_edn(stats);
            if (stats_edn != NULL) {
                fprintf(stderr, "stats: %s\n", stats_edn);
                vev_string_free(stats_edn);
            }
        }
        if (stats != NULL) vev_value_handle_free(stats);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(stats);

    vev_value_handle_t attribute =
        vev_db_attribute_value(db, ":person/email");
    vev_value_t attribute_value =
        attribute == NULL ? NULL : vev_value_handle_value(attribute);
    vev_value_t attribute_ident =
        attribute_value == NULL
            ? NULL
            : vev_value_map_get(attribute_value, ":ident");
    vev_value_t attribute_type =
        attribute_value == NULL
            ? NULL
            : vev_value_map_get(attribute_value, ":value-type");
    if (attribute == NULL ||
        attribute_ident == NULL ||
        strcmp(vev_value_text(attribute_ident), ":person/email") != 0 ||
        attribute_type == NULL ||
        strcmp(vev_value_text(attribute_type), ":db.type/string") != 0) {
        fprintf(stderr, "C attribute contract failed\n");
        if (attribute != NULL) vev_value_handle_free(attribute);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(attribute);

    vev_value_handle_t numeric_datoms =
        vev_db_datoms_value(db, 0, ":avet", "[100]");
    vev_value_t numeric_datoms_value =
        numeric_datoms == NULL
            ? NULL
            : vev_value_handle_value(numeric_datoms);
    if (numeric_datoms == NULL ||
        vev_value_item_count(numeric_datoms_value) != 2) {
        fprintf(stderr, "numeric attribute datoms contract failed\n");
        if (numeric_datoms != NULL) vev_value_handle_free(numeric_datoms);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(numeric_datoms);

    vev_value_handle_t numeric_seek =
        vev_db_datoms_value(db, 1, ":avet", "[100 \"g\"]");
    vev_value_t numeric_seek_value =
        numeric_seek == NULL ? NULL : vev_value_handle_value(numeric_seek);
    vev_value_t seek_datom =
        numeric_seek_value == NULL ? NULL : vev_value_item(numeric_seek_value, 0);
    vev_value_t seek_value =
        seek_datom == NULL ? NULL : vev_value_map_get(seek_datom, ":v");
    if (numeric_seek == NULL || seek_value == NULL ||
        strcmp(vev_value_text(seek_value), "grace@example.com") != 0) {
        fprintf(stderr, "numeric attribute seek-datoms contract failed\n");
        if (numeric_seek != NULL) vev_value_handle_free(numeric_seek);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(numeric_seek);

    vev_value_handle_t numeric_rseek =
        vev_db_datoms_value(db, 2, ":avet", "[100 \"g\"]");
    vev_value_t numeric_rseek_value =
        numeric_rseek == NULL ? NULL : vev_value_handle_value(numeric_rseek);
    vev_value_t rseek_datom =
        numeric_rseek_value == NULL
            ? NULL
            : vev_value_item(numeric_rseek_value, 0);
    vev_value_t rseek_value =
        rseek_datom == NULL ? NULL : vev_value_map_get(rseek_datom, ":v");
    if (numeric_rseek == NULL || rseek_value == NULL ||
        strcmp(vev_value_text(rseek_value), "ada@example.com") != 0) {
        fprintf(stderr, "numeric attribute rseek-datoms contract failed\n");
        if (numeric_rseek != NULL) vev_value_handle_free(numeric_rseek);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(numeric_rseek);

    vev_value_handle_t numeric_range =
        vev_db_index_range_value(db, "100", "\"a\"", "\"b\"");
    vev_value_t numeric_range_value =
        numeric_range == NULL ? NULL : vev_value_handle_value(numeric_range);
    vev_value_t range_datom =
        numeric_range_value == NULL
            ? NULL
            : vev_value_item(numeric_range_value, 0);
    vev_value_t range_value =
        range_datom == NULL ? NULL : vev_value_map_get(range_datom, ":v");
    if (numeric_range == NULL ||
        vev_value_item_count(numeric_range_value) != 1 ||
        range_value == NULL ||
        strcmp(vev_value_text(range_value), "ada@example.com") != 0) {
        fprintf(stderr, "numeric attribute index-range contract failed\n");
        if (numeric_range != NULL) vev_value_handle_free(numeric_range);
        vev_db_release(db);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(numeric_range);

    vev_entity_t by_string = vev_db_entity_lookup_ref_edn(
        db, ":person/email", "\"ada@example.com\"");
    vev_entity_t by_long = vev_db_entity_lookup_ref_edn(
        db, ":person/number", "1815");
    int ok = by_string != NULL && by_long != NULL &&
             vev_entity_found(by_string) && vev_entity_found(by_long) &&
             vev_entity_id(by_string) == ada && vev_entity_id(by_long) == ada;

    vev_value_handle_t index_pull = vev_db_index_pull_value(
        db,
        ":avet",
        "[:person/email]",
        "[:person/email]",
        false,
        0,
        1);
    vev_value_t index_pull_value =
        index_pull == NULL ? NULL : vev_value_handle_value(index_pull);
    vev_value_t pulled =
        index_pull_value == NULL ? NULL : vev_value_item(index_pull_value, 0);
    vev_value_t pulled_email =
        pulled == NULL ? NULL : vev_value_map_get(pulled, ":person/email");
    if (index_pull == NULL ||
        vev_value_item_count(index_pull_value) != 1 ||
        pulled_email == NULL ||
        strcmp(vev_value_text(pulled_email), "ada@example.com") != 0) {
        fprintf(stderr, "C index-pull contract failed\n");
        ok = 0;
    }
    if (index_pull != NULL) vev_value_handle_free(index_pull);

    vev_value_handle_t reverse_index_pull = vev_db_index_pull_value(
        db,
        ":avet",
        "[:person/email]",
        "[:person/email]",
        true,
        1,
        1);
    vev_value_t reverse_value =
        reverse_index_pull == NULL
            ? NULL
            : vev_value_handle_value(reverse_index_pull);
    vev_value_t reverse_pulled =
        reverse_value == NULL ? NULL : vev_value_item(reverse_value, 0);
    vev_value_t reverse_email =
        reverse_pulled == NULL
            ? NULL
            : vev_value_map_get(reverse_pulled, ":person/email");
    if (reverse_index_pull == NULL ||
        vev_value_item_count(reverse_value) != 1 ||
        reverse_email == NULL ||
        strcmp(vev_value_text(reverse_email), "ada@example.com") != 0) {
        fprintf(stderr, "C reverse index-pull contract failed\n");
        ok = 0;
    }
    if (reverse_index_pull != NULL) {
        vev_value_handle_free(reverse_index_pull);
    }

    vev_value_handle_t aevt_index_pull = vev_db_index_pull_value(
        db,
        ":aevt",
        "[:person/email]",
        "[:person/friend]",
        false,
        0,
        -1);
    vev_value_t aevt_value =
        aevt_index_pull == NULL ? NULL : vev_value_handle_value(aevt_index_pull);
    vev_value_t aevt_pulled =
        aevt_value == NULL ? NULL : vev_value_item(aevt_value, 0);
    vev_value_t aevt_email =
        aevt_pulled == NULL
            ? NULL
            : vev_value_map_get(aevt_pulled, ":person/email");
    if (aevt_index_pull == NULL ||
        vev_value_item_count(aevt_value) != 1 ||
        aevt_email == NULL ||
        strcmp(vev_value_text(aevt_email), "grace@example.com") != 0) {
        fprintf(stderr, "C AEVT index-pull contract failed\n");
        ok = 0;
    }
    if (aevt_index_pull != NULL) {
        vev_value_handle_free(aevt_index_pull);
    }

    vev_tx_report_t failed_tx = vev_transact_edn_report(
        conn,
        "[[:db/add 1 :person/email nil]]");
    vev_value_t failed_tx_value =
        failed_tx == NULL ? NULL : vev_tx_report_value(failed_tx);
    vev_value_t failed_tx_error =
        failed_tx_value == NULL
            ? NULL
            : vev_value_map_get(failed_tx_value, ":vev/error");
    if (failed_tx == NULL || report_ok(failed_tx) ||
        failed_tx_error == NULL ||
        strcmp(
            vev_value_text(failed_tx_error),
            ":vev.error/transaction-failed") != 0) {
        fprintf(stderr, "C transact error contract failed\n");
        ok = 0;
    }
    if (failed_tx != NULL) vev_tx_report_free(failed_tx);

    vev_tx_report_t failed_with = vev_with_edn_report(
        db,
        "[[:db/add 1 :person/email nil]]");
    vev_value_t failed_with_value =
        failed_with == NULL ? NULL : vev_tx_report_value(failed_with);
    vev_value_t failed_with_error =
        failed_with_value == NULL
            ? NULL
            : vev_value_map_get(failed_with_value, ":vev/error");
    if (failed_with == NULL || report_ok(failed_with) ||
        failed_with_error == NULL ||
        strcmp(
            vev_value_text(failed_with_error),
            ":vev.error/transaction-failed") != 0) {
        fprintf(stderr, "C with error contract failed\n");
        ok = 0;
    }
    if (failed_with != NULL) vev_tx_report_free(failed_with);

    if (by_string != NULL) vev_entity_free(by_string);
    if (by_long != NULL) vev_entity_free(by_long);
    vev_db_release(db);
    vev_conn_close(conn);

    if (!ok) {
        fprintf(stderr, "generic C lookup refs did not resolve\n");
        return 1;
    }
    puts(":vev-c-datomic-semantics-ok");
    return 0;
}
