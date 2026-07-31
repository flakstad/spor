#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="$("$ROOT/scripts/package_kvist_bundle.sh")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-kvist-binary.XXXXXX")"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib" ;;
  Linux) LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

unzip -q "$ARCHIVE" -d "$TMP_DIR"
cp "$ROOT/examples/kvist_binary/smoke.kvist" "$TMP_DIR/smoke.kvist"
sed -i.bak 's|"../../clients/kvist"|"./vev/kvist"|' "$TMP_DIR/smoke.kvist"
rm -f "$TMP_DIR/smoke.kvist.bak"
cp "$ROOT/examples/kvist/sqlite.kvist" "$TMP_DIR/sqlite-smoke.kvist"
sed -i.bak \
  's|"../../clients/kvist/sqlite"|"./vev/kvist/sqlite"|' \
  "$TMP_DIR/sqlite-smoke.kvist"
rm -f "$TMP_DIR/sqlite-smoke.kvist.bak"
cp "$ROOT/examples/kvist/sqlite_applications.kvist" \
  "$TMP_DIR/sqlite-applications-smoke.kvist"
sed -i.bak \
  's|"../../clients/kvist/sqlite"|"./vev/kvist/sqlite"|' \
  "$TMP_DIR/sqlite-applications-smoke.kvist"
rm -f "$TMP_DIR/sqlite-applications-smoke.kvist.bak"

(
  cd "$TMP_DIR"
  kvist compile smoke.kvist -o smoke.odin
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      BINARY="$TMP_DIR/smoke.exe"
      WINDOWS_GENERATED="$(cygpath -m "$TMP_DIR/smoke.odin")"
      WINDOWS_BINARY="$(cygpath -m "$BINARY")"
      COLLECTION_ARGS=()
      while IFS= read -r drive; do
        COLLECTION_ARGS+=("-collection:$drive=$drive:/")
      done < <(
        sed -nE 's/^import .*"([A-Za-z]):[\\/].*/\1/p' "$TMP_DIR/smoke.odin" |
          tr '[:lower:]' '[:upper:]' |
          sort -u
      )
      MSYS2_ARG_CONV_EXCL="*" odin build "$WINDOWS_GENERATED" -file \
        "${COLLECTION_ARGS[@]}" \
        "-out:$WINDOWS_BINARY"
      ;;
    *)
      BINARY="$TMP_DIR/smoke"
      odin build smoke.odin -file -out:"$BINARY"
      ;;
  esac
  rm -f \
    vev-kvist-binary-smoke.db \
    vev-kvist-binary-smoke.db-wal \
    vev-kvist-binary-smoke.db-shm
  VEV_LIB="$TMP_DIR/vev/lib/$LIB_NAME" "$BINARY"

  kvist compile sqlite-smoke.kvist -o sqlite-smoke.odin
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      SQLITE_BINARY="$TMP_DIR/sqlite-smoke.exe"
      WINDOWS_SQLITE_GENERATED="$(cygpath -m "$TMP_DIR/sqlite-smoke.odin")"
      WINDOWS_SQLITE_BINARY="$(cygpath -m "$SQLITE_BINARY")"
      MSYS2_ARG_CONV_EXCL="*" odin build "$WINDOWS_SQLITE_GENERATED" -file \
        "${COLLECTION_ARGS[@]}" \
        "-out:$WINDOWS_SQLITE_BINARY"
      ;;
    *)
      SQLITE_BINARY="$TMP_DIR/sqlite-smoke"
      odin build sqlite-smoke.odin -file -out:"$SQLITE_BINARY"
      ;;
  esac
  VEV_LIB="$TMP_DIR/vev/lib/$LIB_NAME" "$SQLITE_BINARY"

  kvist compile sqlite-applications-smoke.kvist \
    -o sqlite-applications-smoke.odin
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      SQLITE_APPLICATIONS_BINARY="$TMP_DIR/sqlite-applications-smoke.exe"
      WINDOWS_SQLITE_APPLICATIONS_GENERATED="$(
        cygpath -m "$TMP_DIR/sqlite-applications-smoke.odin"
      )"
      WINDOWS_SQLITE_APPLICATIONS_BINARY="$(
        cygpath -m "$SQLITE_APPLICATIONS_BINARY"
      )"
      MSYS2_ARG_CONV_EXCL="*" odin build \
        "$WINDOWS_SQLITE_APPLICATIONS_GENERATED" \
        -file \
        "${COLLECTION_ARGS[@]}" \
        "-out:$WINDOWS_SQLITE_APPLICATIONS_BINARY"
      ;;
    *)
      SQLITE_APPLICATIONS_BINARY="$TMP_DIR/sqlite-applications-smoke"
      odin build sqlite-applications-smoke.odin \
        -file \
        -out:"$SQLITE_APPLICATIONS_BINARY"
      ;;
  esac
  VEV_LIB="$TMP_DIR/vev/lib/$LIB_NAME" "$SQLITE_APPLICATIONS_BINARY"
)

echo ":vev-kvist-binary-package-ok"
