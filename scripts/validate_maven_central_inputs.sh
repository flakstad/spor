#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/validate_maven_central_inputs.sh <version> <jvm-dir>" >&2
  exit 1
fi

VERSION="$1"
JVM_DIR="$(cd "$2" && pwd)"

case "$VERSION" in
  *[!0-9A-Za-z._-]*|'')
    echo "invalid Maven version: $VERSION" >&2
    exit 1
    ;;
esac

for artifact in vev-java vev-clj; do
  for suffix in .pom .jar -sources.jar -javadoc.jar; do
    file="$JVM_DIR/$artifact-$VERSION$suffix"
    [[ -f "$file" ]] || {
      echo "missing Maven Central input: $file" >&2
      exit 1
    }
  done

  pom="$JVM_DIR/$artifact-$VERSION.pom"
  grep -q '<groupId>com.vevdb</groupId>' "$pom"
  grep -q "<artifactId>$artifact</artifactId>" "$pom"
  grep -q "<version>$VERSION</version>" "$pom"
  grep -q '<licenses>' "$pom"
  grep -q '<developers>' "$pom"
  grep -q '<scm>' "$pom"
done

grep -q '<artifactId>vev-java</artifactId>' "$JVM_DIR/vev-clj-$VERSION.pom"
grep -q "<version>$VERSION</version>" "$JVM_DIR/vev-clj-$VERSION.pom"

jar --list --file "$JVM_DIR/vev-java-$VERSION-sources.jar" |
  grep -qx 'com/vevdb/Vev.java'
jar --list --file "$JVM_DIR/vev-java-$VERSION-javadoc.jar" |
  grep -qx 'com/vevdb/Vev.html'
jar --list --file "$JVM_DIR/vev-clj-$VERSION-sources.jar" |
  grep -qx 'vev/core.clj'
jar --list --file "$JVM_DIR/vev-clj-$VERSION-javadoc.jar" |
  grep -qx 'README.md'

echo ":vev-maven-central-inputs-ok"
