#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: scripts/package_maven_central_bundle.sh <version> <jvm-dir> <output.zip>" >&2
  exit 1
fi

VERSION="$1"
JVM_DIR="$(cd "$2" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$3")" && pwd)"
OUTPUT="$OUTPUT_DIR/$(basename "$3")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-central-bundle.XXXXXX")"
STAGE="$TMP_DIR/stage"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

: "${CENTRAL_GPG_KEY_ID:?CENTRAL_GPG_KEY_ID is required}"
: "${CENTRAL_GPG_PASSPHRASE:?CENTRAL_GPG_PASSPHRASE is required}"

command -v gpg >/dev/null 2>&1 || {
  echo "gpg is required" >&2
  exit 1
}
command -v zip >/dev/null 2>&1 || {
  echo "zip is required" >&2
  exit 1
}

"$ROOT/scripts/validate_maven_central_inputs.sh" "$VERSION" "$JVM_DIR"

checksum() {
  local algorithm="$1"
  local file="$2"

  if command -v "${algorithm}sum" >/dev/null 2>&1; then
    "${algorithm}sum" "$file" | awk '{print $1}'
  else
    openssl dgst "-$algorithm" -r "$file" | awk '{print $1}'
  fi
}

for artifact in vev-java vev-clj; do
  artifact_dir="$STAGE/com/vevdb/$artifact/$VERSION"
  mkdir -p "$artifact_dir"

  for suffix in .pom .jar -sources.jar -javadoc.jar; do
    source="$JVM_DIR/$artifact-$VERSION$suffix"
    target="$artifact_dir/$artifact-$VERSION$suffix"
    cp "$source" "$target"

    printf '%s' "$CENTRAL_GPG_PASSPHRASE" |
      gpg \
        --batch \
        --yes \
        --pinentry-mode loopback \
        --passphrase-fd 0 \
        --local-user "$CENTRAL_GPG_KEY_ID" \
        --armor \
        --detach-sign \
        --output "$target.asc" \
        "$target"

    checksum md5 "$target" > "$target.md5"
    checksum sha1 "$target" > "$target.sha1"
  done
done

rm -f "$OUTPUT"
(
  cd "$STAGE"
  zip -q -r "$OUTPUT" com
)

unzip -tq "$OUTPUT" >/dev/null
echo "$OUTPUT"
