#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: scripts/assemble_jvm_release.sh <version> <output-dir> <m2-dir> <platform-jvm-dir>..." >&2
  exit 1
fi

VERSION="$1"
OUT_DIR="$2"
M2_DIR="$3"
shift 3
JVM_DIRS=("$@")
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/vev-jvm-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

write_pom() {
  local path="$1"
  local artifact="$2"
  local deps="${3:-}"
  local project_url="https://github.com/vevdb/vev"
  local repository="vev"
  local description="VevDB embedded native database."

  case "$artifact" in
    vev-java)
      project_url="https://github.com/vevdb/vev-java"
      repository="vev-java"
      description="Java Foreign Function and Memory wrapper for VevDB."
      ;;
    vev-clj)
      project_url="https://github.com/vevdb/vev-clj"
      repository="vev-clj"
      description="Clojure API for the VevDB embedded database."
      ;;
  esac

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
  <description>$description</description>
  <url>$project_url</url>
  <licenses>
    <license>
      <name>Eclipse Public License 2.0</name>
      <url>https://www.eclipse.org/legal/epl-2.0/</url>
    </license>
  </licenses>
  <developers>
    <developer>
      <name>Andreas Flakstad</name>
    </developer>
  </developers>
  <scm>
    <connection>scm:git:$project_url.git</connection>
    <developerConnection>scm:git:ssh://git@github.com/vevdb/$repository.git</developerConnection>
    <url>$project_url</url>
    <tag>HEAD</tag>
  </scm>$deps
</project>
EOF
}

install_artifact() {
  local artifact="$1"
  local artifact_dir="$M2_DIR/dev/vevdb/$artifact/$VERSION"

  mkdir -p "$artifact_dir"
  cp "$OUT_DIR/$artifact-$VERSION.jar" "$artifact_dir/"
  cp "$OUT_DIR/$artifact-$VERSION.pom" "$artifact_dir/"
  for file in \
    "$artifact_dir/$artifact-$VERSION.jar" \
    "$artifact_dir/$artifact-$VERSION.pom"; do
    shasum -a 1 "$file" | awk '{print $1}' > "$file.sha1"
  done
}

first_java=""
first_clj=""
java_hash=""
clj_hash=""
mkdir -p "$OUT_DIR" "$M2_DIR"

for jvm_dir in "${JVM_DIRS[@]}"; do
  java_jar="$jvm_dir/vev-java-$VERSION.jar"
  clj_jar="$jvm_dir/vev-clj-$VERSION.jar"
  native_jars=("$jvm_dir"/vev-native-*-"$VERSION".jar)

  [[ -f "$java_jar" ]] || { echo "missing JVM artifact: $java_jar" >&2; exit 1; }
  [[ -f "$clj_jar" ]] || { echo "missing JVM artifact: $clj_jar" >&2; exit 1; }
  [[ -f "${native_jars[0]}" ]] || { echo "missing native JVM artifact in $jvm_dir" >&2; exit 1; }

  current_java_hash="$(hash_file "$java_jar")"
  current_clj_hash="$(hash_file "$clj_jar")"
  if [[ -z "$first_java" ]]; then
    first_java="$java_jar"
    first_clj="$clj_jar"
    java_hash="$current_java_hash"
    clj_hash="$current_clj_hash"
    unzip -q "$java_jar" -d "$STAGE"
  elif [[ "$current_java_hash" != "$java_hash" || "$current_clj_hash" != "$clj_hash" ]]; then
    echo "platform-independent JVM artifacts differ across platform builds" >&2
    exit 1
  fi

  for native_jar in "${native_jars[@]}"; do
    unzip -q -o "$native_jar" -d "$STAGE"
  done
done

native_resource_count="$(
  find "$STAGE/dev/vevdb/vev/native" -type f 2>/dev/null | wc -l | tr -d ' '
)"
if [[ "$native_resource_count" -lt "${#JVM_DIRS[@]}" ]]; then
  echo "expected one distinct native resource from each platform JVM directory" >&2
  exit 1
fi

rm -rf "$STAGE/META-INF"
jar --create \
  --date="$ARCHIVE_DATE" \
  --file "$OUT_DIR/vev-java-$VERSION.jar" \
  -C "$STAGE" .
cp "$first_clj" "$OUT_DIR/vev-clj-$VERSION.jar"

write_pom "$OUT_DIR/vev-java-$VERSION.pom" "vev-java"
write_pom "$OUT_DIR/vev-clj-$VERSION.pom" "vev-clj" "
  <dependencies>
    <dependency>
      <groupId>dev.vevdb</groupId>
      <artifactId>vev-java</artifactId>
      <version>$VERSION</version>
    </dependency>
  </dependencies>"

install_artifact "vev-java"
install_artifact "vev-clj"

printf '%s\n' \
  "$OUT_DIR/vev-java-$VERSION.jar" \
  "$OUT_DIR/vev-clj-$VERSION.jar" \
  "$M2_DIR"
