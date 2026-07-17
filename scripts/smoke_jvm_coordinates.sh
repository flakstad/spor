#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/smoke_jvm_coordinates.sh <version> <m2-dir>" >&2
  exit 1
fi

VERSION="$1"
M2_DIR="$(cd "$2" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-jvm-coordinates.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

command -v mvn >/dev/null 2>&1 || {
  echo "mvn is required for the fresh Java coordinate smoke" >&2
  exit 1
}

mkdir -p "$TMP_DIR/java/src/main/java/example" "$TMP_DIR/clojure"

cat > "$TMP_DIR/java/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>vev-coordinate-smoke</artifactId>
  <version>1.0.0</version>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
  </properties>
  <dependencies>
    <dependency>
      <groupId>dev.vevdb</groupId>
      <artifactId>vev-java</artifactId>
      <version>$VERSION</version>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
        <configuration><enablePreview>true</enablePreview></configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF

cat > "$TMP_DIR/java/src/main/java/example/Main.java" <<'EOF'
package example;

import dev.vevdb.vev.Vev;
import java.util.List;
import java.util.Map;

public final class Main {
    public static void main(String[] args) throws Throwable {
        try (Vev vev = Vev.load(); Vev.Connection conn = vev.createConn()) {
            conn.transact("[{:db/id 1 :user/name \"Ada\"}]");
            try (Vev.DB db = conn.db()) {
                List<List<Object>> rows = vev.queryRows(Map.of(
                    "query", "[:find ?name :where [?e :user/name ?name]]",
                    "args", List.of(db)));
                if (!rows.equals(List.of(List.of("Ada")))) {
                    throw new AssertionError(rows);
                }
            }
        }
        System.out.println("vev-java-coordinates-ok");
    }
}
EOF

(
  cd "$TMP_DIR/java"
  mvn -q -Dmaven.repo.local="$M2_DIR" package
  java \
    --enable-preview \
    --enable-native-access=ALL-UNNAMED \
    -cp "target/classes:$M2_DIR/dev/vevdb/vev-java/$VERSION/vev-java-$VERSION.jar" \
    example.Main
)

cat > "$TMP_DIR/clojure/deps.edn" <<EOF
{:mvn/local-repo "$M2_DIR"
 :deps {dev.vevdb/vev-clj {:mvn/version "$VERSION"}}
 :aliases {:run {:jvm-opts ["--enable-preview"
                            "--enable-native-access=ALL-UNNAMED"]}}}
EOF

(
  cd "$TMP_DIR/clojure"
  env -u VEV_LIB clojure -M:run -e "(require '[vev.core :as d])
(let [conn (d/create-conn)]
  (d/transact conn [{:db/id 1 :user/name \"Ada\"}])
  (assert (= #{[\"Ada\"]}
             (d/q '[:find ?name :where [?e :user/name ?name]]
                  (d/db conn)))))
(println :vev-clojure-coordinates-ok)"
)
