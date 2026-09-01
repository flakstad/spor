#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKLOAD="all"
SAMPLES="1"
WARMUPS="0"
PRINT_ROWS="false"
SCHEMA="$ROOT/build/musicbrainz/vev-mbrainz-subset-full-chunked-schema.edn"
VALUES_PREFIX="$ROOT/build/musicbrainz/vev-mbrainz-subset-full-chunked"
VALUES_CHUNKS="8"
BIN="$ROOT/build/bench/musicbrainz_query_profile"
BUILD="true"

usage() {
  cat <<EOF
usage: scripts/compare_musicbrainz_query_matrix.sh [options]

Runs the restored MusicBrainz query matrix against Vev and local Datomic, then
compares row counts and portable fingerprints.

options:
  --workload name        workload name or suffix; default: all
  --samples n           timing samples per engine; default: 1
  --warmups n           warmups per engine; default: 0
  --print-rows bool     print sorted projected row keys; default: false
  --schema path         Vev exported schema EDN path
  --values-prefix path  Vev exported chunk prefix
  --values-chunks n     number of Vev value chunks; default: 8
  --bin path            Vev profiler binary path
  --no-build            use existing profiler binary
  -h, --help            show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workload) WORKLOAD="$2"; shift 2 ;;
    --samples) SAMPLES="$2"; shift 2 ;;
    --warmups) WARMUPS="$2"; shift 2 ;;
    --print-rows) PRINT_ROWS="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;;
    --values-prefix) VALUES_PREFIX="$2"; shift 2 ;;
    --values-chunks) VALUES_CHUNKS="$2"; shift 2 ;;
    --bin) BIN="$2"; shift 2 ;;
    --no-build) BUILD="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$BUILD" == "true" ]]; then
  mkdir -p "$(dirname "$BIN")" "$ROOT/build/kvist-generated"
  kvist build "$ROOT/bench/musicbrainz_query_profile.kvist" \
    --out "$BIN" \
    --generated-dir "$ROOT/build/kvist-generated"
fi

if [[ ! -x "$BIN" ]]; then
  echo "Vev profiler binary not found or not executable: $BIN" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vev-mbrainz-compare.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

vev_out="$tmp_dir/vev.out"
datomic_out="$tmp_dir/datomic.out"
vev_tsv="$tmp_dir/vev.tsv"
datomic_tsv="$tmp_dir/datomic.tsv"

extract_results() {
  awk '
    /^engine=(vev|datomic) workload=/ {
      workload = ""
      rows = ""
      fingerprint = ""
      for (i = 1; i <= NF; i++) {
        split($i, part, "=")
        if (part[1] == "workload") workload = part[2]
        if (part[1] == "rows") rows = part[2]
        if (part[1] == "fingerprint") fingerprint = part[2]
      }
      if (workload != "" && rows != "" && fingerprint != "") {
        print workload "\t" rows "\t" fingerprint
      }
    }
  ' "$1" | sort
}

echo "== Vev =="
"$BIN" \
  --dataset real \
  --schema "$SCHEMA" \
  --values-prefix "$VALUES_PREFIX" \
  --values-chunks "$VALUES_CHUNKS" \
  --samples "$SAMPLES" \
  --warmups "$WARMUPS" \
  --workload "$WORKLOAD" \
  --print-rows "$PRINT_ROWS" | tee "$vev_out"

echo "== Datomic =="
"$ROOT/scripts/musicbrainz_sample.sh" query-matrix-datomic \
  --samples "$SAMPLES" \
  --warmups "$WARMUPS" \
  --workload "$WORKLOAD" \
  --print-rows "$PRINT_ROWS" | tee "$datomic_out"

extract_results "$vev_out" > "$vev_tsv"
extract_results "$datomic_out" > "$datomic_tsv"

if [[ ! -s "$datomic_tsv" ]]; then
  echo "No Datomic result rows found for workload: $WORKLOAD" >&2
  exit 1
fi

status=0
while IFS=$'\t' read -r workload rows fingerprint; do
  match="$(awk -F '\t' -v w="$workload" '$1 == w { print $2 "\t" $3; found = 1; exit } END { if (!found) exit 1 }' "$vev_tsv" || true)"
  if [[ -z "$match" ]]; then
    echo "MISSING workload=$workload engine=vev expected_rows=$rows expected_fingerprint=$fingerprint" >&2
    status=1
    continue
  fi
  vev_rows="${match%%$'\t'*}"
  vev_fingerprint="${match#*$'\t'}"
  if [[ "$vev_rows" != "$rows" || "$vev_fingerprint" != "$fingerprint" ]]; then
    echo "MISMATCH workload=$workload datomic_rows=$rows datomic_fingerprint=$fingerprint vev_rows=$vev_rows vev_fingerprint=$vev_fingerprint" >&2
    status=1
  else
    echo "MATCH workload=$workload rows=$rows fingerprint=$fingerprint"
  fi
done < "$datomic_tsv"

exit "$status"
