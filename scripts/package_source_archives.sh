#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
OUT_DIR="$ROOT/build/release/source"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

archive() {
  local name="$1"
  shift
  local out="$OUT_DIR/$name-$VERSION.tar.gz"

  git -C "$ROOT" archive \
    --format=tar.gz \
    --prefix="$name-$VERSION/" \
    --output="$out" \
    HEAD \
    -- "$@"
  printf '%s\n' "$out"
}

archive vev-python clients/python
archive vev-rust clients/rust
archive vev-node clients/node
archive vev-go clients/go
archive vev-odin clients/odin
archive vev-kvist src/vev src/vev_app
