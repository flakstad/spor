#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib"; EXE_SUFFIX="" ;;
  Linux) LIB_NAME="libvev.so"; EXE_SUFFIX="" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll"; EXE_SUFFIX=".exe" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if ! command -v odin >/dev/null 2>&1; then
  echo "odin not found; skipping Odin package smoke"
  exit 0
fi

if [[ ! -f "$ROOT/build/lib/$LIB_NAME" ]]; then
  "$ROOT/scripts/build_c_abi.sh"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-odin-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

odin check "$ROOT/clients/odin/vev" -no-entry-point
mkdir -p "$TMP_DIR/vendor/vev/lib"
cp "$ROOT/clients/odin/vev/doc.odin" "$TMP_DIR/vendor/vev/doc.odin"
cp "$ROOT/clients/odin/vev/vev.odin" "$TMP_DIR/vendor/vev/vev.odin"
cp "$ROOT/build/lib/$LIB_NAME" "$TMP_DIR/vendor/vev/lib/$LIB_NAME"
odin build "$ROOT/clients/odin/example" -out:"$TMP_DIR/vev_odin_example$EXE_SUFFIX"
PATH="$ROOT/build/lib:$PATH" \
  "$TMP_DIR/vev_odin_example$EXE_SUFFIX" \
  "$TMP_DIR/vendor/vev" \
  "$TMP_DIR/example.vev" >/dev/null

odin build "$ROOT/clients/odin" -file -out:"$TMP_DIR/vev_odin_raw_smoke$EXE_SUFFIX"
PATH="$ROOT/build/lib:$PATH" \
  "$TMP_DIR/vev_odin_raw_smoke$EXE_SUFFIX" "$ROOT/build/lib/$LIB_NAME" >/dev/null
echo ":vev-odin-package-ok"
