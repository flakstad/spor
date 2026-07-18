#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
KVIST_BIN="${KVIST_BIN:-kvist}"
GENERATED_DIR="$ROOT/build/generated/vev_abi"
LIB_DIR="$ROOT/build/lib"
INCLUDE_DIR="$ROOT/build/include"
PKGCONFIG_DIR="$LIB_DIR/pkgconfig"
IF_NEEDED="false"
KVIST_PATH="$(command -v "$KVIST_BIN" 2>/dev/null || true)"

if [[ "${1:-}" == "--if-needed" ]]; then
  IF_NEEDED="true"
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "usage: scripts/build_native_library.sh [--if-needed]" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib"; LINK_NAME="" ;;
  Linux) LIB_NAME="libvev.so"; LINK_NAME="" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll"; LINK_NAME="vev.lib" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

LIB_PATH="$LIB_DIR/$LIB_NAME"
mkdir -p "$GENERATED_DIR" "$LIB_DIR" "$INCLUDE_DIR" "$PKGCONFIG_DIR"

SQLITE_LIB_DIR="${VEV_SQLITE_LIB_DIR:-}"
if [[ -z "$SQLITE_LIB_DIR" ]]; then
  SQLITE_LIB_DIR="$("$ROOT/scripts/build_sqlite.sh")"
fi

if [[ "$IF_NEEDED" == "true" && -f "$LIB_PATH" ]]; then
  SOURCES_CURRENT="true"
  if find "$ROOT/src/vev" "$ROOT/src/vev_abi" -type f -newer "$LIB_PATH" -print -quit | grep -q .; then
    SOURCES_CURRENT="false"
  fi
  if [[ "$ROOT/VERSION" -nt "$LIB_PATH" ]]; then
    SOURCES_CURRENT="false"
  fi
  if [[ "$ROOT/scripts/build_native_library.sh" -nt "$LIB_PATH" ]]; then
    SOURCES_CURRENT="false"
  fi
  if [[ ! -f "$INCLUDE_DIR/vev.h" || "$ROOT/include/vev.h" -nt "$INCLUDE_DIR/vev.h" ]]; then
    SOURCES_CURRENT="false"
  fi
  if [[ -n "$KVIST_PATH" && "$KVIST_PATH" -nt "$LIB_PATH" ]]; then
    SOURCES_CURRENT="false"
  fi
  if [[ "$SOURCES_CURRENT" == "true" ]]; then
    echo "$LIB_PATH"
    exit 0
  fi
fi

if [[ -n "${KVIST_REPO_DIR:-}" ]]; then
  (
    cd "$KVIST_REPO_DIR"
    "$KVIST_BIN" compile "$ROOT/src/vev_abi/vev_abi.kvist" -o "$GENERATED_DIR/vev_abi.odin"
  )
else
  "$KVIST_BIN" compile "$ROOT/src/vev_abi/vev_abi.kvist" -o "$GENERATED_DIR/vev_abi.odin"
fi

ODIN_BUILD_ARGS=(
  "$GENERATED_DIR"
  -build-mode:dll
  -out:"$LIB_PATH"
)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    ODIN_BUILD_ARGS+=("-extra-linker-flags:/LIBPATH:$SQLITE_LIB_DIR")
    ;;
  *)
    ODIN_BUILD_ARGS+=("-extra-linker-flags:-L$SQLITE_LIB_DIR")
    ;;
esac
odin build "${ODIN_BUILD_ARGS[@]}"
if [[ -n "$LINK_NAME" && ! -f "$LIB_DIR/$LINK_NAME" ]]; then
  echo "Windows build did not produce import library $LIB_DIR/$LINK_NAME" >&2
  exit 1
fi
cp "$ROOT/include/vev.h" "$INCLUDE_DIR/vev.h"

cat > "$PKGCONFIG_DIR/vev.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Vev
Description: Embedded native Datalog database
Version: $VERSION
Libs: -L\${libdir} -lvev
Cflags: -I\${includedir}
EOF

echo "$LIB_PATH"
