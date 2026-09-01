#!/usr/bin/env bash

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

CLJ_JAVA_OUT="$JAVA_OUT"
CLJ_SOURCE="$ROOT/clients/clojure/src"
LIB_PATH="$ROOT/build/lib/$LIB_NAME"
RUN_DB="$DB"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    CLJ_JAVA_OUT="$(cygpath -m "$CLJ_JAVA_OUT")"
    CLJ_SOURCE="$(cygpath -m "$CLJ_SOURCE")"
    LIB_PATH="$(cygpath -m "$LIB_PATH")"
    RUN_DB="$(cygpath -m "$RUN_DB")"
    ;;
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
  -Sdeps "{:paths [\"$CLJ_JAVA_OUT\" \"$CLJ_SOURCE\"]}" \
  -M \
  "$ROOT/examples/clojure/sqlite_applications.clj" \
  "$LIB_PATH" \
  "$RUN_DB"
