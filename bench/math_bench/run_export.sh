#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT="${MATH_BENCH_JSON:-}"
OUTPUT_DIR="${MATH_BENCH_BUILD:-$ROOT/build/math_bench}"
CHUNK_SIZE="${MATH_BENCH_CHUNK_SIZE:-50000}"

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Set MATH_BENCH_JSON to Datalevin's benchmarks/math-bench/data.json.gz" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

clojure \
  -Sdeps "{:paths [\"$ROOT/bench/math_bench/scripts\"] :deps {metosin/jsonista {:mvn/version \"0.3.13\"}}}" \
  -M \
  -m vev-math-bench.export-data \
  --input "$INPUT" \
  --output-dir "$OUTPUT_DIR" \
  --chunk-size "$CHUNK_SIZE"
