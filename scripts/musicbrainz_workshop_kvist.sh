#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="${1:-$ROOT/build/musicbrainz/vev-mbrainz-tutorial.sqlite}"
WORKLOAD="${2:-all}"

cd "$ROOT"

if [[ ! -f "$STORE" ]]; then
  echo "missing persistent MusicBrainz Vev store: $STORE" >&2
  echo "build it with scripts/musicbrainz_workshop_setup.sh" >&2
  exit 1
fi

OUTPUT="$(mktemp "${TMPDIR:-/tmp}/vev-mbrainz-kvist.XXXXXX")"
BIN="$(mktemp "${TMPDIR:-/tmp}/vev-mbrainz-kvist-bin.XXXXXX")"
trap 'rm -f "$OUTPUT" "$BIN"' EXIT

kvist build "$ROOT/examples/kvist/musicbrainz_workshop.kvist" --out "$BIN" >/dev/null
"$BIN" "$STORE" "$WORKLOAD" | tee "$OUTPUT"

if grep -q "ok=false" "$OUTPUT"; then
  exit 1
fi

grep -q "source=kvist section=summary ok=true" "$OUTPUT"
