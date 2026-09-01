#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVIST_BIN="${KVIST_BIN:-kvist}"
STORE="${1:-${TMPDIR:-/tmp}/vev-contact-book-kvist.vev}"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-contact-book-kvist-bin.XXXXXX")"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/vev-contact-book-kvist-build.XXXXXX")"
trap 'rm -f "$BIN" "$BUILD_LOG"' EXIT

if ! "$KVIST_BIN" build "$ROOT/examples/kvist/contact_book.kvist" --out "$BIN" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  exit 1
fi
"$BIN" "$STORE"
