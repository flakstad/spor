#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/contact_book_clojure.sh"
"$ROOT/scripts/contact_book_kvist.sh"
