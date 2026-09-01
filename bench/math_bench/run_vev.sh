#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KVIST_BIN="${KVIST_BIN:-kvist}"
KVIST_WORKDIR="${KVIST_ROOT:-$ROOT}"
BUILD_DIR="${MATH_BENCH_BUILD:-$ROOT/build/math_bench}"

if [[ -n "${KVIST_ROOT:-}" ]]; then
  export KVIST_PACKAGES_DIR="${KVIST_PACKAGES_DIR:-$KVIST_ROOT/packages}"
fi

if [[ ! -f "$BUILD_DIR/schema.edn" || ! -f "$BUILD_DIR/manifest.edn" ]]; then
  "$ROOT/bench/math_bench/run_export.sh"
fi

CHUNKS="$(clojure -M -e "(println (:chunks (read-string (slurp \"$BUILD_DIR/manifest.edn\"))))")"

WORKLOADS="${MATH_BENCH_WORKLOADS:-}"
if [[ $# -gt 0 ]]; then
  if [[ $# -gt 1 ]]; then
    echo "run one workload at a time, or omit args for all workloads" >&2
    exit 1
  fi
  WORKLOADS="$1"
fi

(
  cd "$KVIST_WORKDIR"
  "$KVIST_BIN" build "$ROOT/bench/math_bench/math_bench.kvist" \
    --out "$BUILD_DIR/vev_math_bench"
)

"$BUILD_DIR/vev_math_bench" \
    --schema "$BUILD_DIR/schema.edn" \
    --values-prefix "$BUILD_DIR/values" \
    --values-chunks "$CHUNKS" \
    --warmups "${MATH_BENCH_WARMUPS:-1}" \
    --samples "${MATH_BENCH_SAMPLES:-3}" \
    --workloads "${WORKLOADS:-all}"
