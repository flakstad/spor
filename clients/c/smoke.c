// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#include <stdio.h>
#include <string.h>
#include "vev.h"

static void print_and_free(const char *label, const char *text) {
    printf("%s: %s\n", label, text);
    vev_string_free(text);
}

static void print_result_rows(vev_result_t result) {
    if (!vev_result_ok(result)) {
        const char *error = vev_result_error(result);
        fprintf(stderr, "result error: %s\n", error);
        vev_string_free(error);
        return;
    }

    int rows = vev_result_row_count(result);
    printf("result-handle rows: %d\n", rows);
    for (int row = 0; row < rows; row++) {
        int values = vev_result_value_count(result, row);
        printf("  row %d:", row);
        for (int column = 0; column < values; column++) {
            int kind = vev_result_value_kind(result, row, column);
            if (kind == VEV_VALUE_ENTITY) {
                printf(" entity=%llu", vev_result_value_entity(result, row, column));
            } else if (kind == VEV_VALUE_STRING) {
                const char *text = vev_result_value_text(result, row, column);
                printf(" string=%s", text);
                vev_string_free(text);
            } else {
                const char *text = vev_result_value_edn(result, row, column);
                printf(" value=%s", text);
                vev_string_free(text);
            }
        }
        printf("\n");
    }
}

static int result_row_count_or_error(const char *label, vev_result_t result) {
    if (result == NULL) {
        fprintf(stderr, "%s: null result\n", label);
        return -1;
    }
    if (!vev_result_ok(result)) {
        const char *error = vev_result_error(result);
        fprintf(stderr, "%s: %s\n", label, error);
        vev_string_free(error);
        return -1;
    }
    return vev_result_row_count(result);
}

static vev_value_t map_get(vev_value_t map, const char *key) {
    return vev_value_map_get(map, key);
}

static int value_text_equals(vev_value_t value, const char *expected) {
    return vev_value_text_equals(value, expected);
}

static int bytes_equal(const void *data, int len, const char *expected) {
    int expected_len = (int)strlen(expected);
    return len == expected_len && memcmp(data, expected, (size_t)len) == 0;
}

static int expect_u64_array(const char *label, vev_u64_array_t array, const unsigned long long *expected, int expected_count) {
    if (array == NULL) {
        fprintf(stderr, "%s: null array\n", label);
        return 0;
    }
    int count = vev_u64_array_count(array);
    if (count != expected_count) {
        fprintf(stderr, "%s: expected %d values, got %d\n", label, expected_count, count);
        return 0;
    }
    for (int i = 0; i < expected_count; i++) {
        unsigned long long value = vev_u64_array_value(array, i);
        if (value != expected[i]) {
            fprintf(stderr, "%s: expected value[%d]=%llu, got %llu\n", label, i, expected[i], value);
            return 0;
        }
    }
    return 1;
}

struct value_visit_stats {
    int values;
    int ends;
    int depth;
    int max_depth;
};

static bool count_value_visit(void *user, int event, vev_value_t value) {
    struct value_visit_stats *stats = (struct value_visit_stats *)user;
    if (event == VEV_VALUE_VISIT_VALUE) {
        stats->values++;
        int kind = vev_value_kind(value);
        if (kind == VEV_VALUE_VECTOR || kind == VEV_VALUE_MAP) {
            stats->depth++;
            if (stats->depth > stats->max_depth) {
                stats->max_depth = stats->depth;
            }
        }
    } else if (event == VEV_VALUE_VISIT_END) {
        stats->ends++;
        stats->depth--;
    }
    return true;
}

struct result_visit_stats {
    int row_begins;
    int row_ends;
    int values;
    int pulls;
};

static bool count_result_visit(void *user, int event, int row, int index, vev_value_t value) {
    (void)row;
    (void)index;
    struct result_visit_stats *stats = (struct result_visit_stats *)user;
    if (event == VEV_RESULT_VISIT_ROW_BEGIN) {
        stats->row_begins++;
    } else if (event == VEV_RESULT_VISIT_ROW_END) {
        stats->row_ends++;
    } else if (event == VEV_RESULT_VISIT_VALUE) {
        if (value == NULL) {
            return false;
        }
        stats->values++;
    } else if (event == VEV_RESULT_VISIT_PULL) {
        if (value == NULL) {
            return false;
        }
        stats->pulls++;
    }
    return true;
}

static bool cancel_result_visit(void *user, int event, int row, int index, vev_value_t value) {
    (void)user;
    (void)event;
    (void)row;
    (void)index;
    (void)value;
    return false;
}

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
    snprintf(
        out,
        sizeof(out),
        "[[:db/add %lld :user/seen-label \"%s\"]]",
        vev_value_int(entity),
        label_text);
    vev_string_free(label_text);
    return out;
}

static int tx_report_ok_or_error(const char *label, vev_tx_report_t report) {
    if (report == NULL) {
        fprintf(stderr, "%s: null transaction report\n", label);
        return 0;
    }
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t ok = map_get(value, ":ok");
    if (vev_value_kind(ok) == VEV_VALUE_BOOL && vev_value_bool(ok)) {
        return 1;
    }
    const char *edn = vev_tx_report_edn(report);
    fprintf(stderr, "%s: transaction failed: %s\n", label, edn);
    vev_string_free(edn);
    return 0;
}

static int tx_report_failed_contains(const char *label, vev_tx_report_t report, const char *needle) {
    if (report == NULL) {
        fprintf(stderr, "%s: null transaction report\n", label);
        return 0;
    }
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t ok = map_get(value, ":ok");
    if (vev_value_kind(ok) != VEV_VALUE_BOOL || vev_value_bool(ok)) {
        const char *edn = vev_tx_report_edn(report);
        fprintf(stderr, "%s: expected failed transaction report, got: %s\n", label, edn);
        vev_string_free(edn);
        return 0;
    }
    const char *edn = vev_tx_report_edn(report);
    int contains = edn != NULL && strstr(edn, needle) != NULL;
    if (!contains) {
        fprintf(stderr, "%s: expected failure containing '%s', got: %s\n", label, needle, edn);
    }
    vev_string_free(edn);
    return contains;
}

static int tx_report_first_tx_value_is_int_vector(const char *label, vev_tx_report_t report, long long first, long long second) {
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t tx_data = map_get(value, ":tx-data");
    if (vev_value_kind(tx_data) != VEV_VALUE_VECTOR || vev_value_item_count(tx_data) < 1) {
        fprintf(stderr, "%s: expected non-empty :tx-data vector\n", label);
        return 0;
    }
    vev_value_t first_datom = vev_value_item(tx_data, 0);
    vev_value_t datom_value = map_get(first_datom, ":v");
    if (vev_value_kind(datom_value) != VEV_VALUE_VECTOR || vev_value_item_count(datom_value) != 2) {
        const char *edn = vev_value_edn(datom_value);
        fprintf(stderr, "%s: expected vector tx value, got %s\n", label, edn);
        vev_string_free(edn);
        return 0;
    }
    vev_value_t a = vev_value_item(datom_value, 0);
    vev_value_t b = vev_value_item(datom_value, 1);
    if (vev_value_kind(a) != VEV_VALUE_INT || vev_value_kind(b) != VEV_VALUE_INT ||
        vev_value_int(a) != first || vev_value_int(b) != second) {
        const char *edn = vev_value_edn(datom_value);
        fprintf(stderr, "%s: unexpected vector tx value %s\n", label, edn);
        vev_string_free(edn);
        return 0;
    }
    return 1;
}

struct tx_listener_stats {
    int count;
    int saw_listener_attr;
};

static void count_tx_listener(void *user, vev_tx_report_t report) {
    struct tx_listener_stats *stats = (struct tx_listener_stats *)user;
    stats->count++;
    vev_value_t value = vev_tx_report_value(report);
    vev_value_t ok = map_get(value, ":ok");
    if (vev_value_kind(ok) != VEV_VALUE_BOOL || !vev_value_bool(ok)) {
        return;
    }
    const char *edn = vev_tx_report_edn(report);
    if (edn != NULL && strstr(edn, ":user/listener") != NULL) {
        stats->saw_listener_attr = 1;
    }
    vev_string_free(edn);
}

static int run_sqlite_smoke(vev_prepared_query_t all_emails) {
    const char *path = "tmp.vev.c-abi.sqlite";
    remove(path);
    remove("tmp.vev.c-abi.sqlite-wal");
    remove("tmp.vev.c-abi.sqlite-shm");

    int ok = 0;
    vev_connection_t durable = NULL;
    vev_db_t db = NULL;
    vev_result_t result = NULL;
    vev_tx_report_t report = NULL;
    vev_tx_report_array_t reports = NULL;
    vev_tx_fn_registry_t tx_fns = NULL;
    vev_tx_builder_t builder = NULL;
    vev_tx_builder_t bulk_a = NULL;
    vev_tx_builder_t bulk_b = NULL;
    vev_u64_array_t tx_ids = NULL;
    unsigned long long first_basis = 0;
    vev_prepared_query_t source_column_query = NULL;
    vev_column_batch_t source_column_batch = NULL;
    vev_string_array_t source_string_column = NULL;

    durable = vev_connect(path);
    if (durable == NULL || !vev_connection_ok(durable)) {
        const char *error = vev_connection_error(durable);
        fprintf(stderr, "failed to open sqlite Vev connection: %s\n", error);
        vev_string_free(error);
        goto cleanup;
    }
    const char *backend = vev_connection_backend(durable);
    const char *durable_path = vev_connection_path(durable);
    if (strcmp(backend, "sqlite") != 0 || strcmp(durable_path, path) != 0) {
        fprintf(stderr, "unexpected durable connection metadata: backend=%s path=%s\n", backend, durable_path);
        vev_string_free(backend);
        vev_string_free(durable_path);
        goto cleanup;
    }
    vev_string_free(backend);
    vev_string_free(durable_path);
    if (vev_connection_basis_t(durable) != 0) {
        fprintf(stderr, "unexpected initial durable basis\n");
        goto cleanup;
    }
    if (vev_connection_tx_count(durable) != 0) {
        fprintf(stderr, "unexpected initial durable tx count\n");
        goto cleanup;
    }
    tx_ids = vev_connection_tx_ids(durable);
    if (!expect_u64_array("initial-tx-ids", tx_ids, NULL, 0)) {
        goto cleanup;
    }
    vev_u64_array_free(tx_ids);
    tx_ids = NULL;
    const char *info = vev_connection_info_edn(durable);
    if (strstr(info, ":backend :sqlite") == NULL ||
        strstr(info, ":basis-t 0") == NULL ||
        strstr(info, ":tx-count 0") == NULL ||
        strstr(info, path) == NULL) {
        fprintf(stderr, "unexpected durable connection info: %s\n", info);
        vev_string_free(info);
        goto cleanup;
    }
    vev_string_free(info);

    report = vev_connection_transact_edn_report(
        durable,
        "[{:db/id 1 :user/name \"Durable Ada\" :user/email \"durable-ada@example.com\"}]");
    print_and_free("sqlite-tx", vev_tx_report_edn(report));
    if (!tx_report_ok_or_error("sqlite-tx", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    first_basis = vev_connection_basis_t(durable);
    if (first_basis == 0) {
        fprintf(stderr, "unexpected durable basis after first tx\n");
        goto cleanup;
    }
    if (vev_connection_tx_count(durable) != 1) {
        fprintf(stderr, "unexpected durable tx count after first tx\n");
        goto cleanup;
    }
    unsigned long long first_tx_ids[] = {first_basis};
    tx_ids = vev_connection_tx_ids(durable);
    if (!expect_u64_array("first-tx-ids", tx_ids, first_tx_ids, 1)) {
        goto cleanup;
    }
    vev_u64_array_free(tx_ids);
    tx_ids = NULL;

    db = vev_connection_db(durable);
    result = vev_query_db_prepared_result_with_inputs(db, all_emails, "[]");
    int live_rows = result_row_count_or_error("sqlite-live", result);
    printf("sqlite-live rows: %d\n", live_rows);
    if (live_rows != 1) {
        fprintf(stderr, "unexpected sqlite live row count\n");
        goto cleanup;
    }
    vev_result_free(result);
    result = NULL;
    vev_db_release(db);
    db = NULL;
    vev_connection_close(durable);
    durable = NULL;

    durable = vev_connect(path);
    if (durable == NULL || !vev_connection_ok(durable)) {
        const char *error = vev_connection_error(durable);
        fprintf(stderr, "failed to reopen sqlite Vev connection: %s\n", error);
        vev_string_free(error);
        goto cleanup;
    }
    if (vev_connection_basis_t(durable) != first_basis) {
        fprintf(stderr, "unexpected reopened durable basis\n");
        goto cleanup;
    }
    if (vev_connection_tx_count(durable) != 1) {
        fprintf(stderr, "unexpected reopened durable tx count\n");
        goto cleanup;
    }
    tx_ids = vev_connection_tx_ids(durable);
    if (!expect_u64_array("reopened-tx-ids", tx_ids, first_tx_ids, 1)) {
        goto cleanup;
    }
    vev_u64_array_free(tx_ids);
    tx_ids = NULL;
    db = vev_connection_db(durable);
    result = vev_query_db_prepared_result_with_inputs(db, all_emails, "[]");
    int reopened_rows = result_row_count_or_error("sqlite-reopened", result);
    printf("sqlite-reopened rows: %d\n", reopened_rows);
    if (reopened_rows != 1) {
        fprintf(stderr, "unexpected sqlite reopened row count\n");
        goto cleanup;
    }
    vev_result_free(result);
    result = NULL;
    vev_db_release(db);
    db = NULL;

    struct tx_listener_stats durable_listener_stats = {0, 0};
    if (!vev_connection_listen_tx_report(durable, "durable-listener", count_tx_listener, &durable_listener_stats)) {
        fprintf(stderr, "failed to register durable tx report listener\n");
        goto cleanup;
    }
    report = vev_connection_transact_edn_report(
        durable,
        "[[:db/add 1 :user/listener \"durable-heard\"]]");
    if (!tx_report_ok_or_error("sqlite-listener-tx", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    if (durable_listener_stats.count != 1 || !durable_listener_stats.saw_listener_attr) {
        fprintf(stderr, "durable tx report listener did not observe successful transaction\n");
        goto cleanup;
    }
    report = vev_connection_transact_edn_report(durable, "[[:db/add 1 123 \"bad\"]]");
    vev_tx_report_free(report);
    report = NULL;
    if (durable_listener_stats.count != 1) {
        fprintf(stderr, "durable tx report listener observed failed transaction\n");
        goto cleanup;
    }
    if (!vev_connection_unlisten_tx_report(durable, "durable-listener")) {
        fprintf(stderr, "failed to unregister durable tx report listener\n");
        goto cleanup;
    }
    report = vev_connection_transact_edn_report(
        durable,
        "[[:db/add 1 :user/listener \"durable-after-unlisten\"]]");
    if (!tx_report_ok_or_error("sqlite-listener-after-unlisten", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    if (durable_listener_stats.count != 1) {
        fprintf(stderr, "durable tx report listener observed transaction after unlisten\n");
        goto cleanup;
    }

    report = vev_connection_transact_edn_report(
        durable,
        "[{:db/id 2 :user/name \"Durable Grace\" :user/email \"durable-grace@example.com\"}]");
    if (!tx_report_ok_or_error("sqlite-second-tx", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 3) {
        fprintf(stderr, "unexpected durable basis after second tx\n");
        goto cleanup;
    }
    if (vev_connection_tx_count(durable) != 4) {
        fprintf(stderr, "unexpected durable tx count after second tx\n");
        goto cleanup;
    }
    unsigned long long four_tx_ids[] = {first_basis, first_basis + 1, first_basis + 2, first_basis + 3};
    tx_ids = vev_connection_tx_ids(durable);
    if (!expect_u64_array("second-tx-ids", tx_ids, four_tx_ids, 4)) {
        goto cleanup;
    }
    vev_u64_array_free(tx_ids);
    tx_ids = NULL;
    vev_connection_close(durable);
    durable = NULL;

    durable = vev_connect(path);
    if (durable == NULL || !vev_connection_ok(durable)) {
        const char *error = vev_connection_error(durable);
        fprintf(stderr, "failed to reopen sqlite Vev connection after second tx: %s\n", error);
        vev_string_free(error);
        goto cleanup;
    }
    if (vev_connection_basis_t(durable) != first_basis + 3) {
        fprintf(stderr, "unexpected final reopened durable basis\n");
        goto cleanup;
    }
    if (vev_connection_tx_count(durable) != 4) {
        fprintf(stderr, "unexpected final reopened durable tx count\n");
        goto cleanup;
    }
    tx_ids = vev_connection_tx_ids(durable);
    if (!expect_u64_array("final-tx-ids", tx_ids, four_tx_ids, 4)) {
        goto cleanup;
    }
    vev_u64_array_free(tx_ids);
    tx_ids = NULL;
    db = vev_connection_db(durable);
    result = vev_query_db_prepared_result_with_inputs(db, all_emails, "[]");
    int final_rows = result_row_count_or_error("sqlite-final", result);
    printf("sqlite-final rows: %d\n", final_rows);
    if (final_rows != 2) {
        fprintf(stderr, "unexpected sqlite final row count\n");
        goto cleanup;
    }

    source_column_query =
        vev_prepare_query_edn(
            "[:find ?email"
            " :where [?e :user/name ?name]"
            "        [?e :user/email ?email]"
            "        [(= ?name \"Durable Ada\")]]");
    if (source_column_query == NULL) {
        fprintf(stderr, "failed to prepare sqlite source column batch query\n");
        goto cleanup;
    }
    source_column_batch =
        vev_query_db_prepared_column_batch_with_inputs(db, source_column_query, "[]");
    if (source_column_batch == NULL ||
        vev_column_batch_kind(source_column_batch) != VEV_COLUMN_BATCH_STRING ||
        vev_column_batch_count(source_column_batch) != 1) {
        fprintf(stderr, "unexpected sqlite source column batch shape\n");
        goto cleanup;
    }
    const void *const *source_column_strings =
        vev_column_batch_string_data_array(source_column_batch);
    const int *source_column_lengths =
        vev_column_batch_string_lengths_data(source_column_batch);
    if (!bytes_equal(source_column_strings[0], source_column_lengths[0], "durable-ada@example.com")) {
        fprintf(stderr, "unexpected sqlite source column batch contents\n");
        goto cleanup;
    }
    printf("sqlite-source column-batch kind=%d rows=%d\n",
           vev_column_batch_kind(source_column_batch),
           vev_column_batch_count(source_column_batch));
    vev_column_batch_free(source_column_batch);
    source_column_batch = NULL;

    source_string_column =
        vev_query_db_prepared_string_column_with_inputs(db, source_column_query, "[]");
    if (source_string_column == NULL ||
        vev_string_array_count(source_string_column) != 1) {
        fprintf(stderr, "unexpected sqlite source string column shape\n");
        goto cleanup;
    }
    const void *const *source_string_data =
        vev_string_array_data_array(source_string_column);
    const int *source_string_lengths =
        vev_string_array_lengths_data(source_string_column);
    if (!bytes_equal(source_string_data[0], source_string_lengths[0], "durable-ada@example.com")) {
        fprintf(stderr, "unexpected sqlite source string column contents\n");
        goto cleanup;
    }
    vev_string_array_free(source_string_column);
    source_string_column = NULL;

    vev_prepared_query_free(source_column_query);
    source_column_query = NULL;

    vev_result_free(result);
    result = NULL;
    vev_db_release(db);
    db = NULL;

    builder = vev_tx_create(2);
    if (builder == NULL ||
        !vev_tx_add_string(builder, 3, ":user/name", "Durable Katherine") ||
        !vev_tx_add_string(builder, 3, ":user/email", "durable-katherine@example.com")) {
        fprintf(stderr, "failed to build durable typed transaction\n");
        goto cleanup;
    }
    report = vev_connection_tx_commit_report(durable, builder);
    if (!tx_report_ok_or_error("sqlite-typed-builder-tx", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    vev_tx_free(builder);
    builder = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 4) {
        fprintf(stderr, "unexpected durable basis after typed builder tx\n");
        goto cleanup;
    }
    if (!vev_connection_compact_indexes(durable)) {
        fprintf(stderr, "failed to compact durable indexes\n");
        goto cleanup;
    }
    db = vev_connection_db(durable);
    result = vev_query_db_prepared_result_with_inputs(db, all_emails, "[]");
    int typed_rows = result_row_count_or_error("sqlite-typed-builder", result);
    printf("sqlite-typed-builder rows: %d\n", typed_rows);
    if (typed_rows != 3) {
        fprintf(stderr, "unexpected sqlite typed builder row count\n");
        goto cleanup;
    }
    vev_result_free(result);
    result = NULL;
    vev_db_release(db);
    db = NULL;

    bulk_a = vev_tx_create(1);
    bulk_b = vev_tx_create(1);
    if (bulk_a == NULL ||
        bulk_b == NULL ||
        !vev_tx_add_string(bulk_a, 4, ":user/name", "Durable Hedy") ||
        !vev_tx_add_string(bulk_b, 5, ":user/name", "Durable Dorothy")) {
        fprintf(stderr, "failed to build durable bulk typed transaction\n");
        goto cleanup;
    }
    vev_tx_builder_t bulk_builders[] = {bulk_a, bulk_b};
    report = vev_connection_tx_commit_many_report(durable, bulk_builders, 2);
    if (!tx_report_ok_or_error("sqlite-typed-builder-bulk-tx", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;
    vev_tx_free(bulk_a);
    bulk_a = NULL;
    vev_tx_free(bulk_b);
    bulk_b = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 5) {
        fprintf(stderr, "unexpected durable basis after bulk typed builder tx\n");
        goto cleanup;
    }
    db = vev_connection_db(durable);
    result = vev_query_db_prepared_result_with_inputs(db, all_emails, "[]");
    int bulk_rows = result_row_count_or_error("sqlite-typed-builder-bulk", result);
    printf("sqlite-typed-builder-bulk rows: %d\n", bulk_rows);
    if (bulk_rows != 3) {
        fprintf(stderr, "unexpected sqlite typed builder bulk email row count\n");
        goto cleanup;
    }
    vev_result_free(result);
    result = NULL;
    vev_db_release(db);
    db = NULL;

    bulk_a = vev_tx_create(1);
    bulk_b = vev_tx_create(1);
    if (bulk_a == NULL ||
        bulk_b == NULL ||
        !vev_tx_add_string(bulk_a, 6, ":user/name", "Durable Grace") ||
        !vev_tx_add_string(bulk_b, 7, ":user/name", "Durable Ada")) {
        fprintf(stderr, "failed to build durable logical group transaction\n");
        goto cleanup;
    }
    vev_tx_builder_t logical_builders[] = {bulk_a, bulk_b};
    reports = vev_connection_tx_commit_logical_many_reports(durable, logical_builders, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 2) {
        fprintf(stderr, "unexpected logical group commit report count\n");
        goto cleanup;
    }
    if (!tx_report_ok_or_error("sqlite-typed-builder-logical-group-tx-0", vev_tx_report_array_get(reports, 0)) ||
        !tx_report_ok_or_error("sqlite-typed-builder-logical-group-tx-1", vev_tx_report_array_get(reports, 1))) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    vev_tx_free(bulk_a);
    bulk_a = NULL;
    vev_tx_free(bulk_b);
    bulk_b = NULL;
    reports = vev_connection_tx_commit_logical_many_reports(durable, NULL, 0);
    if (reports == NULL || vev_tx_report_array_count(reports) != 0) {
        fprintf(stderr, "expected empty logical group report array for empty builders\n");
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    reports = vev_connection_tx_commit_logical_many_reports(durable, NULL, 1);
    if (reports == NULL || vev_tx_report_array_count(reports) != 1) {
        fprintf(stderr, "expected failed logical group report array for null builder array\n");
        goto cleanup;
    }
    if (!tx_report_failed_contains(
            "sqlite-typed-builder-logical-group-null-builders",
            vev_tx_report_array_get(reports, 0),
            "null")) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    vev_tx_builder_t malformed_logical_builders[] = {NULL};
    reports = vev_connection_tx_commit_logical_many_reports(durable, malformed_logical_builders, 1);
    if (reports == NULL || vev_tx_report_array_count(reports) != 1) {
        fprintf(stderr, "expected failed logical group report array for malformed builders\n");
        goto cleanup;
    }
    if (!tx_report_failed_contains(
            "sqlite-typed-builder-logical-group-malformed",
            vev_tx_report_array_get(reports, 0),
            "null builder")) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 7) {
        fprintf(stderr, "unexpected durable basis after logical group commit\n");
        goto cleanup;
    }

    const char *logical_texts[] = {
        "[{:db/id 8 :user/name \"Durable Katherine\"}]",
        "[{:db/id 9 :user/name \"Durable Hedy\"}]",
    };
    reports = vev_connection_transact_many_edn_reports(durable, logical_texts, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 2) {
        fprintf(stderr, "unexpected EDN logical group report count\n");
        goto cleanup;
    }
    if (!tx_report_ok_or_error("sqlite-edn-logical-group-tx-0", vev_tx_report_array_get(reports, 0)) ||
        !tx_report_ok_or_error("sqlite-edn-logical-group-tx-1", vev_tx_report_array_get(reports, 1))) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 9) {
        fprintf(stderr, "unexpected durable basis after EDN logical group commit\n");
        goto cleanup;
    }
    const char *malformed_logical_texts[] = {
        "[{:db/id 10 :user/name \"Should Not Commit\"}]",
        "[{:db/id 11 :user/name",
    };
    reports = vev_connection_transact_many_edn_reports(durable, malformed_logical_texts, 2);
    if (reports == NULL || vev_tx_report_array_count(reports) != 1) {
        fprintf(stderr, "expected failed EDN logical group report array for malformed text\n");
        goto cleanup;
    }
    if (!tx_report_failed_contains(
            "sqlite-edn-logical-group-malformed",
            vev_tx_report_array_get(reports, 0),
            "transaction group 1")) {
        goto cleanup;
    }
    vev_tx_report_array_free(reports);
    reports = NULL;
    if (vev_connection_basis_t(durable) != first_basis + 9) {
        fprintf(stderr, "malformed EDN logical group advanced durable basis\n");
        goto cleanup;
    }

    report = vev_connection_transact_edn_report(
        durable,
        "[[:db/add 120 :db/ident :mark-seen]"
        " [:db/add 121 :db/ident :user/seen-label]]");
    if (!tx_report_ok_or_error("sqlite-tx-fn-ident", report)) {
        goto cleanup;
    }
    vev_tx_report_free(report);
    report = NULL;

    tx_fns = vev_tx_fn_registry_create();
    if (tx_fns == NULL ||
        !vev_tx_fn_registry_register_edn(tx_fns, ":mark-seen", mark_seen_tx_fn, NULL)) {
        fprintf(stderr, "failed to register sqlite snapshot transaction callback\n");
        goto cleanup;
    }
    db = vev_connection_db(durable);
    report = vev_with_edn_report_with_tx_fns(
        db,
        "[[:db.fn/call :mark-seen 1 \"from-sqlite-with-c\"]]",
        tx_fns);
    const char *sqlite_tx_fn_edn = vev_tx_report_edn(report);
    printf("sqlite-with-tx-fn-callback: %s\n", sqlite_tx_fn_edn);
    if (!tx_report_ok_or_error("sqlite-with-tx-fn-callback", report) ||
        strstr(sqlite_tx_fn_edn, "from-sqlite-with-c") == NULL) {
        fprintf(stderr, "sqlite snapshot transaction callback did not apply returned tx-data\n");
        vev_string_free(sqlite_tx_fn_edn);
        goto cleanup;
    }
    vev_string_free(sqlite_tx_fn_edn);
    vev_tx_report_free(report);
    report = NULL;
    vev_db_release(db);
    db = NULL;

    report = vev_connection_transact_edn_report_with_tx_fns(
        durable,
        "[[:db.fn/call :mark-seen 2 \"from-sqlite-transact-c\"]]",
        tx_fns);
    sqlite_tx_fn_edn = vev_tx_report_edn(report);
    printf("sqlite-transact-tx-fn-callback: %s\n", sqlite_tx_fn_edn);
    if (!tx_report_ok_or_error("sqlite-transact-tx-fn-callback", report) ||
        strstr(sqlite_tx_fn_edn, "from-sqlite-transact-c") == NULL) {
        fprintf(stderr, "sqlite live transaction callback did not apply returned tx-data\n");
        vev_string_free(sqlite_tx_fn_edn);
        goto cleanup;
    }
    vev_string_free(sqlite_tx_fn_edn);
    vev_tx_report_free(report);
    report = NULL;

    vev_tx_fn_registry_free(tx_fns);
    tx_fns = NULL;

    ok = 1;

cleanup:
    if (report != NULL) {
        vev_tx_report_free(report);
    }
    if (reports != NULL) {
        vev_tx_report_array_free(reports);
    }
    if (tx_ids != NULL) {
        vev_u64_array_free(tx_ids);
    }
    if (tx_fns != NULL) {
        vev_tx_fn_registry_free(tx_fns);
    }
    if (builder != NULL) {
        vev_tx_free(builder);
    }
    if (bulk_a != NULL) {
        vev_tx_free(bulk_a);
    }
    if (bulk_b != NULL) {
        vev_tx_free(bulk_b);
    }
    if (source_column_batch != NULL) {
        vev_column_batch_free(source_column_batch);
    }
    if (source_string_column != NULL) {
        vev_string_array_free(source_string_column);
    }
    if (source_column_query != NULL) {
        vev_prepared_query_free(source_column_query);
    }
    if (result != NULL) {
        vev_result_free(result);
    }
    if (db != NULL) {
        vev_db_release(db);
    }
    if (durable != NULL) {
        vev_connection_close(durable);
    }
    remove(path);
    remove("tmp.vev.c-abi.sqlite-wal");
    remove("tmp.vev.c-abi.sqlite-shm");
    return ok;
}

int main(void) {
    printf("version: %s\n", vev_version());

    vev_conn_t conn = vev_conn_open_memory();
    if (conn == NULL) {
        fprintf(stderr, "failed to open Vev connection\n");
        return 1;
    }

    vev_tx_report_t tx_report = vev_transact_edn_report(
        conn,
        "[{:db/id 1 :user/name \"Ada\" :user/email \"ada@example.com\" :user/age 37 :user/active true :user/score 9.5}"
        " {:db/id 2 :user/name \"Grace\" :user/email \"grace@example.com\" :user/age 41 :user/active false :user/score 8.25}]");
    print_and_free("tx", vev_tx_report_edn(tx_report));
    if (!tx_report_ok_or_error("tx", tx_report)) {
        vev_tx_report_free(tx_report);
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_free(tx_report);

    vev_tx_report_t vector_tx_report =
        vev_transact_edn_report(conn, "[[:db/add 1 :user/tags [1 2]] [:db/add 1 :user/mixed 1] [:db/add 2 :user/mixed [2 3]]]");
    if (!tx_report_ok_or_error("vector-tx", vector_tx_report) ||
        !tx_report_first_tx_value_is_int_vector("vector-tx", vector_tx_report, 1, 2)) {
        vev_tx_report_free(vector_tx_report);
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_free(vector_tx_report);

    struct tx_listener_stats listener_stats = {0, 0};
    if (!vev_conn_listen_tx_report(conn, "smoke-listener", count_tx_listener, &listener_stats)) {
        fprintf(stderr, "failed to register tx report listener\n");
        vev_conn_close(conn);
        return 1;
    }
    print_and_free(
        "listener-tx",
        vev_transact_edn(conn, "[[:db/add 1 :user/listener \"heard\"]]"));
    if (listener_stats.count != 1 || !listener_stats.saw_listener_attr) {
        fprintf(stderr, "tx report listener did not observe successful transaction\n");
        vev_conn_close(conn);
        return 1;
    }
    print_and_free(
        "listener-failed-tx",
        vev_transact_edn(conn, "[[:db/add 1 123 \"bad\"]]"));
    if (listener_stats.count != 1) {
        fprintf(stderr, "tx report listener observed failed transaction\n");
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_conn_unlisten_tx_report(conn, "smoke-listener")) {
        fprintf(stderr, "failed to unregister tx report listener\n");
        vev_conn_close(conn);
        return 1;
    }
    print_and_free(
        "listener-after-unlisten",
        vev_transact_edn(conn, "[[:db/add 1 :user/listener \"after-unlisten\"]]"));
    if (listener_stats.count != 1) {
        fprintf(stderr, "tx report listener observed transaction after unlisten\n");
        vev_conn_close(conn);
        return 1;
    }

    print_and_free(
        "tx-email-unique",
        vev_transact_edn(
            conn,
            "[[:db/add 90 :db/ident :user/email]"
            " [:db/add 90 :db/unique :db.unique/identity]]"));

    print_and_free(
        "query",
        vev_query_edn(
            conn,
            "[:find ?e ?name :where [?e :user/name ?name]]"));

    print_and_free(
        "input-scalar",
        vev_query_edn_with_inputs(
            conn,
            "[:find ?name :in $ ?email :where [?e :user/email ?email] [?e :user/name ?name]]",
            "[\"ada@example.com\"]"));

    print_and_free(
        "input-collection",
        vev_query_edn_with_inputs(
            conn,
            "[:find ?name :in $ [?email ...] :where [?e :user/email ?email] [?e :user/name ?name]]",
            "[[\"ada@example.com\" \"grace@example.com\"]]"));

    print_and_free(
        "input-tuple",
        vev_query_edn_with_inputs(
            conn,
            "[:find ?e :in $ [?name ?email] :where [?e :user/name ?name] [?e :user/email ?email]]",
            "[[\"Ada\" \"ada@example.com\"]]"));

    print_and_free(
        "input-relation",
        vev_query_edn_with_inputs(
            conn,
            "[:find ?name :in $ [[?email ?label]] :where [?e :user/email ?email] [?e :user/name ?name]]",
            "[[[\"ada@example.com\" :primary] [\"missing@example.com\" :missing]]]"));

    print_and_free(
        "tx-ref-schema",
        vev_transact_edn(
            conn,
            "[[:db/add 100 :db/ident :user/friend]"
            " [:db/add 100 :db/valueType :db.type/ref]"
            " [:db/add 1 :user/friend 2]]"));

    print_and_free(
        "tx-fn-ident",
        vev_transact_edn(
            conn,
            "[[:db/add 120 :db/ident :mark-seen]"
            " [:db/add 121 :db/ident :user/seen-label]]"));
    vev_tx_fn_registry_t tx_fns = vev_tx_fn_registry_create();
    if (tx_fns == NULL ||
        !vev_tx_fn_registry_register_edn(tx_fns, ":mark-seen", mark_seen_tx_fn, NULL)) {
        fprintf(stderr, "failed to register transaction callback\n");
        if (tx_fns != NULL) {
            vev_tx_fn_registry_free(tx_fns);
        }
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_t tx_fn_report = vev_transact_edn_report_with_tx_fns(
        conn,
        "[[:db.fn/call :mark-seen 1 \"from-c\"]]",
        tx_fns);
    if (!tx_report_ok_or_error("tx-fn-callback", tx_fn_report)) {
        vev_tx_report_free(tx_fn_report);
        vev_tx_fn_registry_free(tx_fns);
        vev_conn_close(conn);
        return 1;
    }
    vev_tx_report_free(tx_fn_report);
    const char *tx_fn_check = vev_query_edn(
        conn,
        "[:find ?label :where [1 :user/seen-label ?label]]");
    printf("tx-fn-callback-check: %s\n", tx_fn_check);
    if (strstr(tx_fn_check, "from-c") == NULL) {
        fprintf(stderr, "transaction callback did not apply returned tx-data\n");
        vev_string_free(tx_fn_check);
        vev_tx_fn_registry_free(tx_fns);
        vev_conn_close(conn);
        return 1;
    }
    vev_string_free(tx_fn_check);
    vev_tx_fn_registry_free(tx_fns);

    vev_prepared_query_t query =
        vev_prepare_query_edn("[:find ?e ?email :in $ ?needle :where [?e :user/email ?email] [(= ?email ?needle)]]");
    if (query == NULL) {
        fprintf(stderr, "failed to prepare query\n");
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_prepared_query_ok(query)) {
        const char *error = vev_prepared_query_error(query);
        fprintf(stderr, "unexpected prepared query error: %s\n", error);
        vev_string_free(error);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *prepared_ast = vev_prepared_query_edn(query);
    if (prepared_ast == NULL ||
        strstr(prepared_ast, ":clauses") == NULL ||
        strstr(prepared_ast, ":input-specs") == NULL) {
        fprintf(stderr, "prepared query AST did not expose expected parser keys: %s\n",
                prepared_ast == NULL ? "<null>" : prepared_ast);
        vev_string_free(prepared_ast);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_string_free(prepared_ast);
    vev_prepared_query_t invalid_query = vev_prepare_query_edn("[:find ?e :where [?e");
    if (invalid_query == NULL || vev_prepared_query_ok(invalid_query)) {
        fprintf(stderr, "invalid prepared query unexpectedly succeeded\n");
        if (invalid_query != NULL) {
            vev_prepared_query_free(invalid_query);
        }
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *invalid_error = vev_prepared_query_error(invalid_query);
    if (invalid_error == NULL || strlen(invalid_error) == 0) {
        fprintf(stderr, "invalid prepared query did not expose an error\n");
        vev_string_free(invalid_error);
        vev_prepared_query_free(invalid_query);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_string_free(invalid_error);
    vev_prepared_query_free(invalid_query);

    print_and_free("prepared", vev_query_prepared_with_inputs(conn, query, "[\"grace@example.com\"]"));

    vev_result_t result = vev_query_prepared_result_with_inputs(conn, query, "[\"grace@example.com\"]");
    if (result == NULL) {
        fprintf(stderr, "failed to query typed result handle\n");
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    print_result_rows(result);
    struct result_visit_stats result_stats = {0, 0, 0, 0};
    if (!vev_result_visit(result, count_result_visit, &result_stats) ||
        result_stats.row_begins != 1 ||
        result_stats.row_ends != 1 ||
        result_stats.values != 2 ||
        result_stats.pulls != 0) {
        fprintf(
            stderr,
            "unexpected result visitor stats: rows=%d/%d values=%d pulls=%d\n",
            result_stats.row_begins,
            result_stats.row_ends,
            result_stats.values,
            result_stats.pulls);
        vev_result_free(result);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_free(result);

    vev_db_t batch_db = vev_conn_db(conn);
    if (batch_db == NULL) {
        fprintf(stderr, "failed to retain DB for column batch API\n");
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_prepared_query_t batch_query =
        vev_prepare_query_edn("[:find ?name :where [?e :user/name ?name]]");
    if (batch_query == NULL || !vev_prepared_query_ok(batch_query)) {
        fprintf(stderr, "failed to prepare column batch query\n");
        if (batch_query != NULL) {
            vev_prepared_query_free(batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, batch_query, "[]");
    if (batch == NULL ||
        vev_column_batch_kind(batch) != VEV_COLUMN_BATCH_STRING ||
        vev_column_batch_count(batch) != 2) {
        fprintf(stderr, "unexpected column batch shape\n");
        if (batch != NULL) {
            vev_column_batch_free(batch);
        }
        vev_prepared_query_free(batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const void *const *batch_strings = vev_column_batch_string_data_array(batch);
    const int *batch_lengths = vev_column_batch_string_lengths_data(batch);
    int saw_ada = 0;
    int saw_grace = 0;
    for (int i = 0; i < vev_column_batch_count(batch); i++) {
        if (bytes_equal(batch_strings[i], batch_lengths[i], "Ada")) {
            saw_ada = 1;
        } else if (bytes_equal(batch_strings[i], batch_lengths[i], "Grace")) {
            saw_grace = 1;
        }
    }
    if (!saw_ada || !saw_grace) {
        fprintf(stderr, "unexpected column batch string contents\n");
        vev_column_batch_free(batch);
        vev_prepared_query_free(batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("column-batch kind=%d rows=%d\n", vev_column_batch_kind(batch), vev_column_batch_count(batch));
    vev_column_batch_free(batch);
    vev_prepared_query_free(batch_query);

    vev_prepared_query_t pair_batch_query =
        vev_prepare_query_edn("[:find ?e ?name :where [?e :user/name ?name]]");
    if (pair_batch_query == NULL || !vev_prepared_query_ok(pair_batch_query)) {
        fprintf(stderr, "failed to prepare entity+string column batch query\n");
        if (pair_batch_query != NULL) {
            vev_prepared_query_free(pair_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t pair_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, pair_batch_query, "[]");
    if (pair_batch == NULL ||
        vev_column_batch_kind(pair_batch) != VEV_COLUMN_BATCH_ENTITY_STRING ||
        vev_column_batch_count(pair_batch) != 2) {
        fprintf(stderr, "unexpected entity+string column batch shape\n");
        if (pair_batch != NULL) {
            vev_column_batch_free(pair_batch);
        }
        vev_prepared_query_free(pair_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const unsigned long long *pair_batch_entities = vev_column_batch_entities_data(pair_batch);
    const void *const *pair_batch_strings = vev_column_batch_string_data_array(pair_batch);
    const int *pair_batch_lengths = vev_column_batch_string_lengths_data(pair_batch);
    int saw_entity_ada = 0;
    int saw_entity_grace = 0;
    for (int i = 0; i < vev_column_batch_count(pair_batch); i++) {
        if (pair_batch_entities[i] == 1 &&
            bytes_equal(pair_batch_strings[i], pair_batch_lengths[i], "Ada")) {
            saw_entity_ada = 1;
        } else if (pair_batch_entities[i] == 2 &&
                   bytes_equal(pair_batch_strings[i], pair_batch_lengths[i], "Grace")) {
            saw_entity_grace = 1;
        }
    }
    if (!saw_entity_ada || !saw_entity_grace) {
        fprintf(stderr, "unexpected entity+string column batch contents\n");
        vev_column_batch_free(pair_batch);
        vev_prepared_query_free(pair_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("entity+string column-batch kind=%d rows=%d\n", vev_column_batch_kind(pair_batch), vev_column_batch_count(pair_batch));
    vev_column_batch_free(pair_batch);
    vev_prepared_query_free(pair_batch_query);

    vev_prepared_query_t string_int_batch_query =
        vev_prepare_query_edn("[:find ?name ?age :where [?e :user/name ?name] [?e :user/age ?age]]");
    if (string_int_batch_query == NULL || !vev_prepared_query_ok(string_int_batch_query)) {
        fprintf(stderr, "failed to prepare string+int column batch query\n");
        if (string_int_batch_query != NULL) {
            vev_prepared_query_free(string_int_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t string_int_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, string_int_batch_query, "[]");
    if (string_int_batch == NULL ||
        vev_column_batch_kind(string_int_batch) != VEV_COLUMN_BATCH_STRING_INT ||
        vev_column_batch_count(string_int_batch) != 2) {
        fprintf(stderr, "unexpected string+int column batch shape\n");
        if (string_int_batch != NULL) {
            vev_column_batch_free(string_int_batch);
        }
        vev_prepared_query_free(string_int_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const void *const *string_int_batch_strings = vev_column_batch_string_data_array(string_int_batch);
    const int *string_int_batch_lengths = vev_column_batch_string_lengths_data(string_int_batch);
    const long long *string_int_batch_ints = vev_column_batch_ints_data(string_int_batch);
    if (vev_column_batch_column_count(string_int_batch) != 2 ||
        vev_column_batch_column_kind(string_int_batch, 0) != VEV_COLUMN_KIND_STRING ||
        vev_column_batch_column_kind(string_int_batch, 1) != VEV_COLUMN_KIND_INT ||
        vev_column_batch_column_kind(string_int_batch, 2) != VEV_COLUMN_KIND_NONE ||
        vev_column_batch_column_string_data_array(string_int_batch, 0) != string_int_batch_strings ||
        vev_column_batch_column_string_lengths_data(string_int_batch, 0) != string_int_batch_lengths ||
        vev_column_batch_column_ints_data(string_int_batch, 1) != string_int_batch_ints) {
        fprintf(stderr, "unexpected generic string+int column metadata\n");
        vev_column_batch_free(string_int_batch);
        vev_prepared_query_free(string_int_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    int saw_ada_age = 0;
    int saw_grace_age = 0;
    for (int i = 0; i < vev_column_batch_count(string_int_batch); i++) {
        if (string_int_batch_ints[i] == 37 &&
            bytes_equal(string_int_batch_strings[i], string_int_batch_lengths[i], "Ada")) {
            saw_ada_age = 1;
        } else if (string_int_batch_ints[i] == 41 &&
                   bytes_equal(string_int_batch_strings[i], string_int_batch_lengths[i], "Grace")) {
            saw_grace_age = 1;
        }
    }
    if (!saw_ada_age || !saw_grace_age) {
        fprintf(stderr, "unexpected string+int column batch contents\n");
        vev_column_batch_free(string_int_batch);
        vev_prepared_query_free(string_int_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("string+int column-batch kind=%d rows=%d\n", vev_column_batch_kind(string_int_batch), vev_column_batch_count(string_int_batch));
    vev_column_batch_free(string_int_batch);
    vev_prepared_query_free(string_int_batch_query);

    vev_prepared_query_t string_string_batch_query =
        vev_prepare_query_edn("[:find ?name ?email :where [?e :user/name ?name] [?e :user/email ?email]]");
    if (string_string_batch_query == NULL || !vev_prepared_query_ok(string_string_batch_query)) {
        fprintf(stderr, "failed to prepare string+string column batch query\n");
        if (string_string_batch_query != NULL) {
            vev_prepared_query_free(string_string_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t string_string_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, string_string_batch_query, "[]");
    if (string_string_batch == NULL ||
        vev_column_batch_kind(string_string_batch) != VEV_COLUMN_BATCH_STRING_STRING ||
        vev_column_batch_count(string_string_batch) != 2) {
        fprintf(stderr, "unexpected string+string column batch shape\n");
        if (string_string_batch != NULL) {
            vev_column_batch_free(string_string_batch);
        }
        vev_prepared_query_free(string_string_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const void *const *string_string_batch_first = vev_column_batch_string_data_array(string_string_batch);
    const int *string_string_batch_first_lengths = vev_column_batch_string_lengths_data(string_string_batch);
    const void *const *string_string_batch_second = vev_column_batch_second_string_data_array(string_string_batch);
    const int *string_string_batch_second_lengths = vev_column_batch_second_string_lengths_data(string_string_batch);
    int saw_ada_email = 0;
    int saw_grace_email = 0;
    for (int i = 0; i < vev_column_batch_count(string_string_batch); i++) {
        if (bytes_equal(string_string_batch_first[i], string_string_batch_first_lengths[i], "Ada") &&
            bytes_equal(string_string_batch_second[i], string_string_batch_second_lengths[i], "ada@example.com")) {
            saw_ada_email = 1;
        } else if (bytes_equal(string_string_batch_first[i], string_string_batch_first_lengths[i], "Grace") &&
                   bytes_equal(string_string_batch_second[i], string_string_batch_second_lengths[i], "grace@example.com")) {
            saw_grace_email = 1;
        }
    }
    if (!saw_ada_email || !saw_grace_email) {
        fprintf(stderr, "unexpected string+string column batch contents\n");
        vev_column_batch_free(string_string_batch);
        vev_prepared_query_free(string_string_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("string+string column-batch kind=%d rows=%d\n", vev_column_batch_kind(string_string_batch), vev_column_batch_count(string_string_batch));
    vev_column_batch_free(string_string_batch);
    vev_prepared_query_free(string_string_batch_query);

    vev_prepared_query_t wide_batch_query =
        vev_prepare_query_edn("[:find ?e ?name ?email ?age :where [?e :user/name ?name] [?e :user/email ?email] [?e :user/age ?age]]");
    if (wide_batch_query == NULL || !vev_prepared_query_ok(wide_batch_query)) {
        fprintf(stderr, "failed to prepare generic wide column batch query\n");
        if (wide_batch_query != NULL) {
            vev_prepared_query_free(wide_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t wide_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, wide_batch_query, "[]");
    if (wide_batch == NULL ||
        vev_column_batch_count(wide_batch) != 2 ||
        vev_column_batch_column_count(wide_batch) != 4 ||
        vev_column_batch_column_kind(wide_batch, 0) != VEV_COLUMN_KIND_ENTITY ||
        vev_column_batch_column_kind(wide_batch, 1) != VEV_COLUMN_KIND_STRING ||
        vev_column_batch_column_kind(wide_batch, 2) != VEV_COLUMN_KIND_STRING ||
        vev_column_batch_column_kind(wide_batch, 3) != VEV_COLUMN_KIND_INT) {
        fprintf(stderr,
                "unexpected generic wide column batch shape: ptr=%p rows=%d cols=%d kinds=[%d %d %d %d]\n",
                (void *)wide_batch,
                wide_batch == NULL ? -1 : vev_column_batch_count(wide_batch),
                wide_batch == NULL ? -1 : vev_column_batch_column_count(wide_batch),
                wide_batch == NULL ? -1 : vev_column_batch_column_kind(wide_batch, 0),
                wide_batch == NULL ? -1 : vev_column_batch_column_kind(wide_batch, 1),
                wide_batch == NULL ? -1 : vev_column_batch_column_kind(wide_batch, 2),
                wide_batch == NULL ? -1 : vev_column_batch_column_kind(wide_batch, 3));
        if (wide_batch != NULL) {
            vev_column_batch_free(wide_batch);
        }
        vev_prepared_query_free(wide_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const unsigned long long *wide_entities = vev_column_batch_column_entities_data(wide_batch, 0);
    const void *const *wide_names = vev_column_batch_column_string_data_array(wide_batch, 1);
    const int *wide_name_lengths = vev_column_batch_column_string_lengths_data(wide_batch, 1);
    const void *const *wide_emails = vev_column_batch_column_string_data_array(wide_batch, 2);
    const int *wide_email_lengths = vev_column_batch_column_string_lengths_data(wide_batch, 2);
    const long long *wide_ages = vev_column_batch_column_ints_data(wide_batch, 3);
    int saw_wide_ada = 0;
    int saw_wide_grace = 0;
    for (int i = 0; i < vev_column_batch_count(wide_batch); i++) {
        if (wide_entities[i] == 1 &&
            wide_ages[i] == 37 &&
            bytes_equal(wide_names[i], wide_name_lengths[i], "Ada") &&
            bytes_equal(wide_emails[i], wide_email_lengths[i], "ada@example.com")) {
            saw_wide_ada = 1;
        } else if (wide_entities[i] == 2 &&
                   wide_ages[i] == 41 &&
                   bytes_equal(wide_names[i], wide_name_lengths[i], "Grace") &&
                   bytes_equal(wide_emails[i], wide_email_lengths[i], "grace@example.com")) {
            saw_wide_grace = 1;
        }
    }
    if (!saw_wide_ada || !saw_wide_grace) {
        fprintf(stderr, "unexpected generic wide column batch contents\n");
        vev_column_batch_free(wide_batch);
        vev_prepared_query_free(wide_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("wide column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(wide_batch),
           vev_column_batch_count(wide_batch));
    vev_column_batch_free(wide_batch);
    vev_prepared_query_free(wide_batch_query);

    vev_prepared_query_t bool_float_batch_query =
        vev_prepare_query_edn("[:find ?active ?score :where [?e :user/name ?name] [?e :user/active ?active] [?e :user/score ?score]]");
    if (bool_float_batch_query == NULL || !vev_prepared_query_ok(bool_float_batch_query)) {
        fprintf(stderr, "failed to prepare bool+float column batch query\n");
        if (bool_float_batch_query != NULL) {
            vev_prepared_query_free(bool_float_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t bool_float_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, bool_float_batch_query, "[]");
    if (bool_float_batch == NULL ||
        vev_column_batch_count(bool_float_batch) != 2 ||
        vev_column_batch_column_count(bool_float_batch) != 2 ||
        vev_column_batch_column_kind(bool_float_batch, 0) != VEV_COLUMN_KIND_BOOL ||
        vev_column_batch_column_kind(bool_float_batch, 1) != VEV_COLUMN_KIND_FLOAT) {
        fprintf(stderr,
                "unexpected bool+float column batch shape: ptr=%p rows=%d cols=%d kinds=[%d %d]\n",
                (void *)bool_float_batch,
                bool_float_batch == NULL ? -1 : vev_column_batch_count(bool_float_batch),
                bool_float_batch == NULL ? -1 : vev_column_batch_column_count(bool_float_batch),
                bool_float_batch == NULL ? -1 : vev_column_batch_column_kind(bool_float_batch, 0),
                bool_float_batch == NULL ? -1 : vev_column_batch_column_kind(bool_float_batch, 1));
        if (bool_float_batch != NULL) {
            vev_column_batch_free(bool_float_batch);
        }
        vev_prepared_query_free(bool_float_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const bool *bool_values = vev_column_batch_column_bools_data(bool_float_batch, 0);
    const double *float_values = vev_column_batch_column_floats_data(bool_float_batch, 1);
    int saw_ada_score = 0;
    int saw_grace_score = 0;
    for (int i = 0; i < vev_column_batch_count(bool_float_batch); i++) {
        if (bool_values[i] && float_values[i] > 9.49 && float_values[i] < 9.51) {
            saw_ada_score = 1;
        } else if (!bool_values[i] && float_values[i] > 8.24 && float_values[i] < 8.26) {
            saw_grace_score = 1;
        }
    }
    if (!saw_ada_score || !saw_grace_score) {
        fprintf(stderr, "unexpected bool+float column batch contents\n");
        vev_column_batch_free(bool_float_batch);
        vev_prepared_query_free(bool_float_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("bool+float column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(bool_float_batch),
           vev_column_batch_count(bool_float_batch));
    vev_column_batch_free(bool_float_batch);
    vev_prepared_query_free(bool_float_batch_query);

    vev_prepared_query_t mixed_batch_query =
        vev_prepare_query_edn("[:find ?value :where (or (and [?e :user/name \"Ada\"] [?e :user/name ?value]) (and [?e :user/name \"Grace\"] [?e :user/age ?value]))]");
    if (mixed_batch_query == NULL || !vev_prepared_query_ok(mixed_batch_query)) {
        fprintf(stderr, "failed to prepare mixed column batch query\n");
        if (mixed_batch_query != NULL) {
            vev_prepared_query_free(mixed_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t mixed_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, mixed_batch_query, "[]");
	if (mixed_batch == NULL ||
	    vev_column_batch_count(mixed_batch) != 2 ||
	    vev_column_batch_column_count(mixed_batch) != 1 ||
	    vev_column_batch_column_kind(mixed_batch, 0) != VEV_COLUMN_KIND_VALUE) {
		fprintf(stderr,
		        "unexpected mixed column batch shape: ptr=%p rows=%d cols=%d kind=%d\n",
		        (void *)mixed_batch,
		        mixed_batch == NULL ? -1 : vev_column_batch_count(mixed_batch),
                mixed_batch == NULL ? -1 : vev_column_batch_column_count(mixed_batch),
                mixed_batch == NULL ? -1 : vev_column_batch_column_kind(mixed_batch, 0));
        if (mixed_batch != NULL) {
            vev_column_batch_free(mixed_batch);
        }
        vev_prepared_query_free(mixed_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
		vev_conn_close(conn);
		return 1;
	}
	const vev_value_t *mixed_values = vev_column_batch_column_values_data(mixed_batch, 0);
	int saw_mixed_ada = 0;
	int saw_mixed_grace_age = 0;
	if (mixed_values != NULL) {
		for (int i = 0; i < vev_column_batch_count(mixed_batch); i++) {
			if (vev_value_kind(mixed_values[i]) == VEV_VALUE_STRING &&
			    value_text_equals(mixed_values[i], "Ada")) {
				saw_mixed_ada = 1;
			} else if (vev_value_kind(mixed_values[i]) == VEV_VALUE_INT &&
			           vev_value_int(mixed_values[i]) == 41) {
				saw_mixed_grace_age = 1;
			}
		}
	}
    if (!saw_mixed_ada || !saw_mixed_grace_age) {
        fprintf(stderr, "unexpected mixed column batch contents\n");
        vev_column_batch_free(mixed_batch);
        vev_prepared_query_free(mixed_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("mixed column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(mixed_batch),
           vev_column_batch_count(mixed_batch));
    vev_column_batch_free(mixed_batch);
    vev_prepared_query_free(mixed_batch_query);

    vev_prepared_query_t value_batch_query =
        vev_prepare_query_edn("[:find ?name ?age ?active ?tags :in ?tags :where [(ground \"Ada\") ?name] [(ground 37) ?age] [(ground true) ?active]]");
    if (value_batch_query == NULL || !vev_prepared_query_ok(value_batch_query)) {
        fprintf(stderr, "failed to prepare value column batch query\n");
        if (value_batch_query != NULL) {
            vev_prepared_query_free(value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, value_batch_query, "[[1 2]]");
    if (value_batch == NULL ||
        vev_column_batch_count(value_batch) != 1 ||
        vev_column_batch_column_count(value_batch) != 4 ||
        vev_column_batch_column_kind(value_batch, 3) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected value column batch shape: ptr=%p rows=%d cols=%d kind3=%d\n",
                (void *)value_batch,
                value_batch == NULL ? -1 : vev_column_batch_count(value_batch),
                value_batch == NULL ? -1 : vev_column_batch_column_count(value_batch),
                value_batch == NULL ? -1 : vev_column_batch_column_kind(value_batch, 3));
        if (value_batch != NULL) {
            vev_column_batch_free(value_batch);
        }
        vev_prepared_query_free(value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *value_cells = vev_column_batch_column_values_data(value_batch, 3);
    if (value_cells == NULL ||
        vev_value_kind(value_cells[0]) != VEV_VALUE_VECTOR ||
        vev_value_item_count(value_cells[0]) != 2 ||
        vev_value_int(vev_value_item(value_cells[0], 0)) != 1 ||
        vev_value_int(vev_value_item(value_cells[0], 1)) != 2) {
        const char *edn = value_cells == NULL ? NULL : vev_value_edn(value_cells[0]);
        fprintf(stderr, "unexpected value column batch contents: %s\n", edn == NULL ? "<null>" : edn);
        if (edn != NULL) {
            vev_string_free(edn);
        }
        vev_column_batch_free(value_batch);
        vev_prepared_query_free(value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(value_batch),
           vev_column_batch_count(value_batch));
    vev_column_batch_free(value_batch);
    vev_prepared_query_free(value_batch_query);

    vev_prepared_query_t ground_value_batch_query =
        vev_prepare_query_edn("[:find ?tags :where [(ground [1 2]) ?tags]]");
    if (ground_value_batch_query == NULL || !vev_prepared_query_ok(ground_value_batch_query)) {
        fprintf(stderr, "failed to prepare ground value column batch query\n");
        if (ground_value_batch_query != NULL) {
            vev_prepared_query_free(ground_value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t ground_value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, ground_value_batch_query, "[]");
    if (ground_value_batch == NULL ||
        vev_column_batch_count(ground_value_batch) != 1 ||
        vev_column_batch_column_count(ground_value_batch) != 1 ||
        vev_column_batch_column_kind(ground_value_batch, 0) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected ground value column batch shape: ptr=%p rows=%d cols=%d kind0=%d\n",
                (void *)ground_value_batch,
                ground_value_batch == NULL ? -1 : vev_column_batch_count(ground_value_batch),
                ground_value_batch == NULL ? -1 : vev_column_batch_column_count(ground_value_batch),
                ground_value_batch == NULL ? -1 : vev_column_batch_column_kind(ground_value_batch, 0));
        if (ground_value_batch != NULL) {
            vev_column_batch_free(ground_value_batch);
        }
        vev_prepared_query_free(ground_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *ground_value_cells = vev_column_batch_column_values_data(ground_value_batch, 0);
    if (ground_value_cells == NULL ||
        vev_value_kind(ground_value_cells[0]) != VEV_VALUE_VECTOR ||
        vev_value_item_count(ground_value_cells[0]) != 2 ||
        vev_value_int(vev_value_item(ground_value_cells[0], 0)) != 1 ||
        vev_value_int(vev_value_item(ground_value_cells[0], 1)) != 2) {
        fprintf(stderr, "unexpected ground value column batch contents\n");
        vev_column_batch_free(ground_value_batch);
        vev_prepared_query_free(ground_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("ground value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(ground_value_batch),
           vev_column_batch_count(ground_value_batch));
    vev_column_batch_free(ground_value_batch);
    vev_prepared_query_free(ground_value_batch_query);

    vev_prepared_query_t function_value_batch_query =
        vev_prepare_query_edn("[:find ?pair :where [?e :user/name ?name] [?e :user/age ?age] [(vector ?name ?age) ?pair]]");
    if (function_value_batch_query == NULL || !vev_prepared_query_ok(function_value_batch_query)) {
        fprintf(stderr, "failed to prepare function value column batch query\n");
        if (function_value_batch_query != NULL) {
            vev_prepared_query_free(function_value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t function_value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, function_value_batch_query, "[]");
    if (function_value_batch == NULL ||
        vev_column_batch_count(function_value_batch) != 2 ||
        vev_column_batch_column_count(function_value_batch) != 1 ||
        vev_column_batch_column_kind(function_value_batch, 0) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected function value column batch shape: ptr=%p rows=%d cols=%d kind0=%d\n",
                (void *)function_value_batch,
                function_value_batch == NULL ? -1 : vev_column_batch_count(function_value_batch),
                function_value_batch == NULL ? -1 : vev_column_batch_column_count(function_value_batch),
                function_value_batch == NULL ? -1 : vev_column_batch_column_kind(function_value_batch, 0));
        if (function_value_batch != NULL) {
            vev_column_batch_free(function_value_batch);
        }
        vev_prepared_query_free(function_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *function_value_cells = vev_column_batch_column_values_data(function_value_batch, 0);
    int saw_ada_pair = 0;
    int saw_grace_pair = 0;
    if (function_value_cells != NULL) {
        for (int i = 0; i < vev_column_batch_count(function_value_batch); i++) {
            if (vev_value_kind(function_value_cells[i]) == VEV_VALUE_VECTOR &&
                vev_value_item_count(function_value_cells[i]) == 2) {
                const vev_value_t name = vev_value_item(function_value_cells[i], 0);
                const vev_value_t age = vev_value_item(function_value_cells[i], 1);
                if (vev_value_kind(name) == VEV_VALUE_STRING &&
                    vev_value_kind(age) == VEV_VALUE_INT &&
                    value_text_equals(name, "Ada") &&
                    vev_value_int(age) == 37) {
                    saw_ada_pair = 1;
                } else if (vev_value_kind(name) == VEV_VALUE_STRING &&
                           vev_value_kind(age) == VEV_VALUE_INT &&
                           value_text_equals(name, "Grace") &&
                           vev_value_int(age) == 41) {
                    saw_grace_pair = 1;
                }
            }
        }
    }
    if (!saw_ada_pair || !saw_grace_pair) {
        fprintf(stderr, "unexpected function value column batch contents\n");
        vev_column_batch_free(function_value_batch);
        vev_prepared_query_free(function_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("function value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(function_value_batch),
           vev_column_batch_count(function_value_batch));
    vev_column_batch_free(function_value_batch);
    vev_prepared_query_free(function_value_batch_query);

    vev_prepared_query_t promoted_value_batch_query =
        vev_prepare_query_edn("[:find ?x :where [?e :user/mixed ?x]]");
    if (promoted_value_batch_query == NULL || !vev_prepared_query_ok(promoted_value_batch_query)) {
        fprintf(stderr, "failed to prepare promoted value column batch query\n");
        if (promoted_value_batch_query != NULL) {
            vev_prepared_query_free(promoted_value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t promoted_value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, promoted_value_batch_query, "[]");
    if (promoted_value_batch == NULL ||
        vev_column_batch_count(promoted_value_batch) != 2 ||
        vev_column_batch_column_count(promoted_value_batch) != 1 ||
        vev_column_batch_column_kind(promoted_value_batch, 0) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected promoted value column batch shape: ptr=%p rows=%d cols=%d kind0=%d\n",
                (void *)promoted_value_batch,
                promoted_value_batch == NULL ? -1 : vev_column_batch_count(promoted_value_batch),
                promoted_value_batch == NULL ? -1 : vev_column_batch_column_count(promoted_value_batch),
                promoted_value_batch == NULL ? -1 : vev_column_batch_column_kind(promoted_value_batch, 0));
        if (promoted_value_batch != NULL) {
            vev_column_batch_free(promoted_value_batch);
        }
        vev_prepared_query_free(promoted_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *promoted_value_cells = vev_column_batch_column_values_data(promoted_value_batch, 0);
    int saw_promoted_int = 0;
    int saw_promoted_vector = 0;
    if (promoted_value_cells != NULL) {
        for (int i = 0; i < vev_column_batch_count(promoted_value_batch); i++) {
            if (vev_value_kind(promoted_value_cells[i]) == VEV_VALUE_INT &&
                vev_value_int(promoted_value_cells[i]) == 1) {
                saw_promoted_int = 1;
            } else if (vev_value_kind(promoted_value_cells[i]) == VEV_VALUE_VECTOR &&
                       vev_value_item_count(promoted_value_cells[i]) == 2 &&
                       vev_value_int(vev_value_item(promoted_value_cells[i], 0)) == 2 &&
                       vev_value_int(vev_value_item(promoted_value_cells[i], 1)) == 3) {
                saw_promoted_vector = 1;
            }
        }
    }
    if (!saw_promoted_int || !saw_promoted_vector) {
        fprintf(stderr, "unexpected promoted value column batch contents\n");
        vev_column_batch_free(promoted_value_batch);
        vev_prepared_query_free(promoted_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("promoted value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(promoted_value_batch),
           vev_column_batch_count(promoted_value_batch));
    vev_column_batch_free(promoted_value_batch);
    vev_prepared_query_free(promoted_value_batch_query);

    vev_prepared_query_t top_n_value_batch_query =
        vev_prepare_query_edn("[:find (max 1 ?age) (min 1 ?age) :where [?e :user/age ?age]]");
    if (top_n_value_batch_query == NULL || !vev_prepared_query_ok(top_n_value_batch_query)) {
        fprintf(stderr, "failed to prepare top-n value column batch query\n");
        if (top_n_value_batch_query != NULL) {
            vev_prepared_query_free(top_n_value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t top_n_value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, top_n_value_batch_query, "[]");
    if (top_n_value_batch == NULL ||
        vev_column_batch_count(top_n_value_batch) != 1 ||
        vev_column_batch_column_count(top_n_value_batch) != 2 ||
        vev_column_batch_column_kind(top_n_value_batch, 0) != VEV_COLUMN_KIND_VALUE ||
        vev_column_batch_column_kind(top_n_value_batch, 1) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected top-n value column batch shape: ptr=%p rows=%d cols=%d kinds=[%d %d]\n",
                (void *)top_n_value_batch,
                top_n_value_batch == NULL ? -1 : vev_column_batch_count(top_n_value_batch),
                top_n_value_batch == NULL ? -1 : vev_column_batch_column_count(top_n_value_batch),
                top_n_value_batch == NULL ? -1 : vev_column_batch_column_kind(top_n_value_batch, 0),
                top_n_value_batch == NULL ? -1 : vev_column_batch_column_kind(top_n_value_batch, 1));
        if (top_n_value_batch != NULL) {
            vev_column_batch_free(top_n_value_batch);
        }
        vev_prepared_query_free(top_n_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *top_n_max_cells = vev_column_batch_column_values_data(top_n_value_batch, 0);
    const vev_value_t *top_n_min_cells = vev_column_batch_column_values_data(top_n_value_batch, 1);
    if (top_n_max_cells == NULL ||
        top_n_min_cells == NULL ||
        vev_value_kind(top_n_max_cells[0]) != VEV_VALUE_VECTOR ||
        vev_value_kind(top_n_min_cells[0]) != VEV_VALUE_VECTOR ||
        vev_value_item_count(top_n_max_cells[0]) != 1 ||
        vev_value_item_count(top_n_min_cells[0]) != 1 ||
        vev_value_int(vev_value_item(top_n_max_cells[0], 0)) != 41 ||
        vev_value_int(vev_value_item(top_n_min_cells[0], 0)) != 37) {
        fprintf(stderr, "unexpected top-n value column batch contents\n");
        vev_column_batch_free(top_n_value_batch);
        vev_prepared_query_free(top_n_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("top-n value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(top_n_value_batch),
           vev_column_batch_count(top_n_value_batch));
    vev_column_batch_free(top_n_value_batch);
    vev_prepared_query_free(top_n_value_batch_query);

    vev_prepared_query_t pull_value_batch_query =
        vev_prepare_query_edn("[:find (pull ?e [:user/name {:user/friend [:user/name]}]) :where [?e :user/name \"Ada\"]]");
    if (pull_value_batch_query == NULL || !vev_prepared_query_ok(pull_value_batch_query)) {
        fprintf(stderr, "failed to prepare pull value column batch query\n");
        if (pull_value_batch_query != NULL) {
            vev_prepared_query_free(pull_value_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t pull_value_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, pull_value_batch_query, "[]");
    if (pull_value_batch == NULL ||
        vev_column_batch_count(pull_value_batch) != 1 ||
        vev_column_batch_column_count(pull_value_batch) != 1 ||
        vev_column_batch_column_kind(pull_value_batch, 0) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected pull value column batch shape: ptr=%p rows=%d cols=%d kind0=%d\n",
                (void *)pull_value_batch,
                pull_value_batch == NULL ? -1 : vev_column_batch_count(pull_value_batch),
                pull_value_batch == NULL ? -1 : vev_column_batch_column_count(pull_value_batch),
                pull_value_batch == NULL ? -1 : vev_column_batch_column_kind(pull_value_batch, 0));
        if (pull_value_batch != NULL) {
            vev_column_batch_free(pull_value_batch);
        }
        vev_prepared_query_free(pull_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *pull_value_cells = vev_column_batch_column_values_data(pull_value_batch, 0);
    vev_value_t pull_value_name = pull_value_cells == NULL ? NULL : map_get(pull_value_cells[0], ":user/name");
    vev_value_t pull_value_friend = pull_value_cells == NULL ? NULL : map_get(pull_value_cells[0], ":user/friend");
    vev_value_t pull_value_friend_name = pull_value_friend == NULL ? NULL : map_get(pull_value_friend, ":user/name");
    if (pull_value_cells == NULL ||
        vev_value_kind(pull_value_cells[0]) != VEV_VALUE_MAP ||
        !value_text_equals(pull_value_name, "Ada") ||
        !value_text_equals(pull_value_friend_name, "Grace")) {
        const char *edn = pull_value_cells == NULL ? NULL : vev_value_edn(pull_value_cells[0]);
        fprintf(stderr, "unexpected pull value column batch contents: %s\n", edn == NULL ? "<null>" : edn);
        if (edn != NULL) {
            vev_string_free(edn);
        }
        vev_column_batch_free(pull_value_batch);
        vev_prepared_query_free(pull_value_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("pull value column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(pull_value_batch),
           vev_column_batch_count(pull_value_batch));
    vev_column_batch_free(pull_value_batch);
    vev_prepared_query_free(pull_value_batch_query);

    vev_prepared_query_t pull_aggregate_batch_query =
        vev_prepare_query_edn("[:find ?e (pull ?e [:user/name]) (count ?age) :where [?e :user/name] [?e :user/age ?age]]");
    if (pull_aggregate_batch_query == NULL || !vev_prepared_query_ok(pull_aggregate_batch_query)) {
        fprintf(stderr, "failed to prepare pull+aggregate column batch query\n");
        if (pull_aggregate_batch_query != NULL) {
            vev_prepared_query_free(pull_aggregate_batch_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t pull_aggregate_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, pull_aggregate_batch_query, "[]");
    if (pull_aggregate_batch == NULL ||
        vev_column_batch_count(pull_aggregate_batch) != 2 ||
        vev_column_batch_column_count(pull_aggregate_batch) != 3 ||
        vev_column_batch_column_kind(pull_aggregate_batch, 0) != VEV_COLUMN_KIND_ENTITY ||
        vev_column_batch_column_kind(pull_aggregate_batch, 1) != VEV_COLUMN_KIND_VALUE ||
        vev_column_batch_column_kind(pull_aggregate_batch, 2) != VEV_COLUMN_KIND_INT) {
        fprintf(stderr,
                "unexpected pull+aggregate column batch shape: ptr=%p rows=%d cols=%d kinds=[%d %d %d]\n",
                (void *)pull_aggregate_batch,
                pull_aggregate_batch == NULL ? -1 : vev_column_batch_count(pull_aggregate_batch),
                pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_count(pull_aggregate_batch),
                pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_kind(pull_aggregate_batch, 0),
                pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_kind(pull_aggregate_batch, 1),
                pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_kind(pull_aggregate_batch, 2));
        if (pull_aggregate_batch != NULL) {
            vev_column_batch_free(pull_aggregate_batch);
        }
        vev_prepared_query_free(pull_aggregate_batch_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const unsigned long long *pull_aggregate_entities = vev_column_batch_column_entities_data(pull_aggregate_batch, 0);
    const vev_value_t *pull_aggregate_pulls = vev_column_batch_column_values_data(pull_aggregate_batch, 1);
    const long long *pull_aggregate_counts = vev_column_batch_column_ints_data(pull_aggregate_batch, 2);
    for (int i = 0; i < vev_column_batch_count(pull_aggregate_batch); i++) {
        vev_value_t name = pull_aggregate_pulls == NULL ? NULL : map_get(pull_aggregate_pulls[i], ":user/name");
        if (pull_aggregate_entities == NULL ||
            pull_aggregate_pulls == NULL ||
            pull_aggregate_counts == NULL ||
            pull_aggregate_entities[i] == 0 ||
            pull_aggregate_counts[i] != 1 ||
            vev_value_kind(pull_aggregate_pulls[i]) != VEV_VALUE_MAP ||
            vev_value_kind(name) != VEV_VALUE_STRING) {
            const char *edn = pull_aggregate_pulls == NULL ? NULL : vev_value_edn(pull_aggregate_pulls[i]);
            fprintf(stderr, "unexpected pull+aggregate column batch row: %s\n", edn == NULL ? "<null>" : edn);
            if (edn != NULL) {
                vev_string_free(edn);
            }
            vev_column_batch_free(pull_aggregate_batch);
            vev_prepared_query_free(pull_aggregate_batch_query);
            vev_db_release(batch_db);
            vev_prepared_query_free(query);
            vev_conn_close(conn);
            return 1;
        }
    }
    printf("pull+aggregate column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(pull_aggregate_batch),
           vev_column_batch_count(pull_aggregate_batch));
    vev_column_batch_free(pull_aggregate_batch);
    vev_prepared_query_free(pull_aggregate_batch_query);

    vev_prepared_query_t hidden_group_pull_aggregate_query =
        vev_prepare_query_edn("[:find (pull ?e [:user/name]) (count ?age) :where [?e :user/name] [?e :user/age ?age]]");
    if (hidden_group_pull_aggregate_query == NULL ||
        !vev_prepared_query_ok(hidden_group_pull_aggregate_query)) {
        fprintf(stderr, "failed to prepare hidden-group pull+aggregate column batch query\n");
        if (hidden_group_pull_aggregate_query != NULL) {
            vev_prepared_query_free(hidden_group_pull_aggregate_query);
        }
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t hidden_group_pull_aggregate_batch =
        vev_query_db_prepared_column_batch_with_inputs(batch_db, hidden_group_pull_aggregate_query, "[]");
    if (hidden_group_pull_aggregate_batch == NULL ||
        vev_column_batch_count(hidden_group_pull_aggregate_batch) != 2 ||
        vev_column_batch_column_count(hidden_group_pull_aggregate_batch) != 2 ||
        vev_column_batch_column_kind(hidden_group_pull_aggregate_batch, 0) != VEV_COLUMN_KIND_VALUE ||
        vev_column_batch_column_kind(hidden_group_pull_aggregate_batch, 1) != VEV_COLUMN_KIND_INT) {
        fprintf(stderr,
                "unexpected hidden-group pull+aggregate column batch shape: ptr=%p rows=%d cols=%d kinds=[%d %d]\n",
                (void *)hidden_group_pull_aggregate_batch,
                hidden_group_pull_aggregate_batch == NULL ? -1 : vev_column_batch_count(hidden_group_pull_aggregate_batch),
                hidden_group_pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_count(hidden_group_pull_aggregate_batch),
                hidden_group_pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_kind(hidden_group_pull_aggregate_batch, 0),
                hidden_group_pull_aggregate_batch == NULL ? -1 : vev_column_batch_column_kind(hidden_group_pull_aggregate_batch, 1));
        if (hidden_group_pull_aggregate_batch != NULL) {
            vev_column_batch_free(hidden_group_pull_aggregate_batch);
        }
        vev_prepared_query_free(hidden_group_pull_aggregate_query);
        vev_db_release(batch_db);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *hidden_group_pull_aggregate_pulls =
        vev_column_batch_column_values_data(hidden_group_pull_aggregate_batch, 0);
    const long long *hidden_group_pull_aggregate_counts =
        vev_column_batch_column_ints_data(hidden_group_pull_aggregate_batch, 1);
    for (int i = 0; i < vev_column_batch_count(hidden_group_pull_aggregate_batch); i++) {
        vev_value_t name = hidden_group_pull_aggregate_pulls == NULL ? NULL : map_get(hidden_group_pull_aggregate_pulls[i], ":user/name");
        if (hidden_group_pull_aggregate_pulls == NULL ||
            hidden_group_pull_aggregate_counts == NULL ||
            hidden_group_pull_aggregate_counts[i] != 1 ||
            vev_value_kind(hidden_group_pull_aggregate_pulls[i]) != VEV_VALUE_MAP ||
            vev_value_kind(name) != VEV_VALUE_STRING) {
            const char *edn = hidden_group_pull_aggregate_pulls == NULL ? NULL : vev_value_edn(hidden_group_pull_aggregate_pulls[i]);
            fprintf(stderr, "unexpected hidden-group pull+aggregate column batch row: %s\n", edn == NULL ? "<null>" : edn);
            if (edn != NULL) {
                vev_string_free(edn);
            }
            vev_column_batch_free(hidden_group_pull_aggregate_batch);
            vev_prepared_query_free(hidden_group_pull_aggregate_query);
            vev_db_release(batch_db);
            vev_prepared_query_free(query);
            vev_conn_close(conn);
            return 1;
        }
    }
    printf("hidden-group pull+aggregate column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(hidden_group_pull_aggregate_batch),
           vev_column_batch_count(hidden_group_pull_aggregate_batch));
    vev_column_batch_free(hidden_group_pull_aggregate_batch);
    vev_prepared_query_free(hidden_group_pull_aggregate_query);

    vev_db_release(batch_db);

    vev_stmt_t stmt = vev_stmt_create(query);
    if (stmt == NULL) {
        fprintf(stderr, "failed to create statement\n");
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_stmt_bind_string(stmt, "ada@example.com")) {
        fprintf(stderr, "failed to bind statement string\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    struct result_visit_stats streamed_stmt_stats = {0, 0, 0, 0};
    if (!vev_query_stmt_visit(conn, stmt, count_result_visit, &streamed_stmt_stats) ||
        streamed_stmt_stats.row_begins != 1 ||
        streamed_stmt_stats.row_ends != 1 ||
        streamed_stmt_stats.values != 2 ||
        streamed_stmt_stats.pulls != 0) {
        fprintf(
            stderr,
            "unexpected streamed statement stats: rows=%d/%d values=%d pulls=%d\n",
            streamed_stmt_stats.row_begins,
            streamed_stmt_stats.row_ends,
            streamed_stmt_stats.values,
            streamed_stmt_stats.pulls);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    if (vev_query_stmt_visit(conn, stmt, cancel_result_visit, NULL)) {
        fprintf(stderr, "cancelled statement visitor unexpectedly succeeded\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *stmt_error = vev_stmt_error(stmt);
    int cancelled = stmt_error != NULL && strstr(stmt_error, "cancelled") != NULL;
    vev_string_free(stmt_error);
    if (!cancelled) {
        fprintf(stderr, "cancelled statement visitor did not expose an error\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t stmt_result = vev_query_stmt_result(conn, stmt);
    int stmt_rows = result_row_count_or_error("stmt", stmt_result);
    printf("stmt rows: %d\n", stmt_rows);
    vev_result_free(stmt_result);
    vev_stmt_clear(stmt);
    if (!vev_stmt_bind_string(stmt, "grace@example.com")) {
        fprintf(stderr, "failed to rebind statement string\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t rebound = vev_query_stmt_result(conn, stmt);
    int rebound_rows = result_row_count_or_error("stmt-rebound", rebound);
    printf("stmt-rebound rows: %d\n", rebound_rows);
    vev_result_free(rebound);
    if (stmt_rows != 1 || rebound_rows != 1) {
        fprintf(stderr, "unexpected statement row counts\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }

    vev_prepared_query_t stmt_batch_query =
        vev_prepare_query_edn("[:find ?name :in $ ?email :where [?e :user/email ?email] [?e :user/name ?name]]");
    if (stmt_batch_query == NULL ||
        !vev_prepared_query_ok(stmt_batch_query)) {
        fprintf(stderr, "failed to prepare statement column batch query\n");
        if (stmt_batch_query != NULL) {
            vev_prepared_query_free(stmt_batch_query);
        }
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t stmt_batch_stmt = vev_stmt_create(stmt_batch_query);
    if (stmt_batch_stmt == NULL ||
        !vev_stmt_bind_string(stmt_batch_stmt, "ada@example.com")) {
        fprintf(stderr, "failed to bind statement column batch query\n");
        if (stmt_batch_stmt != NULL) {
            vev_stmt_free(stmt_batch_stmt);
        }
        vev_prepared_query_free(stmt_batch_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t stmt_batch = vev_query_stmt_column_batch(conn, stmt_batch_stmt);
    if (stmt_batch == NULL ||
        vev_column_batch_kind(stmt_batch) != VEV_COLUMN_BATCH_STRING ||
        vev_column_batch_count(stmt_batch) != 1) {
        fprintf(stderr, "unexpected statement column batch shape\n");
        if (stmt_batch != NULL) {
            vev_column_batch_free(stmt_batch);
        }
        vev_stmt_free(stmt_batch_stmt);
        vev_prepared_query_free(stmt_batch_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const void *const *stmt_batch_strings = vev_column_batch_string_data_array(stmt_batch);
    const int *stmt_batch_lengths = vev_column_batch_string_lengths_data(stmt_batch);
    if (!bytes_equal(stmt_batch_strings[0], stmt_batch_lengths[0], "Ada")) {
        fprintf(stderr, "unexpected statement column batch contents\n");
        vev_column_batch_free(stmt_batch);
        vev_stmt_free(stmt_batch_stmt);
        vev_prepared_query_free(stmt_batch_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("stmt column-batch kind=%d rows=%d\n", vev_column_batch_kind(stmt_batch), vev_column_batch_count(stmt_batch));
    vev_column_batch_free(stmt_batch);
    vev_stmt_free(stmt_batch_stmt);
    vev_prepared_query_free(stmt_batch_query);

    vev_prepared_query_t collection_query =
        vev_prepare_query_edn("[:find ?name :in $ [?email ...] :where [?e :user/email ?email] [?e :user/name ?name]]");
    if (collection_query == NULL) {
        fprintf(stderr, "failed to prepare collection query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t collection_stmt = vev_stmt_create(collection_query);
    if (collection_stmt == NULL) {
        fprintf(stderr, "failed to create collection statement\n");
        vev_prepared_query_free(collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *emails[] = {"ada@example.com", "grace@example.com"};
    if (!vev_stmt_bind_string_collection(collection_stmt, emails, 2)) {
        fprintf(stderr, "failed to bind collection statement\n");
        vev_stmt_free(collection_stmt);
        vev_prepared_query_free(collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t collection_stmt_result = vev_query_stmt_result(conn, collection_stmt);
    int collection_stmt_rows = result_row_count_or_error("stmt-collection", collection_stmt_result);
    printf("stmt-collection rows: %d\n", collection_stmt_rows);
    vev_result_free(collection_stmt_result);
    if (collection_stmt_rows != 2) {
        fprintf(stderr, "unexpected collection statement row count\n");
        vev_stmt_free(collection_stmt);
        vev_prepared_query_free(collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_free(collection_stmt);
    vev_prepared_query_free(collection_query);

    vev_prepared_query_t tuple_query =
        vev_prepare_query_edn("[:find ?e :in $ [?name ?email] :where [?e :user/name ?name] [?e :user/email ?email]]");
    if (tuple_query == NULL) {
        fprintf(stderr, "failed to prepare tuple query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t tuple_stmt = vev_stmt_create(tuple_query);
    if (tuple_stmt == NULL) {
        fprintf(stderr, "failed to create tuple statement\n");
        vev_prepared_query_free(tuple_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *tuple_values[] = {"Ada", "ada@example.com"};
    if (!vev_stmt_bind_string_tuple(tuple_stmt, tuple_values, 2)) {
        fprintf(stderr, "failed to bind tuple statement\n");
        vev_stmt_free(tuple_stmt);
        vev_prepared_query_free(tuple_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t tuple_result = vev_query_stmt_result(conn, tuple_stmt);
    int tuple_rows = result_row_count_or_error("stmt-tuple", tuple_result);
    printf("stmt-tuple rows: %d\n", tuple_rows);
    vev_result_free(tuple_result);
    if (tuple_rows != 1) {
        fprintf(stderr, "unexpected tuple statement row count\n");
        vev_stmt_free(tuple_stmt);
        vev_prepared_query_free(tuple_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_free(tuple_stmt);
    vev_prepared_query_free(tuple_query);

    vev_prepared_query_t relation_query =
        vev_prepare_query_edn("[:find ?name ?label :in $ [[?email ?label]] :where [?e :user/email ?email] [?e :user/name ?name]]");
    if (relation_query == NULL) {
        fprintf(stderr, "failed to prepare relation query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t relation_stmt = vev_stmt_create(relation_query);
    if (relation_stmt == NULL) {
        fprintf(stderr, "failed to create relation statement\n");
        vev_prepared_query_free(relation_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *relation_values[] = {
        "ada@example.com",
        "primary",
        "missing@example.com",
        "missing",
    };
    if (!vev_stmt_bind_string_relation(relation_stmt, relation_values, 4, 2)) {
        fprintf(stderr, "failed to bind relation statement\n");
        vev_stmt_free(relation_stmt);
        vev_prepared_query_free(relation_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t relation_result = vev_query_stmt_result(conn, relation_stmt);
    int relation_rows = result_row_count_or_error("stmt-relation", relation_result);
    vev_value_t relation_name = vev_result_value(relation_result, 0, 0);
    vev_value_t relation_label = vev_result_value(relation_result, 0, 1);
    printf("stmt-relation rows: %d\n", relation_rows);
    if (relation_rows != 1 ||
        !value_text_equals(relation_name, "Ada") ||
        !value_text_equals(relation_label, "primary")) {
        fprintf(stderr, "unexpected relation statement result\n");
        vev_result_free(relation_result);
        vev_stmt_free(relation_stmt);
        vev_prepared_query_free(relation_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_free(relation_result);
    vev_stmt_free(relation_stmt);
    vev_prepared_query_free(relation_query);

    vev_prepared_query_t lookup_query =
        vev_prepare_query_edn("[:find ?name :in $ ?person :where [?person :user/name ?name]]");
    if (lookup_query == NULL) {
        fprintf(stderr, "failed to prepare lookup-ref query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t lookup_stmt = vev_stmt_create(lookup_query);
    if (lookup_stmt == NULL) {
        fprintf(stderr, "failed to create lookup-ref statement\n");
        vev_prepared_query_free(lookup_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_stmt_bind_lookup_ref_string(lookup_stmt, ":user/email", "ada@example.com")) {
        fprintf(stderr, "failed to bind lookup-ref statement\n");
        vev_stmt_free(lookup_stmt);
        vev_prepared_query_free(lookup_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t lookup_result = vev_query_stmt_result(conn, lookup_stmt);
    int lookup_rows = result_row_count_or_error("stmt-lookup-ref", lookup_result);
    vev_value_t lookup_name = vev_result_value(lookup_result, 0, 0);
    printf("stmt-lookup-ref rows: %d\n", lookup_rows);
    if (lookup_rows != 1 || !value_text_equals(lookup_name, "Ada")) {
        fprintf(stderr, "unexpected lookup-ref statement result\n");
        vev_result_free(lookup_result);
        vev_stmt_free(lookup_stmt);
        vev_prepared_query_free(lookup_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_free(lookup_result);
    vev_stmt_free(lookup_stmt);
    vev_prepared_query_free(lookup_query);

    vev_prepared_query_t lookup_collection_query =
        vev_prepare_query_edn("[:find ?name :in $ [?person ...] :where [?person :user/name ?name]]");
    if (lookup_collection_query == NULL) {
        fprintf(stderr, "failed to prepare lookup-ref collection query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t lookup_collection_stmt = vev_stmt_create(lookup_collection_query);
    if (lookup_collection_stmt == NULL) {
        fprintf(stderr, "failed to create lookup-ref collection statement\n");
        vev_prepared_query_free(lookup_collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_stmt_bind_lookup_ref_string_collection(lookup_collection_stmt, ":user/email", emails, 2)) {
        fprintf(stderr, "failed to bind lookup-ref collection statement\n");
        vev_stmt_free(lookup_collection_stmt);
        vev_prepared_query_free(lookup_collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t lookup_collection_result = vev_query_stmt_result(conn, lookup_collection_stmt);
    int lookup_collection_rows = result_row_count_or_error("stmt-lookup-ref-collection", lookup_collection_result);
    printf("stmt-lookup-ref-collection rows: %d\n", lookup_collection_rows);
    vev_result_free(lookup_collection_result);
    if (lookup_collection_rows != 2) {
        fprintf(stderr, "unexpected lookup-ref collection statement row count\n");
        vev_stmt_free(lookup_collection_stmt);
        vev_prepared_query_free(lookup_collection_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_free(lookup_collection_stmt);
    vev_prepared_query_free(lookup_collection_query);

    vev_prepared_query_t pull_query =
        vev_prepare_query_edn("[:find (pull ?e [:user/name {:user/friend [:user/name]}]) :where [?e :user/name \"Ada\"]]");
    if (pull_query == NULL) {
        fprintf(stderr, "failed to prepare pull query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t pull_result = vev_query_prepared_result_with_inputs(conn, pull_query, "[]");
    int pull_rows = result_row_count_or_error("pull", pull_result);
    int pull_count = vev_result_pull_count(pull_result, 0);
    vev_value_t pulled = vev_result_pull(pull_result, 0, 0);
    vev_value_t name = map_get(pulled, ":user/name");
    vev_value_t friend_map = map_get(pulled, ":user/friend");
    vev_value_t friend_name = map_get(friend_map, ":user/name");
    printf("pull rows: %d pulls: %d\n", pull_rows, pull_count);
    if (pull_rows != 1 ||
        pull_count != 1 ||
        vev_value_kind(pulled) != VEV_VALUE_MAP ||
        !value_text_equals(name, "Ada") ||
        !value_text_equals(friend_name, "Grace")) {
        const char *edn = vev_value_edn(pulled);
        fprintf(stderr, "unexpected pull traversal output: %s\n", edn);
        vev_string_free(edn);
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    struct value_visit_stats visit_stats = {0, 0, 0, 0};
    if (!vev_value_visit(pulled, count_value_visit, &visit_stats) ||
        visit_stats.values < 7 ||
        visit_stats.ends != 2 ||
        visit_stats.max_depth < 2 ||
        visit_stats.depth != 0) {
        fprintf(
            stderr,
            "unexpected pull visitor stats: values=%d ends=%d max_depth=%d depth=%d\n",
            visit_stats.values,
            visit_stats.ends,
            visit_stats.max_depth,
            visit_stats.depth);
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    struct result_visit_stats pull_result_stats = {0, 0, 0, 0};
    if (!vev_result_visit(pull_result, count_result_visit, &pull_result_stats) ||
        pull_result_stats.row_begins != 1 ||
        pull_result_stats.row_ends != 1 ||
        pull_result_stats.values != 0 ||
        pull_result_stats.pulls != 1) {
        fprintf(
            stderr,
            "unexpected pull result visitor stats: rows=%d/%d values=%d pulls=%d\n",
            pull_result_stats.row_begins,
            pull_result_stats.row_ends,
            pull_result_stats.values,
            pull_result_stats.pulls);
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t pull_batch_stmt = vev_stmt_create(pull_query);
    if (pull_batch_stmt == NULL) {
        fprintf(stderr, "failed to create resident pull column batch statement\n");
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t resident_pull_batch = vev_query_stmt_column_batch(conn, pull_batch_stmt);
    if (resident_pull_batch == NULL ||
        vev_column_batch_count(resident_pull_batch) != 1 ||
        vev_column_batch_column_count(resident_pull_batch) != 1 ||
        vev_column_batch_column_kind(resident_pull_batch, 0) != VEV_COLUMN_KIND_VALUE) {
        fprintf(stderr,
                "unexpected resident pull column batch shape: ptr=%p rows=%d cols=%d kind0=%d\n",
                (void *)resident_pull_batch,
                resident_pull_batch == NULL ? -1 : vev_column_batch_count(resident_pull_batch),
                resident_pull_batch == NULL ? -1 : vev_column_batch_column_count(resident_pull_batch),
                resident_pull_batch == NULL ? -1 : vev_column_batch_column_kind(resident_pull_batch, 0));
        if (resident_pull_batch != NULL) {
            vev_column_batch_free(resident_pull_batch);
        }
        vev_stmt_free(pull_batch_stmt);
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const vev_value_t *resident_pull_cells = vev_column_batch_column_values_data(resident_pull_batch, 0);
    vev_value_t resident_pull_name = resident_pull_cells == NULL ? NULL : map_get(resident_pull_cells[0], ":user/name");
    vev_value_t resident_pull_friend = resident_pull_cells == NULL ? NULL : map_get(resident_pull_cells[0], ":user/friend");
    vev_value_t resident_pull_friend_name = resident_pull_friend == NULL ? NULL : map_get(resident_pull_friend, ":user/name");
    if (resident_pull_cells == NULL ||
        vev_value_kind(resident_pull_cells[0]) != VEV_VALUE_MAP ||
        !value_text_equals(resident_pull_name, "Ada") ||
        !value_text_equals(resident_pull_friend_name, "Grace")) {
        const char *edn = resident_pull_cells == NULL ? NULL : vev_value_edn(resident_pull_cells[0]);
        fprintf(stderr, "unexpected resident pull column batch contents: %s\n", edn == NULL ? "<null>" : edn);
        if (edn != NULL) {
            vev_string_free(edn);
        }
        vev_column_batch_free(resident_pull_batch);
        vev_stmt_free(pull_batch_stmt);
        vev_result_free(pull_result);
        vev_prepared_query_free(pull_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("resident pull column-batch columns=%d rows=%d\n",
           vev_column_batch_column_count(resident_pull_batch),
           vev_column_batch_count(resident_pull_batch));
    vev_column_batch_free(resident_pull_batch);
    vev_stmt_free(pull_batch_stmt);
    vev_result_free(pull_result);
    vev_prepared_query_free(pull_query);

    vev_db_t pull_db = vev_conn_db(conn);
    if (pull_db == NULL) {
        fprintf(stderr, "failed to retain DB for pull API\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }

    vev_value_handle_t direct_pull =
        vev_pull_edn(pull_db, "[:user/name {:user/friend [:user/name]}]", 1);
    if (direct_pull == NULL) {
        fprintf(stderr, "failed direct pull API\n");
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_t direct_value = vev_value_handle_value(direct_pull);
    const char *direct_edn = vev_value_handle_edn(direct_pull);
    printf("direct-pull: %s\n", direct_edn);
    vev_string_free(direct_edn);
    if (!value_text_equals(map_get(direct_value, ":user/name"), "Ada") ||
        !value_text_equals(map_get(map_get(direct_value, ":user/friend"), ":user/name"), "Grace")) {
        fprintf(stderr, "unexpected direct pull output\n");
        vev_value_handle_free(direct_pull);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(direct_pull);

    vev_value_handle_t lookup_pull =
        vev_pull_lookup_ref_string_edn(pull_db, "[:user/name]", ":user/email", "ada@example.com");
    if (lookup_pull == NULL) {
        fprintf(stderr, "failed lookup-ref pull API\n");
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_t lookup_value = vev_value_handle_value(lookup_pull);
    if (!value_text_equals(map_get(lookup_value, ":user/name"), "Ada")) {
        fprintf(stderr, "unexpected lookup-ref pull output\n");
        vev_value_handle_free(lookup_pull);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(lookup_pull);

    unsigned long long pull_many_ids[] = {1, 2};
    vev_value_handle_t many_pull =
        vev_pull_many_edn(pull_db, "[:user/name]", pull_many_ids, 2);
    if (many_pull == NULL) {
        fprintf(stderr, "failed pull-many API\n");
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_t many_value = vev_value_handle_value(many_pull);
    if (vev_value_kind(many_value) != VEV_VALUE_VECTOR ||
        vev_value_item_count(many_value) != 2 ||
        !value_text_equals(map_get(vev_value_item(many_value, 0), ":user/name"), "Ada") ||
        !value_text_equals(map_get(vev_value_item(many_value, 1), ":user/name"), "Grace")) {
        const char *many_edn = vev_value_handle_edn(many_pull);
        fprintf(stderr, "unexpected pull-many output: %s\n", many_edn);
        vev_string_free(many_edn);
        vev_value_handle_free(many_pull);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(many_pull);

    const char *pull_many_emails[] = {"ada@example.com", "missing@example.com", "grace@example.com"};
    vev_value_handle_t many_lookup_pull =
        vev_pull_many_lookup_ref_string_edn(pull_db, "[:user/name]", ":user/email", pull_many_emails, 3);
    if (many_lookup_pull == NULL) {
        fprintf(stderr, "failed pull-many lookup-ref API\n");
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_t many_lookup_value = vev_value_handle_value(many_lookup_pull);
    if (vev_value_kind(many_lookup_value) != VEV_VALUE_VECTOR ||
        vev_value_item_count(many_lookup_value) != 3 ||
        !value_text_equals(map_get(vev_value_item(many_lookup_value, 0), ":user/name"), "Ada") ||
        vev_value_kind(vev_value_item(many_lookup_value, 1)) != VEV_VALUE_NIL ||
        !value_text_equals(map_get(vev_value_item(many_lookup_value, 2), ":user/name"), "Grace")) {
        const char *many_lookup_edn = vev_value_handle_edn(many_lookup_pull);
        fprintf(stderr, "unexpected pull-many lookup-ref output: %s\n", many_lookup_edn);
        vev_string_free(many_lookup_edn);
        vev_value_handle_free(many_lookup_pull);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(many_lookup_pull);

    vev_entity_t ada_entity = vev_db_entity(pull_db, 1);
    if (ada_entity == NULL ||
        !vev_entity_found(ada_entity) ||
        vev_entity_id(ada_entity) != 1 ||
        !vev_entity_contains(ada_entity, ":user/name")) {
        fprintf(stderr, "unexpected entity handle state\n");
        if (ada_entity != NULL) vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_t entity_name = vev_entity_get(ada_entity, ":user/name");
    if (entity_name == NULL ||
        !value_text_equals(vev_value_handle_value(entity_name), "Ada")) {
        fprintf(stderr, "unexpected entity get output\n");
        if (entity_name != NULL) vev_value_handle_free(entity_name);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(entity_name);

    vev_value_handle_t entity_values = vev_entity_values(ada_entity, ":user/name");
    vev_value_t entity_values_value = entity_values == NULL ? NULL : vev_value_handle_value(entity_values);
    if (entity_values == NULL ||
        vev_value_kind(entity_values_value) != VEV_VALUE_VECTOR ||
        vev_value_item_count(entity_values_value) != 1 ||
        !value_text_equals(vev_value_item(entity_values_value, 0), "Ada")) {
        fprintf(stderr, "unexpected entity values output\n");
        if (entity_values != NULL) vev_value_handle_free(entity_values);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(entity_values);

    vev_entity_t friend_entity = vev_entity_ref(ada_entity, ":user/friend");
    if (friend_entity == NULL ||
        !vev_entity_found(friend_entity) ||
        vev_entity_id(friend_entity) != 2) {
        fprintf(stderr, "unexpected entity ref output\n");
        if (friend_entity != NULL) vev_entity_free(friend_entity);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_entity_free(friend_entity);

    unsigned long long expected_friend_ids[] = {2};
    vev_u64_array_t friend_refs = vev_entity_refs(ada_entity, ":user/friend");
    if (!expect_u64_array("entity refs", friend_refs, expected_friend_ids, 1)) {
        if (friend_refs != NULL) vev_u64_array_free(friend_refs);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_u64_array_free(friend_refs);

    vev_entity_t lookup_entity =
        vev_db_entity_lookup_ref_string(pull_db, ":user/email", "ada@example.com");
    if (lookup_entity == NULL ||
        !vev_entity_found(lookup_entity) ||
        vev_entity_id(lookup_entity) != 1) {
        fprintf(stderr, "unexpected lookup-ref entity output\n");
        if (lookup_entity != NULL) vev_entity_free(lookup_entity);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_entity_free(lookup_entity);

    vev_value_handle_t touched = vev_entity_touch(ada_entity);
    vev_value_t touched_value = touched == NULL ? NULL : vev_value_handle_value(touched);
    if (touched == NULL ||
        !value_text_equals(map_get(touched_value, ":user/name"), "Ada")) {
        fprintf(stderr, "unexpected entity touch output\n");
        if (touched != NULL) vev_value_handle_free(touched);
        vev_entity_free(ada_entity);
        vev_db_release(pull_db);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_value_handle_free(touched);
    vev_entity_free(ada_entity);
    vev_db_release(pull_db);

    vev_prepared_pull_pattern_t prepared_pull_pattern =
        vev_prepare_pull_pattern_edn("[:user/name {:user/friend [:user/name]}]");
    if (prepared_pull_pattern == NULL || !vev_prepared_pull_pattern_ok(prepared_pull_pattern)) {
        fprintf(stderr, "failed to prepare direct pull pattern\n");
        if (prepared_pull_pattern != NULL) vev_prepared_pull_pattern_free(prepared_pull_pattern);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const char *prepared_pull_pattern_edn = vev_prepared_pull_pattern_edn(prepared_pull_pattern);
    if (strstr(prepared_pull_pattern_edn, ":pattern") == NULL ||
        strstr(prepared_pull_pattern_edn, ":attr") == NULL ||
        strstr(prepared_pull_pattern_edn, ":nested-count") == NULL) {
        fprintf(stderr, "unexpected prepared pull pattern EDN: %s\n", prepared_pull_pattern_edn);
        vev_string_free(prepared_pull_pattern_edn);
        vev_prepared_pull_pattern_free(prepared_pull_pattern);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("prepared pull pattern edn: %s\n", prepared_pull_pattern_edn);
    vev_string_free(prepared_pull_pattern_edn);
    vev_prepared_pull_pattern_free(prepared_pull_pattern);

    vev_prepared_query_t pull_pattern_query =
        vev_prepare_query_edn("[:find (pull ?e ?pattern) :in $ ?pattern ?name :where [?e :user/name ?name]]");
    if (pull_pattern_query == NULL) {
        fprintf(stderr, "failed to prepare pull-pattern statement query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t pull_pattern_stmt = vev_stmt_create(pull_pattern_query);
    if (pull_pattern_stmt == NULL ||
        !vev_stmt_bind_pull_pattern_edn(pull_pattern_stmt, "[:user/name {:user/friend [:user/name]}]") ||
        !vev_stmt_bind_string(pull_pattern_stmt, "Ada")) {
        fprintf(stderr, "failed to bind pull-pattern statement\n");
        if (pull_pattern_stmt != NULL) vev_stmt_free(pull_pattern_stmt);
        vev_prepared_query_free(pull_pattern_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t pull_pattern_result = vev_query_stmt_result(conn, pull_pattern_stmt);
    int pull_pattern_rows = result_row_count_or_error("stmt-pull-pattern", pull_pattern_result);
    int pull_pattern_count = vev_result_pull_count(pull_pattern_result, 0);
    vev_value_t bound_pull = vev_result_pull(pull_pattern_result, 0, 0);
    if (pull_pattern_rows != 1 ||
        pull_pattern_count != 1 ||
        !value_text_equals(map_get(bound_pull, ":user/name"), "Ada") ||
        !value_text_equals(map_get(map_get(bound_pull, ":user/friend"), ":user/name"), "Grace")) {
        const char *bound_edn = vev_value_edn(bound_pull);
        fprintf(stderr, "unexpected pull-pattern statement output: %s\n", bound_edn);
        vev_string_free(bound_edn);
        vev_result_free(pull_pattern_result);
        vev_stmt_free(pull_pattern_stmt);
        vev_prepared_query_free(pull_pattern_query);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_free(pull_pattern_result);
    vev_stmt_free(pull_pattern_stmt);
    vev_prepared_query_free(pull_pattern_query);

    vev_conn_t right_conn = vev_conn_open_memory();
    if (right_conn == NULL) {
        fprintf(stderr, "failed to open right source connection\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    print_and_free(
        "right-source-tx",
        vev_transact_edn(
            right_conn,
            "[{:db/id 1 :user/name \"Ada Right\"}"
            " {:db/id 2 :user/name \"Grace Right\"}]"));
    vev_db_t left_source = vev_conn_db(conn);
    vev_db_t right_source = vev_conn_db(right_conn);
    const char *source_names[] = {"$left", "$right"};
    vev_prepared_query_t source_query =
        vev_prepare_query_edn_with_sources(
            "[:find ?e ?left-name ?right-name"
            " :in $left $right [?e ...]"
            " :where [$left ?e :user/name ?left-name]"
            "        [$right ?e :user/name ?right-name]]",
            source_names,
            2);
    vev_stmt_t source_stmt = source_query == NULL ? NULL : vev_stmt_create(source_query);
    unsigned long long source_ids[] = {1, 2};
    if (left_source == NULL ||
        right_source == NULL ||
        source_query == NULL ||
        source_stmt == NULL ||
        !vev_stmt_bind_db_source(source_stmt, "$left", left_source) ||
        !vev_stmt_bind_db_source(source_stmt, "$right", right_source) ||
        !vev_stmt_bind_entity_collection(source_stmt, source_ids, 2)) {
        fprintf(stderr, "failed to bind source statement\n");
        if (source_stmt != NULL) vev_stmt_free(source_stmt);
        if (source_query != NULL) vev_prepared_query_free(source_query);
        if (left_source != NULL) vev_db_release(left_source);
        if (right_source != NULL) vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_t source_result = vev_query_stmt_result(conn, source_stmt);
    int source_rows = result_row_count_or_error("stmt-db-sources", source_result);
    vev_value_t source_left_name = vev_result_value(source_result, 0, 1);
    vev_value_t source_right_name = vev_result_value(source_result, 0, 2);
    printf("stmt-db-sources rows: %d\n", source_rows);
    if (source_rows != 2 ||
        !value_text_equals(source_left_name, "Ada") ||
        !value_text_equals(source_right_name, "Ada Right")) {
        fprintf(stderr, "unexpected DB source statement output\n");
        vev_result_free(source_result);
        vev_stmt_free(source_stmt);
        vev_prepared_query_free(source_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_result_free(source_result);
    vev_stmt_free(source_stmt);
    vev_prepared_query_free(source_query);

    vev_prepared_query_t source_batch_query =
        vev_prepare_query_edn_with_sources(
            "[:find ?right-name"
            " :in $left $right [?e ...]"
            " :where [$left ?e :user/name ?left-name]"
            "        [$right ?e :user/name ?right-name]]",
            source_names,
            2);
    vev_stmt_t source_batch_stmt = source_batch_query == NULL ? NULL : vev_stmt_create(source_batch_query);
    if (source_batch_query == NULL ||
        source_batch_stmt == NULL ||
        !vev_stmt_bind_db_source(source_batch_stmt, "$left", left_source) ||
        !vev_stmt_bind_db_source(source_batch_stmt, "$right", right_source) ||
        !vev_stmt_bind_entity_collection(source_batch_stmt, source_ids, 2)) {
        fprintf(stderr, "failed to bind source statement column batch\n");
        if (source_batch_stmt != NULL) vev_stmt_free(source_batch_stmt);
        if (source_batch_query != NULL) vev_prepared_query_free(source_batch_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t source_batch = vev_query_stmt_column_batch(conn, source_batch_stmt);
    if (source_batch == NULL ||
        vev_column_batch_kind(source_batch) != VEV_COLUMN_BATCH_STRING ||
        vev_column_batch_count(source_batch) != 2) {
        fprintf(stderr, "unexpected source statement column batch shape\n");
        if (source_batch != NULL) vev_column_batch_free(source_batch);
        vev_stmt_free(source_batch_stmt);
        vev_prepared_query_free(source_batch_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const void *const *source_batch_strings = vev_column_batch_string_data_array(source_batch);
    const int *source_batch_lengths = vev_column_batch_string_lengths_data(source_batch);
    if (!bytes_equal(source_batch_strings[0], source_batch_lengths[0], "Ada Right") ||
        !bytes_equal(source_batch_strings[1], source_batch_lengths[1], "Grace Right")) {
        fprintf(stderr, "unexpected source statement column batch contents\n");
        vev_column_batch_free(source_batch);
        vev_stmt_free(source_batch_stmt);
        vev_prepared_query_free(source_batch_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("stmt-db-sources column-batch kind=%d rows=%d\n", vev_column_batch_kind(source_batch), vev_column_batch_count(source_batch));
    vev_column_batch_free(source_batch);
    vev_stmt_free(source_batch_stmt);
    vev_prepared_query_free(source_batch_query);

    vev_prepared_query_t source_triple_query =
        vev_prepare_query_edn_with_sources(
            "[:find ?e ?right-name ?age"
            " :in $left $right [?e ...]"
            " :where [$right ?e :user/name ?right-name]"
            "        [$left ?e :user/age ?age]]",
            source_names,
            2);
    vev_stmt_t source_triple_stmt = source_triple_query == NULL ? NULL : vev_stmt_create(source_triple_query);
    if (source_triple_query == NULL ||
        source_triple_stmt == NULL ||
        !vev_stmt_bind_db_source(source_triple_stmt, "$left", left_source) ||
        !vev_stmt_bind_db_source(source_triple_stmt, "$right", right_source) ||
        !vev_stmt_bind_entity_collection(source_triple_stmt, source_ids, 2)) {
        fprintf(stderr, "failed to bind source statement triple column batch\n");
        if (source_triple_stmt != NULL) vev_stmt_free(source_triple_stmt);
        if (source_triple_query != NULL) vev_prepared_query_free(source_triple_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_column_batch_t source_triple = vev_query_stmt_column_batch(conn, source_triple_stmt);
    if (source_triple == NULL ||
        vev_column_batch_kind(source_triple) != VEV_COLUMN_BATCH_ENTITY_STRING_INT ||
        vev_column_batch_count(source_triple) != 2) {
        fprintf(stderr, "unexpected source statement triple column batch shape\n");
        if (source_triple != NULL) vev_column_batch_free(source_triple);
        vev_stmt_free(source_triple_stmt);
        vev_prepared_query_free(source_triple_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    const unsigned long long *source_triple_entities = vev_column_batch_entities_data(source_triple);
    const long long *source_triple_ints = vev_column_batch_ints_data(source_triple);
    const void *const *source_triple_strings = vev_column_batch_string_data_array(source_triple);
    const int *source_triple_lengths = vev_column_batch_string_lengths_data(source_triple);
    if (source_triple_entities[0] != 1 ||
        source_triple_ints[0] != 37 ||
        !bytes_equal(source_triple_strings[0], source_triple_lengths[0], "Ada Right") ||
        source_triple_entities[1] != 2 ||
        source_triple_ints[1] != 41 ||
        !bytes_equal(source_triple_strings[1], source_triple_lengths[1], "Grace Right")) {
        fprintf(stderr, "unexpected source statement triple column batch contents\n");
        vev_column_batch_free(source_triple);
        vev_stmt_free(source_triple_stmt);
        vev_prepared_query_free(source_triple_query);
        vev_db_release(left_source);
        vev_db_release(right_source);
        vev_conn_close(right_conn);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    printf("stmt-db-sources triple column-batch kind=%d rows=%d\n", vev_column_batch_kind(source_triple), vev_column_batch_count(source_triple));
    vev_column_batch_free(source_triple);
    vev_stmt_free(source_triple_stmt);
    vev_prepared_query_free(source_triple_query);

    vev_db_release(left_source);
    vev_db_release(right_source);
    vev_conn_close(right_conn);

    vev_prepared_query_t all_emails =
        vev_prepare_query_edn("[:find ?e ?email :where [?e :user/email ?email]]");
    if (all_emails == NULL) {
        fprintf(stderr, "failed to prepare snapshot query\n");
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }

    vev_db_t snapshot = vev_conn_db(conn);
    if (snapshot == NULL) {
        fprintf(stderr, "failed to retain DB snapshot\n");
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }
    vev_db_t retained_snapshot = vev_db_retain(snapshot);
    vev_db_release(snapshot);
    snapshot = retained_snapshot;
    if (snapshot == NULL) {
        fprintf(stderr, "failed to retain DB snapshot copy\n");
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        vev_conn_close(conn);
        return 1;
    }

    print_and_free(
        "tx-after-snapshot",
        vev_transact_edn(
            conn,
            "[{:db/id 3 :user/name \"Alan\" :user/email \"alan@example.com\"}]"));

    vev_result_t current = vev_query_prepared_result_with_inputs(conn, all_emails, "[]");
    int current_rows = result_row_count_or_error("current-db", current);
    printf("current-db rows: %d\n", current_rows);
    vev_result_free(current);

    vev_conn_close(conn);
    conn = NULL;

    vev_result_t old = vev_query_db_prepared_result_with_inputs(snapshot, all_emails, "[]");
    int old_rows = result_row_count_or_error("snapshot-db", old);
    printf("snapshot-db rows: %d\n", old_rows);
    vev_result_free(old);

    const char *old_edn = vev_query_db_prepared_with_inputs(snapshot, all_emails, "[]");
    if (old_edn == NULL || strstr(old_edn, "ada@example.com") == NULL || strstr(old_edn, "alan@example.com") != NULL) {
        fprintf(stderr, "unexpected snapshot DB EDN result: %s\n", old_edn ? old_edn : "null");
        if (old_edn != NULL) vev_string_free(old_edn);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_string_free(old_edn);

    if (current_rows != 3 || old_rows != 2) {
        fprintf(stderr, "unexpected snapshot row counts\n");
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    vev_prepared_query_t barbara_query =
        vev_prepare_query_edn("[:find ?e :where [?e :user/name \"Barbara\"]]");
    vev_prepared_query_t dorothy_query =
        vev_prepare_query_edn("[:find ?e :where [?e :user/name \"Dorothy\"]]");
    if (barbara_query == NULL || dorothy_query == NULL) {
        fprintf(stderr, "failed to prepare DB value queries\n");
        if (barbara_query != NULL) vev_prepared_query_free(barbara_query);
        if (dorothy_query != NULL) vev_prepared_query_free(dorothy_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    vev_tx_report_t with_report =
        vev_with_edn_report(snapshot, "[{:db/id 4 :user/name \"Barbara\"}]");
    print_and_free("with-db", vev_tx_report_edn(with_report));
    if (!tx_report_ok_or_error("with-db", with_report)) {
        vev_tx_report_free(with_report);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_db_t report_before = vev_tx_report_db_before(with_report);
    vev_db_t report_after = vev_tx_report_db_after(with_report);
    if (report_before == NULL || report_after == NULL) {
        fprintf(stderr, "with report did not expose db-before/db-after\n");
        if (report_before != NULL) vev_db_release(report_before);
        if (report_after != NULL) vev_db_release(report_after);
        vev_tx_report_free(with_report);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_result_t report_before_barbara =
        vev_query_db_prepared_result_with_inputs(report_before, barbara_query, "[]");
    vev_result_t report_after_barbara =
        vev_query_db_prepared_result_with_inputs(report_after, barbara_query, "[]");
    int report_before_rows =
        result_row_count_or_error("report-before-barbara", report_before_barbara);
    int report_after_rows =
        result_row_count_or_error("report-after-barbara", report_after_barbara);
    vev_result_free(report_before_barbara);
    vev_result_free(report_after_barbara);
    vev_db_release(report_before);
    vev_db_release(report_after);
    if (report_before_rows != 0 || report_after_rows != 1) {
        fprintf(stderr, "unexpected with report db-before/db-after rows: before=%d after=%d\n",
                report_before_rows, report_after_rows);
        vev_tx_report_free(with_report);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_tx_report_free(with_report);

    vev_tx_fn_registry_t snapshot_tx_fns = vev_tx_fn_registry_create();
    if (snapshot_tx_fns == NULL ||
        !vev_tx_fn_registry_register_edn(snapshot_tx_fns, ":mark-seen", mark_seen_tx_fn, NULL)) {
        fprintf(stderr, "failed to register snapshot transaction callback\n");
        if (snapshot_tx_fns != NULL) {
            vev_tx_fn_registry_free(snapshot_tx_fns);
        }
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_tx_report_t snapshot_tx_fn_report =
        vev_with_edn_report_with_tx_fns(
            snapshot,
            "[[:db.fn/call :mark-seen 1 \"from-with-c\"]]",
            snapshot_tx_fns);
    const char *snapshot_tx_fn_edn = vev_tx_report_edn(snapshot_tx_fn_report);
    printf("with-tx-fn-callback: %s\n", snapshot_tx_fn_edn);
    if (!tx_report_ok_or_error("with-tx-fn-callback", snapshot_tx_fn_report) ||
        strstr(snapshot_tx_fn_edn, "from-with-c") == NULL) {
        fprintf(stderr, "snapshot transaction callback did not apply returned tx-data\n");
        vev_string_free(snapshot_tx_fn_edn);
        vev_tx_report_free(snapshot_tx_fn_report);
        vev_tx_fn_registry_free(snapshot_tx_fns);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    vev_string_free(snapshot_tx_fn_edn);
    vev_tx_report_free(snapshot_tx_fn_report);
    vev_tx_fn_registry_free(snapshot_tx_fns);

    vev_db_t next_db = vev_db_with_edn(snapshot, "[{:db/id 4 :user/name \"Barbara\"}]");
    if (next_db == NULL) {
        fprintf(stderr, "failed to create DB value with tx data\n");
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    vev_result_t source_barbara = vev_query_db_prepared_result_with_inputs(snapshot, barbara_query, "[]");
    vev_result_t next_barbara = vev_query_db_prepared_result_with_inputs(next_db, barbara_query, "[]");
    int source_barbara_rows = result_row_count_or_error("source-barbara", source_barbara);
    int next_barbara_rows = result_row_count_or_error("next-barbara", next_barbara);
    vev_result_free(source_barbara);
    vev_result_free(next_barbara);
    if (source_barbara_rows != 0 || next_barbara_rows != 1) {
        fprintf(stderr, "unexpected db-with rows: source=%d next=%d\n", source_barbara_rows, next_barbara_rows);
        vev_db_release(next_db);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    vev_conn_t derived = vev_conn_from_db(next_db);
    if (derived == NULL) {
        fprintf(stderr, "failed to create derived connection\n");
        vev_db_release(next_db);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }
    print_and_free(
        "derived-tx",
        vev_transact_edn(derived, "[{:db/id 5 :user/name \"Dorothy\"}]"));
    vev_result_t derived_barbara = vev_query_prepared_result_with_inputs(derived, barbara_query, "[]");
    vev_result_t derived_dorothy = vev_query_prepared_result_with_inputs(derived, dorothy_query, "[]");
    int derived_barbara_rows = result_row_count_or_error("derived-barbara", derived_barbara);
    int derived_dorothy_rows = result_row_count_or_error("derived-dorothy", derived_dorothy);
    vev_result_free(derived_barbara);
    vev_result_free(derived_dorothy);
    vev_conn_close(derived);
    if (derived_barbara_rows != 1 || derived_dorothy_rows != 1) {
        fprintf(stderr, "unexpected derived connection rows\n");
        vev_db_release(next_db);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    if (!run_sqlite_smoke(all_emails)) {
        vev_db_release(next_db);
        vev_prepared_query_free(dorothy_query);
        vev_prepared_query_free(barbara_query);
        vev_db_release(snapshot);
        vev_prepared_query_free(all_emails);
        vev_stmt_free(stmt);
        vev_prepared_query_free(query);
        return 1;
    }

    vev_db_release(next_db);
    vev_prepared_query_free(dorothy_query);
    vev_prepared_query_free(barbara_query);
    vev_db_release(snapshot);
    vev_prepared_query_free(all_emails);

    vev_stmt_free(stmt);
    vev_prepared_query_free(query);
    if (conn != NULL) {
        vev_conn_close(conn);
    }
    return 0;
}
