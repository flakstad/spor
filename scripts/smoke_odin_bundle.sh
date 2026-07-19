#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"

case "$(uname -s)" in
  Darwin) OS="darwin"; EXE_SUFFIX="" ;;
  Linux) OS="linux"; EXE_SUFFIX="" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; EXE_SUFFIX=".exe" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if ! command -v odin >/dev/null 2>&1; then
  echo "odin not found; skipping Odin vendor bundle smoke"
  exit 0
fi

PLATFORM="$OS-$ARCH"
ARCHIVE="${1:-$ROOT/build/release/odin/vev-odin-$PLATFORM-$VERSION.zip}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-odin-vendor.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$ARCHIVE" ]]; then
  echo "missing Odin vendor bundle: $ARCHIVE" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/consumer/vendor"
(
  cd "$TMP_DIR/consumer/vendor"
  jar --extract --file "$ARCHIVE"
)

cat > "$TMP_DIR/consumer/main.odin" <<'EOF'
package main

import "core:fmt"
import vev "vendor/vev"

main :: proc() {
	library, loaded := vev.load_bundled("vendor/vev")
	assert(loaded)
	defer vev.unload(&library)

	connection, connected := vev.connect(&library, "smoke.vev")
	assert(connected)
	defer vev.close(&connection)

	tx, transacted := vev.transact(
		&connection,
		`[{:db/id 1 :user/name "Ada"}]`,
	)
	assert(transacted)
	defer delete(tx)

	rows, queried := vev.query_rows(
		&connection,
		`[:find ?name :where [?e :user/name ?name]]`,
	)
	assert(queried)
	defer vev.close(&rows)
	assert(vev.row_count(&rows) == 1)

	name, found := vev.value_edn(&rows, 0, 0)
	assert(found)
	defer delete(name)
	assert(name == `"Ada"`)
	fmt.println(name)
}
EOF

(
  cd "$TMP_DIR/consumer"
  odin build . -out:"$TMP_DIR/consumer-smoke$EXE_SUFFIX"
  "./../consumer-smoke$EXE_SUFFIX" >/dev/null
)

echo ":vev-odin-vendor-bundle-ok"
