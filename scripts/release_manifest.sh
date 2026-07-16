#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
OUT="${1:-$ROOT/build/release/manifest.json}"

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

PLATFORM="$OS-$ARCH"
SOURCE_DIR="$ROOT/build/release/source"

metadata_version() {
  case "$1" in
    java) sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$ROOT/clients/java/pom.xml" | head -1 ;;
    python) sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/clients/python/pyproject.toml" | head -1 ;;
    rust) sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/clients/rust/Cargo.toml" | head -1 ;;
    node) sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*/\1/p' "$ROOT/clients/node/package.json" | head -1 ;;
  esac
}

for client in java python rust node; do
  actual="$(metadata_version "$client")"
  if [[ "$actual" != "$VERSION" ]]; then
    echo "$client package version $actual does not match VERSION $VERSION" >&2
    exit 1
  fi
done

git_commit="$(git -C "$ROOT" rev-parse HEAD)"
mkdir -p "$(dirname "$OUT")"

required_artifacts=(
  "$ROOT/build/lib/$LIB_NAME"
  "$ROOT/build/release/native/vev-native-$PLATFORM-$VERSION.zip"
  "$ROOT/include/vev.h"
  "$ROOT/build/jvm/vev-java-$VERSION.jar"
  "$ROOT/build/jvm/vev-native-$PLATFORM-$VERSION.jar"
  "$ROOT/build/jvm/vev-clj-$VERSION.jar"
  "$SOURCE_DIR/vev-python-$VERSION.tar.gz"
  "$SOURCE_DIR/vev-rust-$VERSION.tar.gz"
  "$SOURCE_DIR/vev-node-$VERSION.tar.gz"
  "$SOURCE_DIR/vev-go-$VERSION.tar.gz"
  "$SOURCE_DIR/vev-odin-$VERSION.tar.gz"
  "$SOURCE_DIR/vev-kvist-$VERSION.tar.gz"
)

for path in "${required_artifacts[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "missing release artifact: ${path#"$ROOT/"}" >&2
    exit 1
  fi
done

sha256() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

artifact() {
  local name="$1"
  local kind="$2"
  local path="$3"
  local relative="${path#"$ROOT/"}"
  local exists="false"
  local hash=""

  [[ -e "$path" ]] && exists="true"
  hash="$(sha256 "$path")"
  printf '    {"name":"%s","kind":"%s","path":"%s","exists":%s,"sha256":' \
    "$name" "$kind" "$relative" "$exists"
  if [[ -n "$hash" ]]; then
    printf '"%s"}' "$hash"
  else
    printf 'null}'
  fi
}

{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "version": "%s",\n' "$VERSION"
  printf '  "git_commit": "%s",\n' "$git_commit"
  printf '  "platform": "%s",\n' "$PLATFORM"
  printf '  "artifacts": [\n'
  artifact "vev-native-$PLATFORM" "native-library" "$ROOT/build/lib/$LIB_NAME"; printf ',\n'
  artifact "vev-native-$PLATFORM-bundle" "native-bundle" "$ROOT/build/release/native/vev-native-$PLATFORM-$VERSION.zip"; printf ',\n'
  artifact "vev-c-header" "c-header" "$ROOT/include/vev.h"; printf ',\n'
  artifact "vev-java" "jvm-jar" "$ROOT/build/jvm/vev-java-$VERSION.jar"; printf ',\n'
  artifact "vev-native-$PLATFORM-jvm" "jvm-native-jar" "$ROOT/build/jvm/vev-native-$PLATFORM-$VERSION.jar"; printf ',\n'
  artifact "vev-clj" "clojure-jar" "$ROOT/build/jvm/vev-clj-$VERSION.jar"; printf ',\n'
  artifact "vev-python" "python-source-archive" "$SOURCE_DIR/vev-python-$VERSION.tar.gz"; printf ',\n'
  artifact "vev-rust" "rust-source-archive" "$SOURCE_DIR/vev-rust-$VERSION.tar.gz"; printf ',\n'
  artifact "vev-node" "node-source-archive" "$SOURCE_DIR/vev-node-$VERSION.tar.gz"; printf ',\n'
  artifact "vev-go" "go-source-archive" "$SOURCE_DIR/vev-go-$VERSION.tar.gz"; printf ',\n'
  artifact "vev-odin" "odin-source-archive" "$SOURCE_DIR/vev-odin-$VERSION.tar.gz"; printf ',\n'
  artifact "vev-kvist" "kvist-source-archive" "$SOURCE_DIR/vev-kvist-$VERSION.tar.gz"; printf '\n'
  printf '  ]\n'
  printf '}\n'
} > "$OUT"

echo "$OUT"
