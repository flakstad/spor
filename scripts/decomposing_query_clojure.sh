#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"

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
  -Sdeps "{:paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\" \"$ROOT/examples/clojure\"]}" \
  -M -e "(require '[decomposing-query :as dq]) (println (dq/validate-opening-decomposition!))"
