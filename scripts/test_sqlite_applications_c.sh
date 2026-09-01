#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/test-sqlite-applications-c"
DB="$BUILD_DIR/app.sqlite"
BIN="$BUILD_DIR/sqlite-applications-smoke"

case "$(uname -s)" in
  Darwin|Linux)
    LINK_ARGS=(-L"$ROOT/build/lib" -lvev -Wl,-rpath,"$ROOT/build/lib")
    ;;
  MINGW*|MSYS*|CYGWIN*)
    BIN="$BIN.exe"
    LINK_ARGS=("$ROOT/build/lib/vev.lib")
    ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

mkdir -p "$BUILD_DIR"
rm -f "$DB" "$DB-shm" "$DB-wal"
"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$ROOT/include" \
  "$ROOT/clients/c/sqlite_applications_smoke.c" \
  "${LINK_ARGS[@]}" \
  -o "$BIN"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PATH="$ROOT/build/lib:$PATH" "$BIN" "$DB" ;;
  *) "$BIN" "$DB" ;;
esac
