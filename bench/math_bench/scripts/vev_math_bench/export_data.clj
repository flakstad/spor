;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns vev-math-bench.export-data
  (:require
   [clojure.java.io :as io]
   [jsonista.core :as json]))

(def schema-tx
  [[:db/add 100 :db/ident :dissertation/cid]
   [:db/add 100 :db/valueType :db.type/ref]
   [:db/add 101 :db/ident :dissertation/title]
   [:db/add 102 :db/ident :dissertation/univ]
   [:db/add 102 :db/index true]
   [:db/add 103 :db/ident :dissertation/country]
   [:db/add 104 :db/ident :dissertation/year]
   [:db/add 105 :db/ident :dissertation/area]
   [:db/add 105 :db/index true]
   [:db/add 106 :db/ident :person/name]
   [:db/add 106 :db/index true]
   [:db/add 107 :db/ident :person/advised]
   [:db/add 107 :db/valueType :db.type/ref]
   [:db/add 107 :db/cardinality :db.cardinality/many]])

(defn parse-args [args]
  (loop [opts {:input nil
               :output-dir "build/math_bench"
               :chunk-size 50000}
         args args]
    (if-let [arg (first args)]
      (case arg
        "--input" (recur (assoc opts :input (second args)) (nnext args))
        "--output-dir" (recur (assoc opts :output-dir (second args)) (nnext args))
        "--chunk-size" (recur (assoc opts :chunk-size (parse-long (second args))) (nnext args))
        (throw (ex-info "unknown option" {:arg arg})))
      (if (:input opts)
        opts
        (throw (ex-info "missing required --input" {}))))))

(defn read-json [path]
  (with-open [in (io/input-stream path)]
    (json/read-value
      (if (.endsWith path ".gz")
        (java.util.zip.GZIPInputStream. in)
        in)
      json/keyword-keys-object-mapper)))

(defn writer-state [output-dir]
  {:output-dir output-dir
   :chunk-index 0
   :chunk-item-count 0
   :total-item-count 0
   :writer nil})

(defn chunk-path [output-dir chunk-index]
  (format "%s/values-%04d.edn" output-dir chunk-index))

(defn open-chunk [state]
  (let [path (chunk-path (:output-dir state) (:chunk-index state))
        writer (io/writer path)]
    (.write writer "[")
    (assoc state :writer writer :chunk-item-count 0)))

(defn close-chunk [state]
  (if-let [writer (:writer state)]
    (do
      (.write writer "]\n")
      (.close writer)
      (assoc state :writer nil))
    state))

(defn rotate-if-needed [state chunk-size]
  (if (and (:writer state) (>= (:chunk-item-count state) chunk-size))
    (-> state
        close-chunk
        (update :chunk-index inc))
    state))

(defn write-op [state chunk-size op]
  (let [state (cond-> state
                (nil? (:writer state)) open-chunk)
        writer (:writer state)]
    (when (pos? (:chunk-item-count state))
      (.write writer "\n "))
    (binding [*out* writer]
      (pr op))
    (-> state
        (update :chunk-item-count inc)
        (update :total-item-count inc)
        (rotate-if-needed chunk-size))))

(defn write-schema! [output-dir]
  (io/make-parents (str output-dir "/schema.edn"))
  (with-open [writer (io/writer (str output-dir "/schema.edn"))]
    (binding [*out* writer]
      (pr schema-tx)
      (newline))))

(defn emit-optional [state chunk-size entity attr value]
  (if (some? value)
    (write-op state chunk-size [:db/add entity attr value])
    state))

(defn emit-node [state chunk-size cids dcounter node]
  (if (nil? (:name node))
    state
    (let [person-id (:id node)
          dissertation-id (vswap! dcounter inc)
          advisors (filter cids (:advisors node))]
      (as-> state s
        (write-op s chunk-size [:db/add dissertation-id :dissertation/cid person-id])
        (write-op s chunk-size [:db/add person-id :person/name (:name node)])
        (emit-optional s chunk-size dissertation-id :dissertation/title (:thesis node))
        (emit-optional s chunk-size dissertation-id :dissertation/univ (:school node))
        (emit-optional s chunk-size dissertation-id :dissertation/country (:country node))
        (emit-optional s chunk-size dissertation-id :dissertation/year (:year node))
        (emit-optional s chunk-size dissertation-id :dissertation/area (:subject node))
        (reduce
          (fn [acc advisor-id]
            (write-op acc chunk-size [:db/add advisor-id :person/advised dissertation-id]))
          s
          advisors)))))

(defn export! [{:keys [input output-dir chunk-size]}]
  (let [data (read-json input)
        nodes (:nodes data)
        cids (into #{} (map :id) nodes)
        dcounter (volatile! 1000000)]
    (io/make-parents (str output-dir "/values-0000.edn"))
    (write-schema! output-dir)
    (let [state (reduce
                  (fn [state node]
                    (emit-node state chunk-size cids dcounter node))
                  (writer-state output-dir)
                  nodes)
          state (close-chunk state)
          chunk-count (if (pos? (:total-item-count state))
                        (inc (:chunk-index state))
                        0)]
      (spit (str output-dir "/manifest.edn")
            (pr-str {:schema "schema.edn"
                     :values-prefix "values"
                     :chunks chunk-count
                     :tx-count (:total-item-count state)
                     :source input}))
      (println "schema=" (str output-dir "/schema.edn"))
      (println "values_prefix=" (str output-dir "/values"))
      (println "chunks=" chunk-count)
      (println "tx_count=" (:total-item-count state)))))

(defn -main [& args]
  (export! (parse-args args)))
