#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/test-sqlite-applications-c"
DB="$BUILD_DIR/app.sqlite"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib" ;;
  Linux) LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll" ;;
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
  -L"$ROOT/build/lib" \
  -lvev \
  -Wl,-rpath,"$ROOT/build/lib" \
  -o "$BUILD_DIR/sqlite-applications-smoke"

"$BUILD_DIR/sqlite-applications-smoke" "$DB"
