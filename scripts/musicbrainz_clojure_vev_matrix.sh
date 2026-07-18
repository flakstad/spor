#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
LIB=""
URI=""
WORKLOAD="country-names"
SAMPLES="10"
WARMUPS="5"
SCHEMA="$ROOT/build/musicbrainz/vev-mbrainz-subset-500-schema.edn"
VALUES="$ROOT/build/musicbrainz/vev-mbrainz-subset-500-values.edn"
VALUES_PREFIX="$ROOT/build/musicbrainz/vev-mbrainz-subset-full-chunked"
VALUES_CHUNKS="8"
PRINT_ROWS="false"

usage() {
  cat <<EOF
usage: scripts/musicbrainz_clojure_vev_matrix.sh [options]

Runs the MusicBrainz representative query matrix through the public Clojure Vev
wrapper. This measures host API overhead plus native Vev engine time.

options:
  --workload name        workload name or suffix; default: country-names
  --samples n           timing samples; default: 10
  --warmups n           warmups; default: 5
  --lib path            native library path; default uses Java loader lookup
  --uri uri             open an existing durable Vev DB and skip EDN loading
  --schema path         Vev exported schema EDN path
  --values path         Vev exported single values EDN path
  --values-prefix path  Vev exported chunk prefix
  --values-chunks n     number of Vev value chunks; default: 8
  --print-rows true     print canonical row keys; default: false
  -h, --help            show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workload) WORKLOAD="$2"; shift 2 ;;
    --samples) SAMPLES="$2"; shift 2 ;;
    --warmups) WARMUPS="$2"; shift 2 ;;
    --lib) LIB="$2"; shift 2 ;;
    --uri) URI="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;;
    --values) VALUES="$2"; shift 2 ;;
    --values-prefix) VALUES_PREFIX="$2"; shift 2 ;;
    --values-chunks) VALUES_CHUNKS="$2"; shift 2 ;;
    --print-rows) PRINT_ROWS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$JAVA_OUT"

if [[ ! -f "$JAVA_OUT/com/vevdb/vev/Vev.class" || "$ROOT/clients/java/src/main/java/com/vevdb/vev/Vev.java" -nt "$JAVA_OUT/com/vevdb/vev/Vev.class" ]]; then
  javac \
    --enable-preview \
    --release 21 \
    -d "$JAVA_OUT" \
    "$ROOT/clients/java/src/main/java/com/vevdb/vev/Vev.java"
fi

clojure \
  -J--enable-preview \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\"]}" \
  -M "$ROOT/scripts/musicbrainz_clojure_vev_matrix.clj" \
  --lib "$LIB" \
  --uri "$URI" \
  --schema "$SCHEMA" \
  --values "$VALUES" \
  --values-prefix "$VALUES_PREFIX" \
  --values-chunks "$VALUES_CHUNKS" \
  --workload "$WORKLOAD" \
  --samples "$SAMPLES" \
  --warmups "$WARMUPS" \
  --print-rows "$PRINT_ROWS"
