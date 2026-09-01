#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/examples/c/vev_datomic_semantics_smoke"

"$ROOT/scripts/build_native_library.sh" >/dev/null
mkdir -p "$(dirname "$OUT")"

clang \
  -I"$ROOT/include" \
  "$ROOT/clients/c/datomic_semantics_smoke.c" \
  -L"$ROOT/build/lib" \
  -lvev \
  -Wl,-rpath,"$ROOT/build/lib" \
  -o "$OUT"

"$OUT"
