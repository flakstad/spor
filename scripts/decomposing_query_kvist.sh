#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kvist run "$ROOT/examples/kvist/decomposing_query.kvist"
