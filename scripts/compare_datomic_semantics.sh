#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
DATOMIC_VERSION="${DATOMIC_VERSION:-1.0.7277}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 25)}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

"$ROOT/scripts/build_native_library.sh" >/dev/null
mkdir -p "$JAVA_OUT"
javac \
  --release 25 \
  -d "$JAVA_OUT" \
  "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java"

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:deps {com.datomic/peer {:mvn/version \"$DATOMIC_VERSION\"}}
           :paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\"]}" \
  -M "$ROOT/scripts/compare_datomic_semantics.clj"
