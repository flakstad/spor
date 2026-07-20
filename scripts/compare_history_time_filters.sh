#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7277}"

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 25)}"
export PATH="$JAVA_HOME/bin:$PATH"

"$ROOT/scripts/build_native_library.sh" >/dev/null
mkdir -p "$JAVA_OUT"
javac \
  --release 25 \
  -d "$JAVA_OUT" \
  "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java"

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:deps {com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}}
           :paths [\"$JAVA_OUT\"
                   \"$ROOT/clients/clojure/src\"
                   \"$ROOT/examples/clojure\"]}" \
  -M -m history-time-filters
