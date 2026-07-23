#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ABI_VERSION="$(sed -n 's/^#define VEV_ABI_VERSION \([0-9][0-9]*\)u$/\1/p' "$ROOT/include/vev.h")"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
OUT_DIR="$ROOT/build/release/kvist"
STAGE_DIR="$ROOT/build/release/stage/kvist"

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
ARCHIVE="$OUT_DIR/vev-kvist-$PLATFORM-$VERSION.zip"
BUNDLE_ROOT="vev"

"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p \
  "$OUT_DIR" \
  "$STAGE_DIR/$BUNDLE_ROOT/kvist" \
  "$STAGE_DIR/$BUNDLE_ROOT/odin/vev" \
  "$STAGE_DIR/$BUNDLE_ROOT/lib"

cp "$ROOT/clients/kvist/vev.kvist" "$STAGE_DIR/$BUNDLE_ROOT/kvist/vev.kvist"
cp "$ROOT/clients/odin/vev/doc.odin" "$STAGE_DIR/$BUNDLE_ROOT/odin/vev/doc.odin"
cp "$ROOT/clients/odin/vev/vev.odin" "$STAGE_DIR/$BUNDLE_ROOT/odin/vev/vev.odin"
cp "$ROOT/clients/kvist/README.md" "$STAGE_DIR/$BUNDLE_ROOT/README.md"
cp "$ROOT/LICENSE" "$STAGE_DIR/$BUNDLE_ROOT/LICENSE"
cp "$ROOT/build/lib/$LIB_NAME" "$STAGE_DIR/$BUNDLE_ROOT/lib/$LIB_NAME"

cat > "$STAGE_DIR/$BUNDLE_ROOT/manifest.json" <<EOF
{
  "schema_version": 1,
  "version": "$VERSION",
  "abi_version": $ABI_VERSION,
  "platform": "$PLATFORM",
  "git_commit": "$(git -C "$ROOT" rev-parse HEAD)",
  "library": "lib/$LIB_NAME",
  "library_sha256": "$(shasum -a 256 "$ROOT/build/lib/$LIB_NAME" | awk '{print $1}')"
}
EOF

rm -f "$ARCHIVE"
jar --create \
  --no-manifest \
  --date="$ARCHIVE_DATE" \
  --file "$ARCHIVE" \
  -C "$STAGE_DIR" "$BUNDLE_ROOT"

printf '%s\n' "$ARCHIVE"
