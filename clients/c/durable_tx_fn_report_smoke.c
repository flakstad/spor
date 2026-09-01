#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vev.h"

static const char *mark_seen_tx_fn(void *user, vev_db_t db, int argc, vev_tx_fn_args_t args) {
    (void)user;
    (void)db;
    static char out[256];
    if (argc != 2) {
        return NULL;
    }
    vev_value_t entity = vev_tx_fn_arg(args, 0);
    vev_value_t label = vev_tx_fn_arg(args, 1);
    if (vev_value_kind(entity) != VEV_VALUE_INT || vev_value_kind(label) != VEV_VALUE_STRING) {
        return NULL;
    }
    const char *label_text = vev_value_text(label);
    snprintf(out, sizeof(out), "[[:db/add %lld :user/seen-label \"%s\"]]", vev_value_int(entity), label_text);
    vev_string_free(label_text);
    return out;
}

static int report_ok(const char *label, vev_tx_report_t report) {
    if (report == NULL) {
        fprintf(stderr, "%s: null report\n", label);
        return 0;
    }
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t ok = vev_value_map_get(value, ":ok");
    if (vev_value_kind(ok) == VEV_VALUE_BOOL && vev_value_bool(ok)) {
        return 1;
    }
    const char *edn = vev_tx_report_edn(report);
    fprintf(stderr, "%s failed: %s\n", label, edn);
    vev_string_free(edn);
    return 0;
}

static int print_report_contains(const char *label, vev_tx_report_t report, const char *needle) {
    const char *edn = vev_tx_report_edn(report);
    printf("%s: %s\n", label, edn);
    int ok = strstr(edn, needle) != NULL;
    if (!ok) {
        fprintf(stderr, "%s: missing %s\n", label, needle);
    }
    vev_string_free(edn);
    return ok;
}

int main(void) {
    const char *path = "tmp.vev.durable-tx-fn-report-smoke.sqlite";
    remove(path);
    remove("tmp.vev.durable-tx-fn-report-smoke.sqlite-wal");
    remove("tmp.vev.durable-tx-fn-report-smoke.sqlite-shm");

    int ok = 0;
    vev_connection_t conn = vev_connect(path);
    vev_db_t db = NULL;
    vev_tx_report_t report = NULL;
    vev_tx_report_array_t reports = NULL;
    vev_tx_fn_registry_t tx_fns = NULL;
    vev_tx_builder_t builder = NULL;
    vev_tx_builder_t builder_a = NULL;
    vev_tx_builder_t builder_b = NULL;

    if (conn == NULL || !vev_connection_ok(conn)) {
        const char *error = vev_connection_error(conn);
        fprintf(stderr, "connect: %s\n", error);
        vev_string_free(error);
        goto cleanup;
    }

    report = vev_connection_transact_edn_report(
        conn,
        "[[:db/add 1 :user/name \"Ada\"]"
        " [:db/add 120 :db/ident :mark-seen]"
        " [:db/add 121 :db/ident :user/seen-label]]");
    if (!report_ok("setup", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;

    builder = vev_tx_create(2);
    if (builder == NULL ||
        !vev_tx_add_string(builder, 2, ":user/name", "Katherine") ||
        !vev_tx_add_string(builder, 2, ":user/email", "katherine@example.com")) {
        fprintf(stderr, "typed builder setup failed\n");
        goto cleanup;
    }
    report = vev_connection_tx_commit_report(conn, builder);
    if (!report_ok("typed builder", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    vev_tx_free(builder);
    builder = NULL;

    builder_a = vev_tx_create(1);
    builder_b = vev_tx_create(1);
    if (builder_a == NULL ||
        builder_b == NULL ||
        !vev_tx_add_string(builder_a, 3, ":user/name", "Hedy") ||
        !vev_tx_add_string(builder_b, 4, ":user/name", "Dorothy")) {
        fprintf(stderr, "bulk builder setup failed\n");
        goto cleanup;
    }
    vev_tx_builder_t bulk_builders[] = {builder_a, builder_b};
    report = vev_connection_tx_commit_many_report(conn, bulk_builders, 2);
    if (!report_ok("bulk builder", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    vev_tx_free(builder_a);
    builder_a = NULL;
    vev_tx_free(builder_b);
    builder_b = NULL;

    builder_a = vev_tx_create(1);
    builder_b = vev_tx_create(1);
    if (builder_a == NULL ||
        builder_b == NULL ||
        !vev_tx_add_string(builder_a, 2, ":user/name", "Grace") ||
        !vev_tx_add_string(builder_b, 3, ":user/name", "Barbara")) {
        fprintf(stderr, "builder setup failed\n");
        goto cleanup;
    }
    vev_tx_builder_t builders[] = {builder_a, builder_b};
    reports = vev_connection_tx_commit_logical_many_reports(conn, builders, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 2 ||
        !report_ok("builder logical 0", vev_tx_report_array_get(reports, 0)) ||
        !report_ok("builder logical 1", vev_tx_report_array_get(reports, 1))) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    vev_tx_free(builder_a);
    builder_a = NULL;
    vev_tx_free(builder_b);
    builder_b = NULL;

    reports = vev_connection_tx_commit_logical_many_reports(conn, NULL, 1);
    if (reports == NULL || vev_tx_report_array_count(reports) != 1) {
        fprintf(stderr, "expected failed builder logical report\n");
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;

    const char *texts[] = {
        "[{:db/id 4 :user/name \"Katherine\"}]",
        "[{:db/id 5 :user/name \"Hedy\"}]",
    };
    reports = vev_connection_transact_many_edn_reports(conn, texts, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 2 ||
        !report_ok("edn logical 0", vev_tx_report_array_get(reports, 0)) ||
        !report_ok("edn logical 1", vev_tx_report_array_get(reports, 1))) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;

    const char *bad_texts[] = {
        "[{:db/id 6 :user/name \"Should Not Commit\"}]",
        "[{:db/id 7 :user/name",
    };
    reports = vev_connection_transact_many_edn_reports(conn, bad_texts, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 1) {
        fprintf(stderr, "expected failed EDN logical report\n");
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;

    tx_fns = vev_tx_fn_registry_create();
    if (tx_fns == NULL ||
        !vev_tx_fn_registry_register_edn(tx_fns, ":mark-seen", mark_seen_tx_fn, NULL)) {
        fprintf(stderr, "register tx fn failed\n");
        goto cleanup;
    }

    db = vev_connection_db(conn);
    report = vev_with_edn_report_with_tx_fns(
        db,
        "[[:db.fn/call :mark-seen 1 \"from-with\"]]",
        tx_fns);
    if (!report_ok("with", report) || !print_report_contains("with", report, "from-with")) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    vev_db_release(db);
    db = NULL;

    report = vev_connection_transact_edn_report_with_tx_fns(
        conn,
        "[[:db.fn/call :mark-seen 1 \"from-transact\"]]",
        tx_fns);
    if (!report_ok("transact", report) || !print_report_contains("transact", report, "from-transact")) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;

    ok = 1;

cleanup:
    if (report != NULL) {
        vev_tx_report_free(report);
    }
    if (reports != NULL) {
        vev_tx_report_array_free(reports);
    }
    if (db != NULL) {
        vev_db_release(db);
    }
    if (builder != NULL) {
        vev_tx_free(builder);
    }
    if (builder_a != NULL) {
        vev_tx_free(builder_a);
    }
    if (builder_b != NULL) {
        vev_tx_free(builder_b);
    }
    if (tx_fns != NULL) {
        vev_tx_fn_registry_free(tx_fns);
    }
    if (conn != NULL) {
        vev_connection_close(conn);
    }
    return ok ? 0 : 1;
}
