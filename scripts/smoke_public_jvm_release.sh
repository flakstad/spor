#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: scripts/smoke_public_jvm_release.sh <release-tag> <artifact-version> [github-repository]" >&2
  exit 1
fi

TAG="$1"
VERSION="$2"
REPOSITORY="${3:-vevdb/vev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-public-jvm-release.XXXXXX")"
DOWNLOAD_DIR="$TMP_DIR/download"
M2_DIR="$TMP_DIR/m2"
BASE_URL="https://github.com/$REPOSITORY/releases/download/$TAG"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

case "$TAG" in
  *[!0-9A-Za-z._-]*|'')
    echo "invalid release tag: $TAG" >&2
    exit 1
    ;;
esac
case "$VERSION" in
  *[!0-9A-Za-z._-]*|'')
    echo "invalid artifact version: $VERSION" >&2
    exit 1
    ;;
esac
case "$REPOSITORY" in
  *[!0-9A-Za-z._/-]*|'')
    echo "invalid GitHub repository: $REPOSITORY" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || {
  echo "curl is required for the public release smoke" >&2
  exit 1
}

mkdir -p "$DOWNLOAD_DIR" "$M2_DIR"
files=(
  SHA256SUMS
  "vev-java-$VERSION.jar"
  "vev-java-$VERSION-sources.jar"
  "vev-java-$VERSION-javadoc.jar"
  "vev-java-$VERSION.pom"
  "vev-clj-$VERSION.jar"
  "vev-clj-$VERSION-sources.jar"
  "vev-clj-$VERSION-javadoc.jar"
  "vev-clj-$VERSION.pom"
)

for file in "${files[@]}"; do
  curl \
    --fail \
    --location \
    --retry 5 \
    --retry-all-errors \
    --silent \
    --show-error \
    --output "$DOWNLOAD_DIR/$file" \
    "$BASE_URL/$file"
done

for file in "${files[@]:1}"; do
  expected="$(
    awk -v name="$file" '
      $2 == name || $2 == ("upload/" name) {
        print $1
        exit
      }
    ' "$DOWNLOAD_DIR/SHA256SUMS"
  )"
  [[ -n "$expected" ]] || {
    echo "$file is not listed in the published SHA256SUMS" >&2
    exit 1
  }
  actual="$(shasum -a 256 "$DOWNLOAD_DIR/$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "checksum mismatch for $file" >&2
    exit 1
  }
done

expected_native_resources="$TMP_DIR/expected-native-resources"
actual_native_resources="$TMP_DIR/actual-native-resources"
cat > "$expected_native_resources" <<'EOF'
com/vevdb/native/darwin-aarch64/libvev.dylib
com/vevdb/native/darwin-x86_64/libvev.dylib
com/vevdb/native/linux-aarch64/libvev.so
com/vevdb/native/linux-x86_64/libvev.so
com/vevdb/native/windows-x86_64/vev.dll
EOF
jar --list --file "$DOWNLOAD_DIR/vev-java-$VERSION.jar" |
  awk '/^com\/vevdb\/native\/.*\/(libvev\.(dylib|so)|vev\.dll)$/ {print}' |
  sort > "$actual_native_resources"
diff -u "$expected_native_resources" "$actual_native_resources"

jar --list --file "$DOWNLOAD_DIR/vev-java-$VERSION-sources.jar" |
  grep -qx 'com/vevdb/Vev.java'
jar --list --file "$DOWNLOAD_DIR/vev-java-$VERSION-javadoc.jar" |
  grep -qx 'com/vevdb/Vev.html'
jar --list --file "$DOWNLOAD_DIR/vev-clj-$VERSION-sources.jar" |
  grep -qx 'vev/core.clj'
jar --list --file "$DOWNLOAD_DIR/vev-clj-$VERSION-javadoc.jar" |
  grep -qx 'README.md'

for artifact in vev-java vev-clj; do
  artifact_dir="$M2_DIR/com/vevdb/$artifact/$VERSION"
  mkdir -p "$artifact_dir"
  cp \
    "$DOWNLOAD_DIR/$artifact-$VERSION.jar" \
    "$artifact_dir/$artifact-$VERSION.jar"
  cp \
    "$DOWNLOAD_DIR/$artifact-$VERSION.pom" \
    "$artifact_dir/$artifact-$VERSION.pom"
done

env -u VEV_LIB \
  "$ROOT/scripts/smoke_jvm_coordinates.sh" "$VERSION" "$M2_DIR"

echo "public JVM release smoke passed: https://github.com/$REPOSITORY/releases/tag/$TAG"
