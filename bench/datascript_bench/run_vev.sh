#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAVA_DIR="$ROOT/build/examples/java"
LIB_PATH="${VEV_LIB:-$ROOT/build/lib/libvev.dylib}"

if [[ ! -f "$LIB_PATH" ]]; then
  echo "missing Vev native library: $LIB_PATH" >&2
  echo "run scripts/build_c_abi.sh first" >&2
  exit 1
fi

mkdir -p "$JAVA_DIR"

if [[ ! -f "$JAVA_DIR/vev/Vev.class" || "$ROOT/examples/java/Vev.java" -nt "$JAVA_DIR/vev/Vev.class" ]]; then
  javac \
    --release 25 \
    -d "$JAVA_DIR" \
    "$ROOT/examples/java/Vev.java"
fi

BENCHMARKS=("$@")
if [[ ${#BENCHMARKS[@]} -eq 0 ]]; then
  BENCHMARKS=(q1 q2 q2-switch q3 q4 qpred1 qpred2)
fi

printf "version\t"
for bench in "${BENCHMARKS[@]}"; do
  printf "%s\t" "$bench"
done
printf "\n"
printf "vev\t"

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:paths [\"$JAVA_DIR\" \"$ROOT/clients/clojure/src\" \"$ROOT/bench/datascript_bench/src\"]}" \
  -M \
  -m vev-datascript-bench.vev \
  "${BENCHMARKS[@]}"
