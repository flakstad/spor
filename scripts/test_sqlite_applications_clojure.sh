#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/test-sqlite-applications-clojure"
JAVA_OUT="$BUILD_DIR/classes"
DB="$BUILD_DIR/app.sqlite"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib" ;;
  Linux) LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 25 2>/dev/null || true)}"
if [[ -z "$JAVA_HOME" ]]; then
  echo "Java 25 is required" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -rf "$JAVA_OUT"
rm -f "$DB" "$DB-shm" "$DB-wal"
mkdir -p "$JAVA_OUT"
"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

"$JAVA_HOME/bin/javac" \
  --release 25 \
  -d "$JAVA_OUT" \
  "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java" \
  "$ROOT/clients/java/src/main/java/com/vevdb/VevSQLite.java"

JAVA_HOME="$JAVA_HOME" \
PATH="$JAVA_HOME/bin:$PATH" \
clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\"]}" \
  -M \
  "$ROOT/examples/clojure/sqlite_applications.clj" \
  "$ROOT/build/lib/$LIB_NAME" \
  "$DB"
