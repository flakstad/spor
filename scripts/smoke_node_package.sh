#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) OS="darwin"; LIB_NAME="libvev.dylib" ;;
  Linux) OS="linux"; LIB_NAME="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; LIB_NAME="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ ! -f "$ROOT/build/examples/node/vev_native.node" || ! -f "$ROOT/build/lib/$LIB_NAME" ]]; then
  "$ROOT/scripts/build_node_addon.sh" >/dev/null
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-node-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/native/$OS-$ARCH"
cp "$ROOT/clients/node/vev.js" "$TMP_DIR/vev.js"
cp "$ROOT/clients/node/vev.d.ts" "$TMP_DIR/vev.d.ts"
cp "$ROOT/clients/node/package.json" "$TMP_DIR/package.json"
cp "$ROOT/build/examples/node/vev_native.node" "$TMP_DIR/native/$OS-$ARCH/vev_native.node"
cp "$ROOT/build/lib/$LIB_NAME" "$TMP_DIR/native/$OS-$ARCH/$LIB_NAME"

(
  cd "$TMP_DIR"
  env -u VEV_NODE_NATIVE node - <<'JS'
const fs = require("fs");
const vev = require("./vev");
function removeStore(path) {
  for (const suffix of ["", "-wal", "-shm"]) {
    try {
      fs.unlinkSync(`${path}${suffix}`);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
if (pkg.name !== "@vevdb/vev" || pkg.main !== "vev.js" || pkg.types !== "vev.d.ts") {
  throw new Error(`unexpected package metadata: ${JSON.stringify(pkg)}`);
}
const conn = vev.createConn();
conn.transact('[{:db/id 1 :user/name "Ada"}]');
const result = conn.queryText('[:find ?name :where [?e :user/name ?name]]');
if (!result.includes('"Ada"')) {
  throw new Error(`unexpected query result: ${result}`);
}
const store = "tmp.vev.node-package.sqlite";
removeStore(store);
try {
  const durable = vev.connect(store);
  durable.transact('[{:db/id 2 :user/name "Durable Grace"}]');
  const durableResult = durable.db().query(conn.prepare('[:find ?name :where [?e :user/name ?name]]'));
  if (!durableResult.includes('"Durable Grace"')) {
    throw new Error(`unexpected durable query result: ${durableResult}`);
  }
} finally {
  removeStore(store);
}
console.log(":vev-node-package-ok");
JS
)
