#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  *) echo "release builds do not support $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "release builds do not support architecture $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
if [[ -n "${VEV_EXPECT_PLATFORM:-}" && "$PLATFORM" != "$VEV_EXPECT_PLATFORM" ]]; then
  echo "release runner is $PLATFORM, expected $VEV_EXPECT_PLATFORM" >&2
  exit 1
fi

required_commands=(
  cargo
  clang
  clang++
  clojure
  go
  jar
  java
  javac
  kvist
  node
  odin
  python3
  rustc
  shasum
  tar
  unzip
)

missing=()
for command in "${required_commands[@]}"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    missing+=("$command")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'release environment is missing required commands:' >&2
  printf ' %s' "${missing[@]}" >&2
  printf '\n' >&2
  exit 1
fi

if ! javac -version 2>&1 | grep -Eq 'javac (21|2[2-9]|[3-9][0-9])([.]|$)'; then
  echo "release builds require JDK 21 or newer" >&2
  javac -version >&2
  exit 1
fi

printf '%s\n' "$PLATFORM"
