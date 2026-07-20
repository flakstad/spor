#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/build/history-api-fixture"

mkdir -p "$ROOT/build"
kvist build "$ROOT/src/vev_tests/history_api_fixture.kvist" --out "$BIN" >/dev/null
"$BIN"
