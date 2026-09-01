#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clojure -M "$ROOT/scripts/check_datomic_peer_manifest.clj" \
  "$ROOT/compat/datomic-peer-api.edn"
