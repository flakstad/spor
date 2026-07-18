#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${1:-$ROOT/build}"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib" ;;
  Linux) LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [[ "$PREFIX" == "$ROOT/build" &&
      (! -f "$PREFIX/lib/$LIB_NAME" || ! -f "$PREFIX/lib/pkgconfig/vev.pc") ]]; then
  "$ROOT/scripts/build_c_abi.sh"
fi
if [[ ! -f "$PREFIX/lib/$LIB_NAME" || ! -f "$PREFIX/include/vev.h" ]]; then
  echo "missing C package under $PREFIX" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-c-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/smoke.c" <<'EOF'
#include "vev.h"
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

static void remove_file(const char *path) {
#ifdef _WIN32
    DeleteFileA(path);
#else
    unlink(path);
#endif
}

static void remove_store(const char *path) {
    char wal[512];
    char shm[512];
    snprintf(wal, sizeof(wal), "%s-wal", path);
    snprintf(shm, sizeof(shm), "%s-shm", path);
    remove_file(path);
    remove_file(wal);
    remove_file(shm);
}

int main(void) {
    vev_conn_t conn = vev_conn_open_memory();
    if (!conn) {
        fprintf(stderr, "failed to open Vev connection\n");
        return 1;
    }

    const char *tx = vev_transact_edn(conn, "[{:db/id 1 :user/name \"Ada\"}]");
    if (!tx || !strstr(tx, ":ok true")) {
        fprintf(stderr, "unexpected tx: %s\n", tx ? tx : "<null>");
        if (tx) vev_string_free(tx);
        vev_conn_close(conn);
        return 1;
    }
    vev_string_free(tx);

    const char *result = vev_query_edn(conn, "[:find ?name :where [?e :user/name ?name]]");
    if (!result || !strstr(result, "\"Ada\"")) {
        fprintf(stderr, "unexpected query result: %s\n", result ? result : "<null>");
        if (result) vev_string_free(result);
        vev_conn_close(conn);
        return 1;
    }
    vev_string_free(result);
    vev_conn_close(conn);

    const char *store = "tmp.vev.c-package.sqlite";
    remove_store(store);
    vev_connection_t durable = vev_connect(store);
    if (!durable || !vev_connection_ok(durable)) {
        fprintf(stderr, "failed to connect durable Vev store: %s\n",
                durable ? vev_connection_error(durable) : "<null>");
        if (durable) vev_connection_close(durable);
        remove_store(store);
        return 1;
    }
    vev_tx_report_t report = vev_connection_transact_edn_report(
        durable,
        "[{:db/id 2 :user/name \"Durable Grace\"}]");
    if (!report) {
        fprintf(stderr, "failed to transact durable store\n");
        vev_connection_close(durable);
        remove_store(store);
        return 1;
    }
    vev_tx_report_free(report);
    vev_connection_close(durable);

    durable = vev_connect(store);
    if (!durable || !vev_connection_ok(durable)) {
        fprintf(stderr, "failed to reopen durable Vev store\n");
        if (durable) vev_connection_close(durable);
        remove_store(store);
        return 1;
    }
    vev_db_t db = vev_connection_db(durable);
    vev_prepared_query_t query = vev_prepare_query_edn("[:find ?name :where [?e :user/name ?name]]");
    vev_result_t rows = vev_query_db_prepared_result_with_inputs(db, query, "[]");
    if (!rows || !vev_result_ok(rows) || vev_result_row_count(rows) != 1) {
        fprintf(stderr, "unexpected durable query result\n");
        if (rows) vev_result_free(rows);
        if (query) vev_prepared_query_free(query);
        if (db) vev_db_release(db);
        vev_connection_close(durable);
        remove_store(store);
        return 1;
    }
    const char *name = vev_result_value_text(rows, 0, 0);
    if (!name || strcmp(name, "Durable Grace") != 0) {
        fprintf(stderr, "unexpected durable row value: %s\n", name ? name : "<null>");
        vev_result_free(rows);
        vev_prepared_query_free(query);
        vev_db_release(db);
        vev_connection_close(durable);
        remove_store(store);
        return 1;
    }
    vev_string_free(name);
    vev_result_free(rows);
    vev_prepared_query_free(query);
    vev_db_release(db);
    vev_connection_close(durable);
    remove_store(store);

    puts(":vev-c-package-ok");
    return 0;
}
EOF

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    clang \
      -I"$PREFIX/include" \
      "$TMP_DIR/smoke.c" \
      "$PREFIX/lib/vev.lib" \
      -o "$TMP_DIR/smoke.exe"
    PATH="$PREFIX/lib:$PATH" "$TMP_DIR/smoke.exe"
    ;;
  *)
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
      clang "$TMP_DIR/smoke.c" \
      $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags --libs vev) \
      -Wl,-rpath,"$PREFIX/lib" \
      -o "$TMP_DIR/smoke"
    "$TMP_DIR/smoke"
    ;;
esac
