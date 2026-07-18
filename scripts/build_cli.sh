#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
KVIST_BIN="${KVIST_BIN:-kvist}"
GENERATED_DIR="$ROOT/build/generated/vev_cli"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) EXE_NAME="vevdb.exe" ;;
  *) EXE_NAME="vevdb" ;;
esac

OUTPUT="${VEV_CLI_OUTPUT:-$ROOT/build/$EXE_NAME}"
IF_NEEDED="false"
if [[ "${1:-}" == "--if-needed" ]]; then
  IF_NEEDED="true"
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "usage: scripts/build_cli.sh [--if-needed]" >&2
  exit 1
fi

SQLITE_LIB_DIR="${VEV_SQLITE_LIB_DIR:-}"
if [[ -z "$SQLITE_LIB_DIR" ]]; then
  SQLITE_LIB_DIR="$("$ROOT/scripts/build_sqlite.sh")"
fi

mkdir -p "$GENERATED_DIR" "$(dirname "$OUTPUT")"

if [[ "$IF_NEEDED" == "true" && -x "$OUTPUT" ]]; then
  CURRENT="true"
  if find "$ROOT/src/vev" "$ROOT/src/vev_cli" -type f -newer "$OUTPUT" -print -quit | grep -q .; then
    CURRENT="false"
  fi
  for input in "$ROOT/VERSION" "$ROOT/scripts/build_cli.sh" "$ROOT/scripts/build_sqlite.sh"; do
    if [[ "$input" -nt "$OUTPUT" ]]; then
      CURRENT="false"
    fi
  done
  if [[ "$CURRENT" == "true" ]]; then
    printf '%s\n' "$OUTPUT"
    exit 0
  fi
fi

"$KVIST_BIN" compile \
  "$ROOT/src/vev_cli/main.kvist" \
  -o "$GENERATED_DIR/vev_cli.odin"

ODIN_ARGS=(
  "$GENERATED_DIR/vev_cli.odin"
  -file
  -out:"$OUTPUT"
  -define:VEV_VERSION="$VERSION"
)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    SQLITE_WINDOWS_DIR="$(cygpath -w "$SQLITE_LIB_DIR")"
    ODIN_ARGS+=("-extra-linker-flags:/LIBPATH:$SQLITE_WINDOWS_DIR")
    ;;
  *)
    ODIN_ARGS+=("-extra-linker-flags:-L$SQLITE_LIB_DIR")
    ;;
esac

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    MSYS2_ARG_CONV_EXCL="-extra-linker-flags:" odin build "${ODIN_ARGS[@]}"
    ;;
  *)
    odin build "${ODIN_ARGS[@]}"
    ;;
esac
printf '%s\n' "$OUTPUT"
