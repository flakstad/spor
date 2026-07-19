#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-cross-process-bin.XXXXXX")"
DB="$(mktemp "${TMPDIR:-/tmp}/vev-cross-process-db.XXXXXX")"
READY="$(mktemp "${TMPDIR:-/tmp}/vev-cross-process-ready.XXXXXX")"
rm -f "$DB"
rm -f "$READY"
trap 'rm -f "$BIN" "$DB" "$DB-wal" "$DB-shm" "$READY"' EXIT

kvist build "$ROOT/src/vev_tests/cross_process_fixture.kvist" --out "$BIN" >/dev/null
"$BIN" init "$DB"
"$BIN" watch "$DB" "$READY" &
READER_PID=$!
while [[ ! -f "$READY" ]]; do
  if ! kill -0 "$READER_PID" 2>/dev/null; then
    wait "$READER_PID"
  fi
done
"$BIN" write-loop "$DB"
wait "$READER_PID"
"$BIN" write-a "$DB" &
WRITER_A_PID=$!
"$BIN" write-b "$DB" &
WRITER_B_PID=$!
wait "$WRITER_A_PID"
wait "$WRITER_B_PID"
"$BIN" verify-writers "$DB"
"$BIN" write "$DB"
"$BIN" read "$DB"

echo "cross-process-visibility: ok"
