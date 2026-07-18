#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
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
  curl
  go
  jar
  java
  javac
  kvist
  node
  odin
  pkg-config
  python3
  rustc
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

if ! command -v shasum >/dev/null 2>&1 &&
   ! command -v sha256sum >/dev/null 2>&1; then
  echo "release environment is missing shasum or sha256sum" >&2
  exit 1
fi

if ! command -v llvm-ar >/dev/null 2>&1 &&
   ! command -v ar >/dev/null 2>&1; then
  echo "release environment is missing llvm-ar or ar" >&2
  exit 1
fi

if ! javac -version 2>&1 | grep -Eq 'javac (2[5-9]|[3-9][0-9])([.]|$)'; then
  echo "release builds require JDK 25 or newer" >&2
  javac -version >&2
  exit 1
fi

printf '%s\n' "$PLATFORM"
