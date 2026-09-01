#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7277}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 25)}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

if [[ ! -f "$JAVA_OUT/com/vevdb/Vev.class" || "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java" -nt "$JAVA_OUT/com/vevdb/Vev.class" ]]; then
  javac \
    --release 25 \
    -d "$JAVA_OUT" \
    "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java"
fi

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:deps {com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}
                  org.clojure/data.generators {:mvn/version \"0.1.2\"}}
           :paths [\"$JAVA_OUT\"
                   \"$ROOT/clients/clojure/src\"
                   \"$ROOT/examples/clojure\"
                   \"$ROOT/build/upstream/day-of-datomic/src\"
                   \"$ROOT/build/upstream/day-of-datomic/resources\"]}" \
  -M "$ROOT/scripts/compare_aggregates_tutorial.clj"
