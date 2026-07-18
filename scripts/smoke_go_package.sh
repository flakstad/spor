#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib"; GO_CLIENT_ROOT="$ROOT/clients/go" ;;
  Linux) LIB_NAME="libvev.so"; GO_CLIENT_ROOT="$ROOT/clients/go" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll"; GO_CLIENT_ROOT="$(cygpath -m "$ROOT/clients/go")" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [[ ! -f "$ROOT/build/lib/$LIB_NAME" ]]; then
  "$ROOT/scripts/build_c_abi.sh"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-go-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/go.mod" <<EOF
module vev-go-package-smoke

go 1.22

require github.com/vevdb/vev/clients/go v0.0.0

replace github.com/vevdb/vev/clients/go => $GO_CLIENT_ROOT
EOF

cat > "$TMP_DIR/main.go" <<'EOF'
package main

import (
	"fmt"
	"strings"

	vev "github.com/vevdb/vev/clients/go"
)

func main() {
	conn, err := vev.CreateConn()
	if err != nil {
		panic(err)
	}
	defer conn.Close()

	conn.Transact(`[{:db/id 1 :user/name "Ada"}]`)
	result := conn.QueryText(`[:find ?name :where [?e :user/name ?name]]`, `[]`)
	if !strings.Contains(result, `"Ada"`) {
		panic(result)
	}
	fmt.Println(":vev-go-package-ok")
}
EOF

(
  cd "$TMP_DIR"
  PATH="$ROOT/build/lib:$PATH" \
    DYLD_LIBRARY_PATH="$ROOT/build/lib:${DYLD_LIBRARY_PATH:-}" \
    LD_LIBRARY_PATH="$ROOT/build/lib:${LD_LIBRARY_PATH:-}" \
    go run .
)
