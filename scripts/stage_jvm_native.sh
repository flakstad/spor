#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${VEV_LIB_DIR:-$ROOT/build/lib}"
OUT_DIR="${VEV_JVM_NATIVE_DIR:-$ROOT/build/jvm-native}"

case "$(uname -s)" in
  Darwin)
    OS="darwin"
    LIB_NAME="libvev.dylib"
    ;;
  Linux)
    OS="linux"
    LIB_NAME="libvev.so"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS="windows"
    LIB_NAME="vev.dll"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64)
    ARCH="aarch64"
    ;;
  x86_64|amd64)
    ARCH="x86_64"
    ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

SOURCE="$LIB_DIR/$LIB_NAME"
TARGET_DIR="$OUT_DIR/com/vevdb/native/$OS-$ARCH"
TARGET="$TARGET_DIR/$LIB_NAME"

if [[ ! -f "$SOURCE" ]]; then
  echo "missing native library: $SOURCE" >&2
  echo "run scripts/build_c_abi.sh first, or set VEV_LIB_DIR" >&2
  exit 1
fi

"$ROOT/scripts/check_self_contained_native.sh" "$SOURCE" >/dev/null

mkdir -p "$TARGET_DIR"
cp "$SOURCE" "$TARGET"

echo "$TARGET"
