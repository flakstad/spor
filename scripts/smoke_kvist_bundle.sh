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
      if (( ${#COLLECTION_ARGS[@]} == 0 )); then
        echo "generated Kvist bundle smoke has no Windows import collections" >&2
        exit 1
      fi
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
    /tmp/vev-kvist-binary-smoke.vev \
    /tmp/vev-kvist-binary-smoke.vev-wal \
    /tmp/vev-kvist-binary-smoke.vev-shm
  VEV_LIB="$TMP_DIR/vev/lib/$LIB_NAME" "$BINARY"
)

echo ":vev-kvist-binary-package-ok"
