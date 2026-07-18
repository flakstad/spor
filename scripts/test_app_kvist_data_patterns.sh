#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-app-data-patterns-bin.XXXXXX")"
OUTPUT="$(mktemp "${TMPDIR:-/tmp}/vev-app-data-patterns-output.XXXXXX")"
trap 'rm -f "$BIN" "$OUTPUT"' EXIT

kvist build "$ROOT/src/vev_tests/app_data_patterns_fixture.kvist" --out "$BIN" >/dev/null
"$BIN" success | grep -Fq "app-data-patterns: ok"

expect_error() {
  local mode="$1"
  local expected="$2"

  if bash -c '"$1" "$2"; exit $?' _ "$BIN" "$mode" >"$OUTPUT" 2>&1; then
    echo "expected fixture mode $mode to fail" >&2
    exit 1
  fi
  grep -Fq "$expected" "$OUTPUT"
}

expect_error non-vector "log query must be a vector"
expect_error unnamed "log query requires a named function"
expect_error unsupported "unsupported Vev log query function"
expect_error tx-ids-arity "tx-ids expects log, start, and end arguments"
expect_error tx-ids-range "tx-ids expects integer range arguments"
expect_error tx-data-arity "tx-data expects log and transaction arguments"
expect_error tx-data-negative "transaction id must be non-negative"
expect_error extra-input "log queries currently accept one value input"

echo "app-kvist-data-patterns: ok"
