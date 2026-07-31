#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/test-sqlite-applications-kvist"
BIN="$BUILD_DIR/sqlite-applications-smoke"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib" ;;
  Linux) LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

mkdir -p "$BUILD_DIR"
"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

kvist build \
  "$ROOT/examples/kvist/sqlite_applications.kvist" \
  --out "$BIN" \
  --generated "$BUILD_DIR/sqlite-applications-smoke.odin"

VEV_LIB="$ROOT/build/lib/$LIB_NAME" "$BIN"
