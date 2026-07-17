#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT/build/lib"
OUT_DIR="$ROOT/build/examples/node"
OUT="$OUT_DIR/vev_native.node"
IF_AVAILABLE="false"

if [[ "${1:-}" == "--if-available" ]]; then
  IF_AVAILABLE="true"
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "usage: scripts/build_node_addon.sh [--if-available]" >&2
  exit 2
fi

unavailable() {
  if [[ "$IF_AVAILABLE" == "true" ]]; then
    echo "$1; skipping Node addon" >&2
    exit 0
  fi
  echo "$1" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || unavailable "node not found"
command -v clang++ >/dev/null 2>&1 || unavailable "clang++ not found"

NODE_INCLUDE_DIR="${NODE_INCLUDE_DIR:-}"
if [[ -z "$NODE_INCLUDE_DIR" ]]; then
  NODE_PREFIX="$(cd "$(dirname "$(command -v node)")/.." && pwd)"
  for candidate in \
    "$NODE_PREFIX/include/node" \
    /usr/local/include/node \
    /usr/include/node; do
    if [[ -f "$candidate/node_api.h" ]]; then
      NODE_INCLUDE_DIR="$candidate"
      break
    fi
  done
fi
[[ -f "${NODE_INCLUDE_DIR:-}/node_api.h" ]] ||
  unavailable "node_api.h not found"

"$ROOT/scripts/build_native_library.sh" --if-needed >/dev/null
mkdir -p "$OUT_DIR"

case "$(uname -s)" in
  Darwin)
    clang++ \
      -std=c++17 \
      -bundle \
      -undefined dynamic_lookup \
      -I"$ROOT/include" \
      -I"$NODE_INCLUDE_DIR" \
      "$ROOT/clients/node/vev_native.cc" \
      -L"$LIB_DIR" \
      -lvev \
      -Wl,-rpath,"$LIB_DIR" \
      -Wl,-rpath,@loader_path \
      -o "$OUT"
    ;;
  Linux)
    clang++ \
      -std=c++17 \
      -shared \
      -fPIC \
      -I"$ROOT/include" \
      -I"$NODE_INCLUDE_DIR" \
      "$ROOT/clients/node/vev_native.cc" \
      -L"$LIB_DIR" \
      -lvev \
      -Wl,-rpath,"$LIB_DIR" \
      -Wl,-rpath,'$ORIGIN' \
      -o "$OUT"
    ;;
  *)
    unavailable "Node addon builds do not support $(uname -s)"
    ;;
esac

printf '%s\n' "$OUT"
