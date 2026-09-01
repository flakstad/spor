#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_PATH="$("$ROOT/scripts/build_native_library.sh" --if-needed)"
BUILD_DIR="$ROOT/build/sqlite-kvist-test"
BIN="$BUILD_DIR/sqlite-smoke"

mkdir -p "$BUILD_DIR"

kvist build \
  "$ROOT/examples/kvist/sqlite.kvist" \
  --out "$BIN" \
  --generated "$BUILD_DIR/sqlite-smoke.odin"

VEV_LIB="$LIB_PATH" "$BIN"
