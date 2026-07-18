#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_OUT="$ROOT/build/examples/java"
STORE="${VEV_MUSICBRAINZ_STORE:-$ROOT/build/musicbrainz/vev-mbrainz-tutorial.sqlite}"

cd "$ROOT"

if [[ ! -f "$STORE" ]]; then
  echo "missing persistent MusicBrainz Vev store: $STORE" >&2
  echo "build it with scripts/musicbrainz_workshop_setup.sh" >&2
  exit 1
fi

if [[ ! -f "$JAVA_OUT/com/vevdb/Vev.class" || "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java" -nt "$JAVA_OUT/com/vevdb/Vev.class" ]]; then
  javac \
    --release 25 \
    -d "$JAVA_OUT" \
    "$ROOT/clients/java/src/main/java/com/vevdb/Vev.java"
fi

clojure \
  -J--enable-native-access=ALL-UNNAMED \
  -Sdeps "{:paths [\"$JAVA_OUT\" \"$ROOT/clients/clojure/src\" \"$ROOT/examples/clojure\"]}" \
  -M -e "(require '[musicbrainz-workshop :as workshop]) (println (workshop/validate-opening-bindings!)) (println (workshop/validate-find-specifications!)) (println (workshop/validate-collection-functions!)) (println (workshop/validate-numeric-attributes!)) (println (workshop/validate-dynamic-attributes!)) (println (workshop/validate-country-inputs!)) (println (workshop/validate-basic-aggregations!)) (println (workshop/validate-deeper-query-intro!)) (println (workshop/validate-mbrainz-opening-data-queries!)) (println (workshop/validate-pre-1970-release-stats!)) (println (workshop/validate-pre-1970-track-stats!)) (println (workshop/validate-rules-intro!)) (println (workshop/validate-pattern-inputs!)) (println (workshop/validate-pull-intro!)) (println (workshop/validate-pull-nested-map!)) (println (workshop/validate-pull-wildcard!)) (println (workshop/validate-pull-wildcard-map!)) (println (workshop/validate-pull-default-option!)) (println (workshop/validate-pull-default-option-string!)) (println (workshop/validate-pull-absent-attribute!)) (println (workshop/validate-pull-explicit-limit!)) (println (workshop/validate-pull-limit-subspec!)) (println (workshop/validate-pull-limit-subspec-as!)) (println (workshop/validate-pull-no-limit!)) (println (workshop/validate-pull-empty-results!)) (println (workshop/validate-pull-empty-results-in-collection!)) (println (workshop/validate-pull-expression-in-query!)) (println (workshop/validate-dynamic-pattern-input!))"
