#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clojure -M "$ROOT/scripts/check_datomic_peer_manifest.clj" \
  "$ROOT/compat/datomic-peer-api.edn"
