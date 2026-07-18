#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
STORE="$ROOT/build/musicbrainz/vev-mbrainz-tutorial.sqlite"
DATOMIC_URI="${DATOMIC_URI:-datomic:dev://localhost:4334/mbrainz-1968-1973}"
ENGINE="all"
RUN_KVIST="true"
QUERY_STATS="false"
WARMUP_RUNS="0"
MEASURE_RUNS="1"
PREPARED_VEV="false"

usage() {
  cat <<EOF
usage: scripts/compare_musicbrainz_workshop.sh [options]

Runs the exact upstream mbrainz-sample data-query workshop slice against Vev
Clojure, Vev Kvist, and Datomic when requested.

options:
  --engine all|vev|datomic  Clojure comparison engine; default: all
  --workload name           workload name or suffix; default: all
  --query-stats             print Vev query stats for selected workload(s)
  --prepared-vev            prepare each Vev query once per workload before timing
  --warmup-runs n           unreported warmup runs per workload; default: 0
  --measure-runs n          measured runs per workload; default: 1
  --skip-datomic            run only Vev Clojure plus Kvist validation
  --skip-kvist              skip the Kvist workshop validation
  --datomic-uri uri         Datomic URI; default: $DATOMIC_URI
  -h, --help                show this help

Before running Datomic comparison, ensure the local sample is available:
  scripts/musicbrainz_sample.sh prepare
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2 ;;
    --workload) WORKLOAD="$2"; shift 2 ;;
    --query-stats) QUERY_STATS="true"; shift ;;
    --prepared-vev) PREPARED_VEV="true"; shift ;;
    --warmup-runs) WARMUP_RUNS="$2"; shift 2 ;;
    --measure-runs) MEASURE_RUNS="$2"; shift 2 ;;
    --skip-datomic) ENGINE="vev"; shift ;;
    --skip-kvist) RUN_KVIST="false"; shift ;;
    --datomic-uri) DATOMIC_URI="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$STORE" && "$ENGINE" != "datomic" ]]; then
  echo "missing persistent MusicBrainz Vev store: $STORE" >&2
  echo "build it with scripts/musicbrainz_workshop_setup.sh" >&2
  exit 1
fi

if [[ ! -f "$JAVA_OUT/com/vevdb/Vev.class" || "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java" -nt "$JAVA_OUT/com/vevdb/Vev.class" ]]; then
  javac \
    --release 25 \
    -d "$JAVA_OUT" \
    "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java"
fi

if [[ "$RUN_KVIST" == "true" && "$ENGINE" != "datomic" ]]; then
  "$ROOT/scripts/musicbrainz_workshop_kvist.sh" "$STORE" "${WORKLOAD:-all}"
fi

if [[ "$ENGINE" != "vev" ]]; then
  "$ROOT/scripts/musicbrainz_sample.sh" start
  trap "\"$ROOT/scripts/musicbrainz_sample.sh\" stop" EXIT
fi

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:deps {com.datomic/peer {:mvn/version \"1.0.7277\"}}
           :paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\" \"$ROOT/examples/clojure\" \"$ROOT/scripts\"]}" \
  -M "$ROOT/scripts/compare_musicbrainz_workshop.clj" \
  --engine "$ENGINE" \
  --workload "${WORKLOAD:-all}" \
  --query-stats "$QUERY_STATS" \
  --prepared-vev "$PREPARED_VEV" \
  --warmup-runs "$WARMUP_RUNS" \
  --measure-runs "$MEASURE_RUNS" \
  --datomic-uri "$DATOMIC_URI"
