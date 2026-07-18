#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVIST_BIN="${KVIST_BIN:-kvist}"
EXPORT_PREFIX="${VEV_MUSICBRAINZ_EXPORT_PREFIX:-$ROOT/build/musicbrainz/vev-mbrainz-subset-full-chunked}"
STORE="${VEV_MUSICBRAINZ_STORE:-$ROOT/build/musicbrainz/vev-mbrainz-tutorial.sqlite}"
IMPORT_BIN="$ROOT/build/bench/musicbrainz_import_subset"
VALIDATE="false"
FROM_DATOMIC="false"

usage() {
  cat <<EOF
usage: scripts/musicbrainz_workshop_setup.sh [options]

Creates or refreshes the persistent Vev store used by the Clojure and Kvist
MusicBrainz workshop examples.

options:
  --validate       run both workshop validation commands after setup
  --from-datomic   prepare local Datomic and export the sample when the Vev
                   transaction chunks are missing
  --store path     output Vev store; default: $STORE
  --export-prefix path
                   Vev transaction chunk prefix; default: $EXPORT_PREFIX
  -h, --help       show this help

The ordinary setup path needs Kvist, Odin, Clang, an archiver, and an existing
Vev-compatible MusicBrainz export. The Vev build supplies SQLite. Datomic is
used only with --from-datomic to convert the upstream sample backup into that
export.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) VALIDATE="true"; shift ;;
    --from-datomic) FROM_DATOMIC="true"; shift ;;
    --store) STORE="$2"; shift 2 ;;
    --export-prefix) EXPORT_PREFIX="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

for command in "$KVIST_BIN" odin; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

SCHEMA="$EXPORT_PREFIX-schema.edn"
shopt -s nullglob
VALUE_FILES=("$EXPORT_PREFIX"-values-[0-9][0-9][0-9][0-9].edn)
shopt -u nullglob

if [[ ! -f "$SCHEMA" || ${#VALUE_FILES[@]} -eq 0 ]]; then
  if [[ "$FROM_DATOMIC" != "true" ]]; then
    cat >&2 <<EOF
missing Vev-compatible MusicBrainz export:
  $SCHEMA
  $EXPORT_PREFIX-values-0000.edn ...

Use --from-datomic to download/restore the upstream sample and create the
export, or set VEV_MUSICBRAINZ_EXPORT_PREFIX to an existing exported prefix.
EOF
    exit 1
  fi

  "$ROOT/scripts/musicbrainz_sample.sh" prepare
  "$ROOT/scripts/musicbrainz_sample.sh" export-subset-chunks "$EXPORT_PREFIX" 0 100000
  shopt -s nullglob
  VALUE_FILES=("$EXPORT_PREFIX"-values-[0-9][0-9][0-9][0-9].edn)
  shopt -u nullglob
fi

if [[ ${#VALUE_FILES[@]} -eq 0 ]]; then
  echo "MusicBrainz export produced no value chunks" >&2
  exit 1
fi

for ((index = 0; index < ${#VALUE_FILES[@]}; index++)); do
  expected="$(printf '%s-values-%04d.edn' "$EXPORT_PREFIX" "$index")"
  if [[ "${VALUE_FILES[$index]}" != "$expected" ]]; then
    echo "non-contiguous MusicBrainz value chunks: expected $expected" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$IMPORT_BIN")" "$(dirname "$STORE")"
"$KVIST_BIN" build "$ROOT/bench/musicbrainz_import_subset.kvist" --out "$IMPORT_BIN"

rm -f "$STORE" "$STORE-wal" "$STORE-shm"
"$IMPORT_BIN" \
  --schema "$SCHEMA" \
  --values-prefix "$EXPORT_PREFIX" \
  --values-chunks "${#VALUE_FILES[@]}" \
  --sqlite-output "$STORE" \
  --progress true

"$ROOT/scripts/build_native_library.sh" >/dev/null

echo "MusicBrainz Vev store ready: $STORE"
echo "Clojure validation: scripts/musicbrainz_workshop_clojure.sh"
echo "Kvist validation:   scripts/musicbrainz_workshop_kvist.sh"

if [[ "$VALIDATE" == "true" ]]; then
  "$ROOT/scripts/fetch_workshop_sources.sh"
  VEV_MUSICBRAINZ_STORE="$STORE" "$ROOT/scripts/musicbrainz_workshop_clojure.sh"
  "$ROOT/scripts/musicbrainz_workshop_kvist.sh" "$STORE"
fi
