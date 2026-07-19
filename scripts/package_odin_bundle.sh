#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
OUT_DIR="$ROOT/build/release/odin"
STAGE_DIR="$ROOT/build/release/stage/odin"

case "$(uname -s)" in
  Darwin) OS="darwin"; LIB_NAME="libvev.dylib" ;;
  Linux) OS="linux"; LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
ARCHIVE="$OUT_DIR/vev-odin-$PLATFORM-$VERSION.zip"
BUNDLE_ROOT="vev"

"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p "$OUT_DIR" "$STAGE_DIR/$BUNDLE_ROOT/lib"
cp "$ROOT/clients/odin/vev/doc.odin" "$STAGE_DIR/$BUNDLE_ROOT/doc.odin"
cp "$ROOT/clients/odin/vev/vev.odin" "$STAGE_DIR/$BUNDLE_ROOT/vev.odin"
cp "$ROOT/clients/odin/README.md" "$STAGE_DIR/$BUNDLE_ROOT/README.md"
cp "$ROOT/LICENSE" "$STAGE_DIR/$BUNDLE_ROOT/LICENSE"
cp "$ROOT/build/lib/$LIB_NAME" "$STAGE_DIR/$BUNDLE_ROOT/lib/$LIB_NAME"

rm -f "$ARCHIVE"
jar --create \
  --no-manifest \
  --date="$ARCHIVE_DATE" \
  --file "$ARCHIVE" \
  -C "$STAGE_DIR" "$BUNDLE_ROOT"

printf '%s\n' "$ARCHIVE"
