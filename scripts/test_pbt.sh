#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBT_ROOT="${VEV_PBT_ROOT:-$ROOT/../pbt}"
ODIN_BIN="${VEV_ODIN_BIN:-odin}"

if [[ ! -d "$PBT_ROOT/pbt" ]]; then
  echo "pbt Odin package not found under $PBT_ROOT/pbt" >&2
  echo "Place pbt beside Vev as ../pbt, or set VEV_PBT_ROOT." >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib"; EXE_SUFFIX="" ;;
  Linux) LIB_NAME="libvev.so"; EXE_SUFFIX="" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll"; EXE_SUFFIX=".exe" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [[ "${VEV_SKIP_NATIVE_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null
fi

LIB_PATH="${VEV_LIB:-$ROOT/build/lib/$LIB_NAME}"
if [[ ! -f "$LIB_PATH" ]]; then
  echo "Vev native library not found at $LIB_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-pbt.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

RUNNER="$TMP_DIR/vev-pbt$EXE_SUFFIX"
"$ODIN_BIN" build "$ROOT/test/pbt" \
  -collection:pbt="$PBT_ROOT" \
  -out:"$RUNNER"

VEV_LIB="$LIB_PATH" "$RUNNER" "$@"
