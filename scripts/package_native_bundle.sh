#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
OUT_DIR="$ROOT/build/release/native"
STAGE_DIR="$ROOT/build/release/stage/native"

case "$(uname -s)" in
  Darwin) OS="darwin"; LIB_NAME="libvev.dylib"; LINK_NAME="" ;;
  Linux) OS="linux"; LIB_NAME="libvev.so"; LINK_NAME="" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; LIB_NAME="vev.dll"; LINK_NAME="vev.lib" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
BUNDLE_ROOT="vev-$VERSION"
ARCHIVE="$OUT_DIR/vev-native-$PLATFORM-$VERSION.zip"

"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p \
  "$OUT_DIR" \
  "$STAGE_DIR/$BUNDLE_ROOT/include" \
  "$STAGE_DIR/$BUNDLE_ROOT/lib/pkgconfig"

cp "$ROOT/include/vev.h" "$STAGE_DIR/$BUNDLE_ROOT/include/vev.h"
cp "$ROOT/build/lib/$LIB_NAME" "$STAGE_DIR/$BUNDLE_ROOT/lib/$LIB_NAME"
if [[ -n "$LINK_NAME" ]]; then
  cp "$ROOT/build/lib/$LINK_NAME" "$STAGE_DIR/$BUNDLE_ROOT/lib/$LINK_NAME"
fi
cp "$ROOT/build/lib/pkgconfig/vev.pc" "$STAGE_DIR/$BUNDLE_ROOT/lib/pkgconfig/vev.pc"
cp "$ROOT/LICENSE" "$STAGE_DIR/$BUNDLE_ROOT/LICENSE"

rm -f "$ARCHIVE"
jar --create \
  --no-manifest \
  --date="$ARCHIVE_DATE" \
  --file "$ARCHIVE" \
  -C "$STAGE_DIR" "$BUNDLE_ROOT"

printf '%s\n' "$ARCHIVE"
