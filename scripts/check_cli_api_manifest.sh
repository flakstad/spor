#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clojure -M "$ROOT/scripts/check_cli_api_manifest.clj" \
  "$ROOT/compat/cli-api.edn" \
  "$ROOT/clients/kvist/vev.kvist" \
  "$ROOT/clients/clojure/src/vev/core.clj"
