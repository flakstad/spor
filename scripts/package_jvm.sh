#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
OUT_DIR="$ROOT/build/jvm"
M2_DIR="$ROOT/build/m2"
JAVA_CLASSES="$OUT_DIR/classes/java"
CLOJURE_CLASSES="$OUT_DIR/classes/clojure"
NATIVE_CLASSES="$OUT_DIR/classes/native"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
NATIVE_ARTIFACT="vev-native-$PLATFORM"

rm -rf "$OUT_DIR" "$M2_DIR"
mkdir -p "$JAVA_CLASSES" "$CLOJURE_CLASSES" "$NATIVE_CLASSES"

write_pom() {
  local path="$1"
  local artifact="$2"
  local deps="${3:-}"

  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.vevdb</groupId>
  <artifactId>$artifact</artifactId>
  <version>$VERSION</version>
  <name>$artifact</name>
  <description>VevDB local JVM proof artifact.</description>
  <url>https://github.com/vevdb/vev</url>
  <licenses>
    <license>
      <name>Eclipse Public License 2.0</name>
      <url>https://www.eclipse.org/legal/epl-2.0/</url>
    </license>
  </licenses>$deps
</project>
EOF
}

java_dependency_block() {
  cat <<EOF
  <dependencies>
    <dependency>
      <groupId>dev.vevdb</groupId>
      <artifactId>$NATIVE_ARTIFACT</artifactId>
      <version>$VERSION</version>
    </dependency>
  </dependencies>
EOF
}

clojure_dependency_block() {
  cat <<EOF
  <dependencies>
    <dependency>
      <groupId>dev.vevdb</groupId>
      <artifactId>vev-java</artifactId>
      <version>$VERSION</version>
    </dependency>
  </dependencies>
EOF
}

install_artifact() {
  local artifact="$1"
  local jar_path="$2"
  local pom_path="$3"
  local artifact_dir="$M2_DIR/dev/vevdb/$artifact/$VERSION"

  mkdir -p "$artifact_dir"
  cp "$jar_path" "$artifact_dir/$artifact-$VERSION.jar"
  cp "$pom_path" "$artifact_dir/$artifact-$VERSION.pom"
}

javac \
  --enable-preview \
  --release 21 \
  -d "$JAVA_CLASSES" \
  "$ROOT/clients/java/src/main/java/dev/vevdb/vev/Vev.java"

jar --create \
  --date="$ARCHIVE_DATE" \
  --file "$OUT_DIR/vev-java-$VERSION.jar" \
  -C "$JAVA_CLASSES" .

write_pom "$OUT_DIR/vev-java-$VERSION.pom" "vev-java" "$(java_dependency_block)"

VEV_JVM_NATIVE_DIR="$NATIVE_CLASSES" "$ROOT/scripts/stage_jvm_native.sh" >/dev/null

jar --create \
  --date="$ARCHIVE_DATE" \
  --file "$OUT_DIR/$NATIVE_ARTIFACT-$VERSION.jar" \
  -C "$NATIVE_CLASSES" .

write_pom "$OUT_DIR/$NATIVE_ARTIFACT-$VERSION.pom" "$NATIVE_ARTIFACT"

cp -R "$ROOT/clients/clojure/src/." "$CLOJURE_CLASSES/"

jar --create \
  --date="$ARCHIVE_DATE" \
  --file "$OUT_DIR/vev-clj-$VERSION.jar" \
  -C "$CLOJURE_CLASSES" .

write_pom "$OUT_DIR/vev-clj-$VERSION.pom" "vev-clj" "$(clojure_dependency_block)"

install_artifact "vev-java" "$OUT_DIR/vev-java-$VERSION.jar" "$OUT_DIR/vev-java-$VERSION.pom"
install_artifact "$NATIVE_ARTIFACT" "$OUT_DIR/$NATIVE_ARTIFACT-$VERSION.jar" "$OUT_DIR/$NATIVE_ARTIFACT-$VERSION.pom"
install_artifact "vev-clj" "$OUT_DIR/vev-clj-$VERSION.jar" "$OUT_DIR/vev-clj-$VERSION.pom"

printf '%s\n' \
  "$OUT_DIR/vev-java-$VERSION.jar" \
  "$OUT_DIR/$NATIVE_ARTIFACT-$VERSION.jar" \
  "$OUT_DIR/vev-clj-$VERSION.jar" \
  "$M2_DIR"
