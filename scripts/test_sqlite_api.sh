#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_PATH="$("$ROOT/scripts/build_native_library.sh" --if-needed)"
LIB_DIR="$(dirname "$LIB_PATH")"
BUILD_DIR="$ROOT/build/sqlite-api-test"
BIN="$BUILD_DIR/sqlite-smoke"
DB="$BUILD_DIR/application.sqlite"
VEV_DB="$BUILD_DIR/application.vev"

mkdir -p "$BUILD_DIR"
rm -f \
  "$DB" "$DB-shm" "$DB-wal" \
  "$VEV_DB" "$VEV_DB-shm" "$VEV_DB-wal"

case "$(uname -s)" in
  Darwin)
    RPATH="-Wl,-rpath,$LIB_DIR"
    ;;
  Linux)
    RPATH="-Wl,-rpath,$LIB_DIR"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    RPATH=""
    BIN="$BIN.exe"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

"${CC:-cc}" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$ROOT/include" \
  "$ROOT/clients/c/sqlite_smoke.c" \
  -L"$LIB_DIR" \
  $RPATH \
  -lvev \
  -o "$BIN"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    PATH="$LIB_DIR:$PATH" "$BIN" "$DB" "$VEV_DB"
    ;;
  *)
    "$BIN" "$DB" "$VEV_DB"
    ;;
esac
