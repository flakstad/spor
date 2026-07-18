#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRST="$(mktemp "${TMPDIR:-/tmp}/vev-jvm-hashes.XXXXXX")"
SECOND="$(mktemp "${TMPDIR:-/tmp}/vev-jvm-hashes.XXXXXX")"
trap 'rm -f "$FIRST" "$SECOND"' EXIT

jvm_hashes() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$ROOT"/build/jvm/*.jar
  else
    sha256sum "$ROOT"/build/jvm/*.jar
  fi | sed "s#$ROOT/##"
}

"$ROOT/scripts/package_jvm.sh" >/dev/null
jvm_hashes > "$FIRST"
"$ROOT/scripts/package_jvm.sh" >/dev/null
jvm_hashes > "$SECOND"

diff -u "$FIRST" "$SECOND"
cat "$SECOND"
