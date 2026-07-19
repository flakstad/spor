#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-multi-writer-bin.XXXXXX")"
DB="$(mktemp "${TMPDIR:-/tmp}/vev-multi-writer-db.XXXXXX")"
rm -f "$DB"
trap 'rm -f "$BIN" "$DB" "$DB-wal" "$DB-shm"' EXIT

kvist build "$ROOT/src/vev_tests/multi_writer_fixture.kvist" --out "$BIN" >/dev/null
"$BIN" "$DB"

echo "multi-writer-connections: ok"
