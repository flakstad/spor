#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WARMUP_RUNS="${WARMUP_RUNS:-2}"
MEASURE_RUNS="${MEASURE_RUNS:-5}"

WORKLOADS=(
  mbrainz-title-album-year-by-artist
  mbrainz-pre-1970-title-album-year
  mbrainz-track-release-rule
  mbrainz-track-search-info
)

usage() {
  cat <<EOF
usage: scripts/compare_musicbrainz_target_rows.sh [workload ...]

Runs selected MusicBrainz workloads sequentially against Vev Clojure and local
Datomic. Workload names are accepted by compare_musicbrainz_workshop.sh.

env:
  WARMUP_RUNS=n    default: $WARMUP_RUNS
  MEASURE_RUNS=n   default: $MEASURE_RUNS
  DATOMIC_URI=uri  forwarded to compare_musicbrainz_workshop.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  WORKLOADS=("$@")
fi

for workload in "${WORKLOADS[@]}"; do
  echo "== $workload =="
  "$ROOT/scripts/compare_musicbrainz_workshop.sh" \
    --workload "$workload" \
    --query-stats \
    --warmup-runs "$WARMUP_RUNS" \
    --measure-runs "$MEASURE_RUNS" \
    --skip-kvist
done
