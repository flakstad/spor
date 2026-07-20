#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"

case "$(uname -s)" in
  Darwin) LIB_NAME="libvev.dylib"; M2_REPO="$ROOT/build/m2" ;;
  Linux) LIB_NAME="libvev.so"; M2_REPO="$ROOT/build/m2" ;;
  MINGW*|MSYS*|CYGWIN*) LIB_NAME="vev.dll"; M2_REPO="$(cygpath -m "$ROOT/build/m2")" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [[ ! -f "$ROOT/build/lib/$LIB_NAME" ]]; then
  "$ROOT/scripts/build_c_abi.sh"
fi

"$ROOT/scripts/package_jvm.sh" >/dev/null

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-jvm-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/deps-java.edn" <<EOF
{:mvn/local-repo "$M2_REPO"
 :deps {com.vevdb/vev-java {:mvn/version "$VERSION"}}
 :aliases {:run {:jvm-opts ["--enable-native-access=ALL-UNNAMED"]}}}
EOF

cat > "$TMP_DIR/java-smoke.clj" <<'EOF'
(import '[com.vevdb Vev Vev$TxReportListener])
(with-open [vev (Vev/load)
            conn (.createConn vev)]
  (let [seen (atom 0)]
    (with-open [listener (.listen conn "java-listener"
                                  (reify Vev$TxReportListener
                                    (accept [_ report]
                                      (when (.contains (str report) ":user/listener")
                                        (swap! seen inc)))))]
      (.transact conn "[[:db/add 1 :user/listener \"heard\"]]")
      (assert (= 1 @seen)))
    (.transact conn "[[:db/add 1 :user/listener \"after-close\"]]")
    (assert (= 1 @seen)))
  (.transact conn "[{:db/id 1 :user/name \"Ada\"}]")
  (with-open [db (.db conn)]
    (let [relation (.query vev (java.util.Map/of
                                "query" "[:find ?name :where [?e :user/name ?name]]"
                                "args" (java.util.List/of db)))
          scalar (.query vev (java.util.Map/of
                              "query" "[:find ?name . :where [1 :user/name ?name]]"
                              "args" (java.util.List/of db)))]
      (assert (= #{["Ada"]} (set (map vec relation))))
      (assert (= "Ada" scalar))))
  (println :vev-java-package-ok))
EOF

(
  cd "$TMP_DIR"
  clojure -Sdeps "$(cat deps-java.edn)" -M:run java-smoke.clj
)

cat > "$TMP_DIR/deps-clj.edn" <<EOF
{:mvn/local-repo "$M2_REPO"
 :deps {com.vevdb/vev-clj {:mvn/version "$VERSION"}}
 :aliases {:run {:jvm-opts ["--enable-native-access=ALL-UNNAMED"]}}}
EOF

cat > "$TMP_DIR/clojure-smoke.clj" <<'EOF'
(require '[vev.core :as d])
(let [conn (d/create-conn)]
  (let [seen (atom [])]
    (with-open [listener (d/listen conn :clj-listener #(swap! seen conj (:tx-data %)))]
      (d/transact conn [[:db/add 1 :user/listener "heard"]])
      (assert (= 1 (count @seen))))
    (d/transact conn [[:db/add 1 :user/listener "after-close"]])
    (assert (= 1 (count @seen))))
  (d/transact conn [{:db/id 1 :user/name "Ada"}])
  (assert (= #{["Ada"]}
             (d/q '[:find ?name :where [?e :user/name ?name]]
                  (d/db conn))))
  (with-open [fns (d/tx-fns conn {:user/set-name
                                  (fn [db e name]
                                    [[:db/add e :user/name name]])})]
    (d/transact conn [[:db/add 100 :db/ident :user/set-name]])
    (d/transact conn [[:user/set-name 2 "Grace"]] fns)
    (assert (= #{["Grace"]}
               (d/q '[:find ?name :where [2 :user/name ?name]]
                    (d/db conn)))))
  (println :vev-jvm-package-ok))
EOF

(
  cd "$TMP_DIR"
  clojure -Sdeps "$(cat deps-clj.edn)" -M:run clojure-smoke.clj
)
