#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
ARCHIVE="${1:-$ROOT/build/release/native/vev-native-$PLATFORM-$VERSION.zip}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-native-package.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$ARCHIVE" ]]; then
  echo "missing native bundle: $ARCHIVE" >&2
  exit 1
fi

(
  cd "$TMP_DIR"
  jar --extract --file "$ARCHIVE"
)

BUNDLE="$TMP_DIR/vev-$VERSION"
"$ROOT/scripts/smoke_c_package.sh" "$BUNDLE"
