#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQLITE_VERSION="3530300"
SQLITE_RELEASE_YEAR="2026"
SQLITE_SHA3_256="d45c688a8cb23f68611a894a756a12d7eb6ab6e9e2468ca70adbeab3808b5ab9"
SQLITE_ARCHIVE="sqlite-amalgamation-$SQLITE_VERSION.zip"
SQLITE_URL="https://sqlite.org/$SQLITE_RELEASE_YEAR/$SQLITE_ARCHIVE"
CACHE_DIR="${VEV_SQLITE_CACHE_DIR:-$ROOT/build/vendor/sqlite}"
ARCHIVE_PATH="$CACHE_DIR/$SQLITE_ARCHIVE"
SOURCE_DIR="$CACHE_DIR/sqlite-amalgamation-$SQLITE_VERSION"

case "$(uname -s)" in
  Darwin) PLATFORM="darwin-$(uname -m)"; LIB_NAME="libsqlite3.a"; OBJECT_NAME="sqlite3.o" ;;
  Linux) PLATFORM="linux-$(uname -m)"; LIB_NAME="libsqlite3.a"; OBJECT_NAME="sqlite3.o" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-$(uname -m)"; LIB_NAME="sqlite3.lib"; OBJECT_NAME="sqlite3.obj" ;;
  *) echo "unsupported OS for bundled SQLite: $(uname -s)" >&2; exit 1 ;;
esac

BUILD_DIR="$CACHE_DIR/build/$PLATFORM"
LIB_PATH="$BUILD_DIR/$LIB_NAME"
OBJECT_PATH="$BUILD_DIR/$OBJECT_NAME"

if [[ -f "$LIB_PATH" &&
      ! "$ROOT/scripts/build_sqlite.sh" -nt "$LIB_PATH" &&
      ( ! -f "$ARCHIVE_PATH" || ! "$ARCHIVE_PATH" -nt "$LIB_PATH" ) ]]; then
  printf '%s\n' "$BUILD_DIR"
  exit 0
fi

mkdir -p "$CACHE_DIR" "$BUILD_DIR"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  TEMP_ARCHIVE="$ARCHIVE_PATH.tmp"
  rm -f "$TEMP_ARCHIVE"
  curl --fail --location --retry 3 --output "$TEMP_ARCHIVE" "$SQLITE_URL"
  mv "$TEMP_ARCHIVE" "$ARCHIVE_PATH"
fi

python3 - "$ARCHIVE_PATH" "$SQLITE_SHA3_256" <<'PY'
import hashlib
import pathlib
import sys

archive_name, expected = sys.argv[1:]
archive = pathlib.Path(archive_name)

actual = hashlib.sha3_256(archive.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(
        f"SQLite archive SHA3-256 mismatch: expected {expected}, got {actual}"
    )
PY

if [[ ! -f "$SOURCE_DIR/sqlite3.c" ]]; then
  rm -rf "$SOURCE_DIR"
  unzip -q "$ARCHIVE_PATH" -d "$CACHE_DIR"
fi

COMMON_FLAGS=(
  -O2
  -DSQLITE_ENABLE_FTS5
  -DSQLITE_OMIT_LOAD_EXTENSION
  -DSQLITE_THREADSAFE=1
  -c
  "$SOURCE_DIR/sqlite3.c"
  -o
  "$OBJECT_PATH"
)

case "$(uname -s)" in
  Darwin|Linux)
    clang -fPIC "${COMMON_FLAGS[@]}"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    clang "${COMMON_FLAGS[@]}"
    ;;
esac

if [[ -n "${AR:-}" ]]; then
  ARCHIVER="$AR"
elif command -v llvm-ar >/dev/null 2>&1; then
  ARCHIVER="llvm-ar"
elif command -v ar >/dev/null 2>&1; then
  ARCHIVER="ar"
else
  echo "bundled SQLite build requires llvm-ar or ar" >&2
  exit 1
fi
"$ARCHIVER" rcs "$LIB_PATH" "$OBJECT_PATH"

printf '%s\n' "$BUILD_DIR"
