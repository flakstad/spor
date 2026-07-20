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
(import '[com.vevdb Vev Vev$Datom Vev$Keyword Vev$TxReportListener])
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
  (.transact conn
             "[{:db/id 90 :db/ident :user/friend :db/valueType :db.type/ref}
               {:db/id 91 :db/ident :user/tags :db/cardinality :db.cardinality/many}
               {:db/id 1 :user/name \"Ada\" :user/friend 2 :user/tags [\"pioneer\"]}
               {:db/id 2 :user/name \"Grace\"}]")
  (with-open [db (.db conn)]
    (let [basis (.basisT db)
          relation (.query vev (java.util.Map/of
                                "query" "[:find ?name :where [?e :user/name ?name]]"
                                "args" (java.util.List/of db)))
          scalar (.query vev (java.util.Map/of
                              "query" "[:find ?name . :where [1 :user/name ?name]]"
                              "args" (java.util.List/of db)))]
      (assert (= 3 basis))
      (assert (= 4 (.nextT db)))
      (assert (nil? (.asOfT db)))
      (assert (nil? (.sinceT db)))
      (assert (false? (.isHistory db)))
      (with-open [ada (.entity db 1)]
        (assert (= 1 (bit-and 1 (.attrFlags ada ":user/friend"))))
        (assert (= 2 (bit-and 2 (.attrFlags ada ":user/tags")))))
      (let [raw-datoms (vec (.datoms db
                                     (Vev$Keyword. ":eavt")
                                     (object-array [1 (Vev$Keyword. ":user/name")])))]
        (assert (= 1 (count raw-datoms)))
        (assert (instance? Vev$Datom (first raw-datoms)))
        (assert (= "Ada" (.v ^Vev$Datom (first raw-datoms)))))
      (with-open [log (.log conn)]
        (assert (= 3 (count (.txRange log nil nil)))))
      (with-open [earlier (.asOf db (dec basis))
                  history (.history db)]
        (assert (= (dec basis) (.asOfT earlier)))
        (assert (.isHistory history)))
      (assert (= #{["Ada"] ["Grace"]} (set (map vec relation))))
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
  (d/transact conn
              [{:db/id 90
                :db/ident :user/friend
                :db/valueType :db.type/ref}
               {:db/id 91
                :db/ident :user/tags
                :db/cardinality :db.cardinality/many}
               {:db/id 92
                :db/ident :user/email
                :db/unique :db.unique/identity}
               {:db/id 1
                :user/name "Ada"
                :user/email "ada@example.com"
                :user/friend 2
                :user/tags ["pioneer"]}
               {:db/id 2
                :user/name "Grace"}])
  (assert (= #{["Ada"] ["Grace"]}
             (d/q '[:find ?name :where [?e :user/name ?name]]
                  (d/db conn))))
  (let [snapshot (d/db conn)
        ada (d/entity snapshot 1)
        friend (:user/friend ada)]
    (assert (= 1 (:db/id ada)))
    (assert (= "Ada" (:user/name ada)))
    (assert (= #{"pioneer"} (:user/tags ada)))
    (assert (= 2 (:db/id friend)))
    (assert (= "Grace" (:user/name friend)))
    (assert (contains? ada :user/name))
    (assert (not (map? ada)))
    (assert (= "Ada" (:user/name (into {} ada))))
    (assert (identical? snapshot (d/entity-db ada)))
    (assert (identical? ada (d/touch ada)))
    (assert (= 999 (:db/id (d/entity snapshot 999))))
    (assert (nil? (d/entity snapshot :user/missing)))
    (assert (nil? (d/entity snapshot [:user/email "missing@example.com"])))
    (assert (= 92 (d/entid snapshot :user/email)))
    (assert (= 92 (d/entid snapshot 92)))
    (assert (= :user/email (d/ident snapshot 92)))
    (assert (= :user/email (d/ident snapshot :user/email)))
    (let [name-datom (first (d/datoms snapshot :eavt 1 :user/name))
          lookup-name (first (d/datoms snapshot
                                       :eavt
                                       [:user/email "ada@example.com"]
                                       :user/name))
          email-range (d/index-range snapshot :user/email "a" "b")]
      (assert (= 1 (:e name-datom)))
      (assert (= :user/name (:a name-datom)))
      (assert (= "Ada" (:v name-datom)))
      (assert (= [1 :user/name "Ada" (:tx name-datom) true]
                 (vec name-datom)))
      (assert (= 1 (:e lookup-name)))
      (assert (= ["ada@example.com"] (mapv :v email-range)))
      (assert (= 2 (:e (first (d/seek-datoms snapshot :eavt 2)))))
      (assert (= 2 (:e (first (d/rseek-datoms snapshot :eavt 2)))))))
  (with-open [fns (d/tx-fns conn {:user/set-name
                                  (fn [db e name]
                                    [[:db/add e :user/name
                                      (str (:user/name (d/entity db e))
                                           "->"
                                           name)]])})]
    (d/transact conn [[:db/add 100 :db/ident :user/set-name]])
    (d/transact conn [[:db/add 2 :user/name "Intermediate"]
                      [:user/set-name 2 "Final"]]
                fns)
    (assert (= #{["Grace->Final"]}
               (d/q '[:find ?name :where [2 :user/name ?name]]
                    (d/db conn)))))
  (with-open [snapshot (d/db conn)
              earlier (d/as-of snapshot (dec (d/basis-t snapshot)))
              audit (d/history snapshot)]
    (assert (= (inc (d/basis-t snapshot)) (d/next-t snapshot)))
    (assert (nil? (d/as-of-t snapshot)))
    (assert (nil? (d/since-t snapshot)))
    (assert (= (dec (d/basis-t snapshot)) (d/as-of-t earlier)))
    (assert (d/history? audit))
    (assert (some (comp not :added)
                  (d/datoms audit :eavt 2 :user/name)))
    (assert (= (d/basis-t snapshot)
               (count (d/tx-range (d/log conn) nil nil))))
    (let [txs (d/q
                '[:find [?tx ...]
                  :in $ ?log ?start ?end
                  :where [(tx-ids ?log ?start ?end) [?tx ...]]]
                snapshot
                (d/log conn)
                nil
                nil)
          tx (first txs)
          datoms (d/q
                   '[:find ?e ?a ?v ?added
                     :in $ ?log ?tx
                     :where [(tx-data ?log ?tx) [[?e ?a ?v _ ?added]]]]
                   snapshot
                   (d/log conn)
                   tx)]
      (assert (= (d/basis-t snapshot) (count txs)))
      (assert (seq datoms))
      (assert (= 0 (d/tx->t (d/t->tx 0))))
      (assert (= tx (d/t->tx (d/tx->t tx))))
      (assert (= (d/basis-t snapshot)
                 (d/tx->t (d/t->tx (d/basis-t snapshot)))))))
  (println :vev-jvm-package-ok))

(let [file (java.io.File/createTempFile "vev-index-api-" ".vev")
      path (.getAbsolutePath file)]
  (.delete file)
  (try
    (with-open [conn (d/connect path)]
      (d/transact conn [{:db/id 80
                         :db/ident :item/score
                         :db/index true}
                        {:db/id 1 :item/score 10}
                        {:db/id 2 :item/score 20}])
      (let [snapshot (d/db conn)]
        (assert (= [10 20]
                   (mapv :v (d/datoms snapshot :avet :item/score))))
        (assert (= [20]
                   (mapv :v (d/index-range snapshot :item/score 15 nil))))))
    (finally
      (doseq [suffix ["" "-wal" "-shm"]]
        (java.nio.file.Files/deleteIfExists
         (java.nio.file.Path/of (str path suffix)
                                (make-array String 0)))))))
EOF

(
  cd "$TMP_DIR"
  clojure -Sdeps "$(cat deps-clj.edn)" -M:run clojure-smoke.clj
)
