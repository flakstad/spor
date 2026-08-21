#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="${VEV_CLI_VERSION:-$(vev_cli_version "$ROOT")}"
KVIST_BIN="${KVIST_BIN:-kvist}"
GENERATED_DIR="$ROOT/build/generated/vev_cli"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) EXE_NAME="vevdb.exe" ;;
  *) EXE_NAME="vevdb" ;;
esac

OUTPUT="${VEV_CLI_OUTPUT:-$ROOT/build/$EXE_NAME}"
BUILD_CONFIG_PATH="$OUTPUT.build-config"
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
SQLITE_MODE="${VEV_SQLITE_MODE:-}"
if [[ -z "$SQLITE_MODE" ]]; then
  if [[ -n "$SQLITE_LIB_DIR" ]]; then
    SQLITE_MODE="system"
  else
    SQLITE_MODE="bundled"
  fi
fi
case "$SQLITE_MODE" in
  bundled)
    if [[ -n "$SQLITE_LIB_DIR" ]]; then
      echo "VEV_SQLITE_LIB_DIR requires VEV_SQLITE_MODE=system" >&2
      exit 1
    fi
    SQLITE_LIB_DIR="$("$ROOT/scripts/build_sqlite.sh")"
    ;;
  system)
    ;;
  *)
    echo "VEV_SQLITE_MODE must be bundled or system" >&2
    exit 1
    ;;
esac
BUILD_CONFIG="sqlite-mode=$SQLITE_MODE;sqlite-lib-dir=$SQLITE_LIB_DIR;version=$VERSION"

mkdir -p "$GENERATED_DIR" "$(dirname "$OUTPUT")"

if [[ "$IF_NEEDED" == "true" && -x "$OUTPUT" ]]; then
  CURRENT="true"
  if [[ ! -f "$BUILD_CONFIG_PATH" ||
        "$(cat "$BUILD_CONFIG_PATH")" != "$BUILD_CONFIG" ]]; then
    CURRENT="false"
  fi
  if find "$ROOT/src/vev" "$ROOT/src/vev_cli" -type f -newer "$OUTPUT" -print -quit | grep -q .; then
    CURRENT="false"
  fi
  for input in "$ROOT/VERSION" "$ROOT/scripts/version.sh" "$ROOT/scripts/build_cli.sh" "$ROOT/scripts/build_sqlite.sh"; do
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
    # Match the practical stack available on Unix. The Windows default (1 MiB)
    # is insufficient for composed durable exec requests.
    WINDOWS_LINKER_FLAGS=("/STACK:8388608")
    if [[ -n "$SQLITE_LIB_DIR" ]]; then
      SQLITE_WINDOWS_DIR="$(cygpath -w "$SQLITE_LIB_DIR")"
      WINDOWS_LINKER_FLAGS+=("/LIBPATH:$SQLITE_WINDOWS_DIR")
    fi
    ODIN_ARGS+=("-extra-linker-flags:${WINDOWS_LINKER_FLAGS[*]}")
    ;;
  *)
    if [[ -n "$SQLITE_LIB_DIR" ]]; then
      ODIN_ARGS+=("-extra-linker-flags:-L$SQLITE_LIB_DIR")
    fi
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
printf '%s\n' "$BUILD_CONFIG" > "$BUILD_CONFIG_PATH"
printf '%s\n' "$OUTPUT"
