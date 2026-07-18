#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-contact-book-package.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null
"$ROOT/scripts/package_jvm.sh" >/dev/null

cp "$ROOT/examples/clojure/contact_book.clj" "$TMP_DIR/contact_book.clj"

cat > "$TMP_DIR/deps.edn" <<EOF
{:mvn/local-repo "$ROOT/build/m2"
 :paths ["."]
 :deps {com.vevdb/vev-clj {:mvn/version "$VERSION"}}
 :aliases {:run {:jvm-opts ["--enable-native-access=ALL-UNNAMED"]}}}
EOF

(
  cd "$TMP_DIR"
  clojure -M:run -m contact-book "$TMP_DIR/contact-book.vev"
)
