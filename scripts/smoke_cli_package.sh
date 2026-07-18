#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"

case "$(uname -s)" in
  Darwin) OS="darwin"; EXE_NAME="vevdb"; FORMAT="tar.gz" ;;
  Linux) OS="linux"; EXE_NAME="vevdb"; FORMAT="tar.gz" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; EXE_NAME="vevdb.exe"; FORMAT="zip" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
ARCHIVE="${1:-$ROOT/build/release/cli/vevdb-cli-$PLATFORM-$VERSION.$FORMAT}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vevdb-cli-package.XXXXXX")"
DB="$TMP_DIR/smoke.vev"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -f "$ARCHIVE" ]]; then
  "$ROOT/scripts/package_cli.sh" >/dev/null
fi

case "$FORMAT" in
  tar.gz) tar -xzf "$ARCHIVE" -C "$TMP_DIR" ;;
  zip) unzip -q "$ARCHIVE" -d "$TMP_DIR" ;;
esac

CLI="$TMP_DIR/vevdb-$VERSION/bin/$EXE_NAME"
[[ "$("$CLI" --version)" == "vevdb $VERSION" ]]
"$CLI" transact "$DB" '[{:db/id 1 :user/name "Ada"}]' >/dev/null
query="$("$CLI" query "$DB" '[:find ?name :where [?e :user/name ?name]]')"
case "$query" in *'"Ada"'*) ;; *) echo "unexpected packaged CLI query: $query" >&2; exit 1 ;; esac

"$ROOT/scripts/check_self_contained_native.sh" "$CLI" >/dev/null

echo ":vevdb-cli-package-ok"
