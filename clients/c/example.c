// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#include "vev.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "example.vev";
    vev_connection_t conn = vev_connect(path);
    if (conn == NULL || !vev_connection_ok(conn)) {
        const char *error = vev_connection_error(conn);
        fprintf(stderr, "VevDB connect failed: %s\n", error ? error : "<null>");
        if (error) {
            vev_string_free(error);
        }
        if (conn) {
            vev_connection_close(conn);
        }
        return 1;
    }

    vev_tx_report_t report = vev_connection_transact_edn_report(
        conn,
        "[{:db/id 1 :person/name \"Ada Lovelace\"}]");
    if (report == NULL) {
        fprintf(stderr, "VevDB transaction failed\n");
        vev_connection_close(conn);
        return 1;
    }
    const char *tx = vev_tx_report_edn(report);
    if (tx == NULL || strstr(tx, ":ok true") == NULL) {
        fprintf(stderr, "VevDB transaction failed: %s\n", tx ? tx : "<null>");
        if (tx) {
            vev_string_free(tx);
        }
        vev_tx_report_free(report);
        vev_connection_close(conn);
        return 1;
    }
    vev_string_free(tx);
    vev_tx_report_free(report);

    const char *rows = vev_connection_query_edn(
        conn,
        "[:find ?name :where [?person :person/name ?name]]");
    if (rows == NULL) {
        fprintf(stderr, "VevDB query failed\n");
        vev_connection_close(conn);
        return 1;
    }
    puts(rows);
    vev_string_free(rows);
    vev_connection_close(conn);
    return 0;
}
