#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="${1:?usage: run_engine.sh datascript|datalevin|datomic [benchmark options]}"
shift
SOURCE="$ROOT/bench/transaction_comparison"
DATASCRIPT_VERSION="${DATASCRIPT_VERSION:-1.7.8}"
DATALEVIN_VERSION="${DATALEVIN_VERSION:-0.10.7}"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7705}"
CLOJURE_COMMAND=(clojure -Srepro)

case "$ENGINE" in
  datascript)
    DEPS="datascript/datascript {:mvn/version \"$DATASCRIPT_VERSION\"}"
    ;;
  datalevin)
    DEPS="datalevin/datalevin {:mvn/version \"$DATALEVIN_VERSION\"}"
    CLOJURE_COMMAND+=(
      -J--enable-native-access=ALL-UNNAMED
      -J--add-opens=java.base/java.nio=ALL-UNNAMED
      -J--add-opens=java.base/sun.nio.ch=ALL-UNNAMED
    )
    ;;
  datomic)
    DEPS="com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}"
    ;;
  *)
    echo "unsupported engine: $ENGINE" >&2
    exit 1
    ;;
esac

exec "${CLOJURE_COMMAND[@]}" \
  -Sdeps "{:paths [\"$SOURCE\"] :deps {$DEPS}}" \
  -M -m vev-bench.resident-transactions --engine "$ENGINE" "$@"
