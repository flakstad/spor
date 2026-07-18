#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7277}"

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
  -Sdeps "{:deps {com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}
                  org.clojure/data.generators {:mvn/version \"0.1.2\"}}
           :paths [\"$JAVA_OUT\"
                   \"$ROOT/clients/clojure/src\"
                   \"$ROOT/examples/clojure\"
                   \"$ROOT/build/upstream/day-of-datomic/src\"
                   \"$ROOT/build/upstream/day-of-datomic/resources\"]}" \
  -M "$ROOT/scripts/compare_aggregates_tutorial.clj"
