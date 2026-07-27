#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$ROOT/build/vevdb" ]]; then
  "$ROOT/scripts/build_cli.sh" >/dev/null
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vevdb-cli-smoke.XXXXXX")"
DB="$TMP_DIR/example.db"
TX_FILE="$TMP_DIR/transactions.edn"
QUERY_FILE="$TMP_DIR/query.edn"
INPUTS_FILE="$TMP_DIR/inputs.edn"
PULL_FILE="$TMP_DIR/pull.edn"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

printf '%s\n' '[{:db/id 1 :user/name "Ada"}]' > "$TX_FILE"
printf '%s\n' '[:find ?name :in $ ?name :where [?e :user/name ?name]]' > "$QUERY_FILE"
printf '%s\n' '["Ada"]' > "$INPUTS_FILE"
printf '%s\n' '[:user/name]' > "$PULL_FILE"

tx="$("$ROOT/build/vevdb" transact "$DB" "$TX_FILE")"
query="$("$ROOT/build/vevdb" query "$DB" "$QUERY_FILE" "$INPUTS_FILE")"
inline_query="$("$ROOT/build/vevdb" query "$DB" '[:find ?name :where [?e :user/name ?name]]')"
pull="$("$ROOT/build/vevdb" pull "$DB" "$PULL_FILE" 1)"
info="$("$ROOT/build/vevdb" info "$DB")"

case "$tx" in *":ok true"*) ;; *) echo "unexpected tx: $tx" >&2; exit 1 ;; esac
case "$query" in *'"Ada"'*) ;; *) echo "unexpected query: $query" >&2; exit 1 ;; esac
case "$inline_query" in *'"Ada"'*) ;; *) echo "unexpected inline query: $inline_query" >&2; exit 1 ;; esac
case "$pull" in *'"Ada"'*) ;; *) echo "unexpected pull: $pull" >&2; exit 1 ;; esac
case "$info" in *":basis-t 4611686018427387904"*":tx-count 1"*) ;; *) echo "unexpected info: $info" >&2; exit 1 ;; esac

echo ":vevdb-cli-ok"
