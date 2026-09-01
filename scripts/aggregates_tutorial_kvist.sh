#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="${1:-$ROOT/build/day-of-datomic/vev-aggregates.sqlite}"

"$ROOT/scripts/aggregates_tutorial_clojure.sh" >/dev/null

OUTPUT="$(mktemp "${TMPDIR:-/tmp}/vev-aggregates-kvist.XXXXXX")"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-aggregates-kvist-bin.XXXXXX")"
trap 'rm -f "$OUTPUT" "$BIN"' EXIT

kvist build "$ROOT/examples/kvist/aggregates_tutorial.kvist" --out "$BIN" >/dev/null
"$BIN" "$STORE" | tee "$OUTPUT"

if grep -q "ok=false" "$OUTPUT"; then
  exit 1
fi

grep -q "source=kvist section=summary ok=true" "$OUTPUT"
