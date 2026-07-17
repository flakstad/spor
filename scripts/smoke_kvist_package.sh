#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE="$ROOT/build/release/source/vev-kvist-$VERSION.tar.gz"

if ! command -v kvist >/dev/null 2>&1; then
  echo "kvist not found; skipping Kvist package smoke"
  exit 0
fi

if [[ ! -f "$ARCHIVE" ]]; then
  "$ROOT/scripts/package_source_archives.sh" >/dev/null
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-kvist-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
PACKAGE_ROOT="$TMP_DIR/vev-kvist-$VERSION"

cat > "$PACKAGE_ROOT/smoke.kvist" <<'EOF'
(package main)

(import d "./src/vev_app")
(import kdata "kvist:data")

(defn main []
  (let [conn (d.create-conn)
        _ (d.transact conn '[{:db/id 1 :user/name "Ada"}])
        db (d.db conn)
        names (d.q '[:find ?name :where [?e :user/name ?name]] db)]
    (when (not (= (kdata.count names) 1))
      (panic "unexpected packaged Kvist query result"))))
EOF

(
  cd "$PACKAGE_ROOT"
  kvist run smoke.kvist >/dev/null
)

echo ":vev-kvist-package-ok"
