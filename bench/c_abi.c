// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "vev.h"

static double now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((double)ts.tv_sec * 1000000.0) + ((double)ts.tv_nsec / 1000.0);
}

static int compare_double(const void *a, const void *b) {
    double left = *(const double *)a;
    double right = *(const double *)b;
    return (left > right) - (left < right);
}

static char *people_tx(int n) {
    size_t cap = (size_t)n * 128 + 128;
    char *out = malloc(cap);
    if (out == NULL) {
        return NULL;
    }

    size_t len = 0;
    len += (size_t)snprintf(
        out + len,
        cap - len,
        "[{:db/id 100 :db/ident :friend}"
        " {:db/id 100 :db/valueType :db.type/ref}");
    for (int i = 1; i <= n; i++) {
        int written = snprintf(
            out + len,
            cap - len,
            " {:db/id %d :email \"user-%d@example.com\" :name \"User %d\" :age %d :friend %d}",
            i,
            i,
            i,
            i % 100,
            i == n ? 1 : i + 1);
        if (written < 0 || (size_t)written >= cap - len) {
            free(out);
            return NULL;
        }
        len += (size_t)written;
    }
    out[len++] = ']';
    out[len] = '\0';
    return out;
}

struct visit_stats {
    int rows;
    int values;
    int pulls;
};

static bool scan_result_visit(void *user, int event, int row, int index, vev_value_t value) {
    (void)row;
    (void)index;
    struct visit_stats *stats = (struct visit_stats *)user;
    if (event == VEV_RESULT_VISIT_ROW_BEGIN) {
        stats->rows++;
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

int main(void) {
    const int n = 300;
    const int warmups = 30;
    const int sample_count = 200;
    const char *query =
        "[:find ?name ?age :in $ ?email :where [?e :email ?email] [?e :name ?name] [?e :age ?age]]";
    const char *inputs = "[\"user-150@example.com\"]";
    const char *many_query =
        "[:find ?e ?name ?age :where [?e :email ?email] [?e :name ?name] [?e :age ?age]]";

    vev_conn_t conn = vev_conn_open_memory();
    if (conn == NULL) {
        fprintf(stderr, "failed to open Vev connection\n");
        return 1;
    }

    char *tx = people_tx(n);
    if (tx == NULL) {
        fprintf(stderr, "failed to build transaction text\n");
        vev_conn_close(conn);
        return 1;
    }

    const char *tx_result = vev_transact_edn(conn, tx);
    vev_string_free(tx_result);
    free(tx);

    vev_prepared_query_t prepared = vev_prepare_query_edn(query);
    if (prepared == NULL) {
        fprintf(stderr, "failed to prepare query\n");
        vev_conn_close(conn);
        return 1;
    }

    vev_stmt_t stmt = vev_stmt_create(prepared);
    if (stmt == NULL) {
        fprintf(stderr, "failed to create statement\n");
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }

    vev_prepared_query_t many_prepared = vev_prepare_query_edn(many_query);
    if (many_prepared == NULL || !vev_prepared_query_ok(many_prepared)) {
        fprintf(stderr, "failed to prepare many-row query\n");
        if (many_prepared != NULL) {
            vev_prepared_query_free(many_prepared);
        }
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }
    vev_stmt_t many_stmt = vev_stmt_create(many_prepared);
    if (many_stmt == NULL) {
        fprintf(stderr, "failed to create many-row statement\n");
        vev_prepared_query_free(many_prepared);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }
    if (!vev_stmt_bind_string(stmt, "user-150@example.com")) {
        fprintf(stderr, "failed to bind statement input\n");
        vev_stmt_free(many_stmt);
        vev_prepared_query_free(many_prepared);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }

    for (int i = 0; i < warmups; i++) {
        const char *result = vev_query_prepared_with_inputs(conn, prepared, inputs);
        vev_string_free(result);
    }

    double *samples = malloc(sizeof(double) * (size_t)sample_count);
    if (samples == NULL) {
        fprintf(stderr, "failed to allocate samples\n");
        vev_stmt_free(many_stmt);
        vev_prepared_query_free(many_prepared);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        const char *result = vev_query_prepared_with_inputs(conn, prepared, inputs);
        double elapsed = now_us() - start;
        vev_string_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=prepared-email-input-text n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        vev_result_t result = vev_query_prepared_result_with_inputs(conn, prepared, inputs);
        vev_result_free(result);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_result_t result = vev_query_prepared_result_with_inputs(conn, prepared, inputs);
        double elapsed = now_us() - start;
        if (!vev_result_ok(result) || vev_result_row_count(result) != 1) {
            fprintf(stderr, "unexpected result handle output\n");
            vev_result_free(result);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_result_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=prepared-email-result n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        vev_result_t result = vev_query_stmt_result(conn, stmt);
        vev_result_free(result);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_result_t result = vev_query_stmt_result(conn, stmt);
        double elapsed = now_us() - start;
        if (!vev_result_ok(result) || vev_result_row_count(result) != 1) {
            fprintf(stderr, "unexpected statement result output\n");
            vev_result_free(result);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_result_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=prepared-email-bound-result n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        vev_result_t result = vev_query_stmt_result(conn, many_stmt);
        vev_result_free(result);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_result_t result = vev_query_stmt_result(conn, many_stmt);
        double elapsed = now_us() - start;
        if (!vev_result_ok(result) || vev_result_row_count(result) != n) {
            fprintf(stderr, "unexpected many-row result output\n");
            vev_result_free(result);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_result_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=many-row-result n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        struct visit_stats stats = {0, 0, 0};
        if (!vev_query_stmt_visit(conn, many_stmt, scan_result_visit, &stats)) {
            fprintf(stderr, "failed to stream many-row warmup\n");
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
    }

    for (int i = 0; i < sample_count; i++) {
        struct visit_stats stats = {0, 0, 0};
        double start = now_us();
        bool ok = vev_query_stmt_visit(conn, many_stmt, scan_result_visit, &stats);
        double elapsed = now_us() - start;
        if (!ok || stats.rows != n || stats.values != n * 3 || stats.pulls != 0) {
            fprintf(stderr, "unexpected many-row visitor output\n");
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=many-row-scan n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    unsigned long long pull_ids[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    const int pull_count = (int)(sizeof(pull_ids) / sizeof(pull_ids[0]));
    const char *pull_pattern = "[:name {:friend [:name]}]";
    for (int i = 0; i < warmups; i++) {
        vev_db_t pull_db = vev_conn_db(conn);
        vev_value_handle_t handle = vev_pull_many_edn(pull_db, pull_pattern, pull_ids, pull_count);
        vev_value_handle_free(handle);
        vev_db_release(pull_db);
    }

    for (int i = 0; i < sample_count; i++) {
        vev_db_t pull_db = vev_conn_db(conn);
        double start = now_us();
        vev_value_handle_t handle = vev_pull_many_edn(pull_db, pull_pattern, pull_ids, pull_count);
        double elapsed = now_us() - start;
        vev_value_t value = vev_value_handle_value(handle);
        if (vev_value_kind(value) != VEV_VALUE_VECTOR || vev_value_item_count(value) != pull_count) {
            fprintf(stderr, "unexpected pull-many output\n");
            vev_value_handle_free(handle);
            vev_db_release(pull_db);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_value_handle_free(handle);
        vev_db_release(pull_db);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=pull-many-nested n=%d median_us=%.0f samples=%d\n",
        pull_count,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_db_t snapshot = vev_conn_db(conn);
        double elapsed = now_us() - start;
        vev_db_release(snapshot);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=db-snapshot n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    vev_db_t snapshot = vev_conn_db(conn);
    if (snapshot == NULL) {
        fprintf(stderr, "failed to retain DB snapshot\n");
        free(samples);
        vev_stmt_free(many_stmt);
        vev_prepared_query_free(many_prepared);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }

    for (int i = 0; i < warmups; i++) {
        vev_result_t result = vev_query_db_prepared_result_with_inputs(snapshot, prepared, inputs);
        vev_result_free(result);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_result_t result = vev_query_db_prepared_result_with_inputs(snapshot, prepared, inputs);
        double elapsed = now_us() - start;
        if (!vev_result_ok(result) || vev_result_row_count(result) != 1) {
            fprintf(stderr, "unexpected DB result handle output\n");
            vev_result_free(result);
            vev_db_release(snapshot);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_result_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=prepared-email-db-result n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        vev_result_t result = vev_query_db_stmt_result(snapshot, stmt);
        vev_result_free(result);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_result_t result = vev_query_db_stmt_result(snapshot, stmt);
        double elapsed = now_us() - start;
        if (!vev_result_ok(result) || vev_result_row_count(result) != 1) {
            fprintf(stderr, "unexpected DB statement result output\n");
            vev_result_free(result);
            vev_db_release(snapshot);
            free(samples);
            vev_stmt_free(many_stmt);
            vev_prepared_query_free(many_prepared);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_result_free(result);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=prepared-email-db-bound-result n=%d median_us=%.0f samples=%d\n",
        n,
        samples[sample_count / 2],
        sample_count);

    vev_conn_t empty_conn = vev_conn_open_memory();
    if (empty_conn == NULL) {
        fprintf(stderr, "failed to open empty Vev connection\n");
        vev_db_release(snapshot);
        free(samples);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }
    vev_db_t empty_db = vev_conn_db(empty_conn);
    vev_conn_close(empty_conn);
    if (empty_db == NULL) {
        fprintf(stderr, "failed to retain empty DB snapshot\n");
        vev_db_release(snapshot);
        free(samples);
        vev_stmt_free(stmt);
        vev_prepared_query_free(prepared);
        vev_conn_close(conn);
        return 1;
    }

    const char *tx_text = "[{:db/id 1 :name \"Ada\"}]";
    for (int i = 0; i < warmups; i++) {
        const char *report = vev_with_edn(empty_db, tx_text);
        vev_string_free(report);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        const char *report = vev_with_edn(empty_db, tx_text);
        double elapsed = now_us() - start;
        vev_string_free(report);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=with-tx-report-text n=%d median_us=%.0f samples=%d\n",
        1,
        samples[sample_count / 2],
        sample_count);

    for (int i = 0; i < warmups; i++) {
        vev_tx_report_t report = vev_with_edn_report(empty_db, tx_text);
        vev_tx_report_free(report);
    }

    for (int i = 0; i < sample_count; i++) {
        double start = now_us();
        vev_tx_report_t report = vev_with_edn_report(empty_db, tx_text);
        double elapsed = now_us() - start;
        vev_value_t value = vev_tx_report_value(report);
        if (vev_value_kind(value) != VEV_VALUE_MAP || vev_value_map_count(value) == 0) {
            fprintf(stderr, "unexpected transaction report value\n");
            vev_tx_report_free(report);
            vev_db_release(empty_db);
            vev_db_release(snapshot);
            free(samples);
            vev_stmt_free(stmt);
            vev_prepared_query_free(prepared);
            vev_conn_close(conn);
            return 1;
        }
        vev_tx_report_free(report);
        samples[i] = elapsed;
    }

    qsort(samples, (size_t)sample_count, sizeof(double), compare_double);
    printf(
        "engine=c-abi workload=with-tx-report-value n=%d median_us=%.0f samples=%d\n",
        1,
        samples[sample_count / 2],
        sample_count);

    vev_db_release(empty_db);
    vev_db_release(snapshot);
    free(samples);
    vev_stmt_free(many_stmt);
    vev_prepared_query_free(many_prepared);
    vev_stmt_free(stmt);
    vev_prepared_query_free(prepared);
    vev_conn_close(conn);
    return 0;
}
