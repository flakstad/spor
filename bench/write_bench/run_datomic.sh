#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7277}"

exec clojure -Srepro \
  -Sdeps "{:paths [\"$ROOT/bench/write_bench\"]
           :deps {com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}}}" \
  -M -m vev-bench.write-datomic "$@"
