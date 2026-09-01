(ns aggregates-tutorial
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [vev.core :as d]))

;; Port source of truth:
;; build/upstream/day-of-datomic/tutorial/aggregates.clj
;; Section: file top through schema attribute/value-type aggregate query.
;; Fixture:
;; build/upstream/day-of-datomic/resources/day-of-datomic/bigger-than-pluto.edn

(def default-uri "build/day-of-datomic/vev-aggregates.sqlite")
(def fixture-path "build/upstream/day-of-datomic/resources/day-of-datomic/bigger-than-pluto.edn")

(def object-count-query
  '[:find (count ?e) .
    :where [?e :object/name ?n]])

(def object-names-query
  '[:find ?name
    :where [?e :object/name ?name]])

(def largest-radius-query
  '[:find (max ?radius) .
    :where [_ :object/meanRadius ?radius]])

(def smallest-radius-query
  '[:find (min ?radius) .
    :where [_ :object/meanRadius ?radius]])

(def average-radius-query
  '[:find (avg ?radius) .
    :with ?e
    :where [?e :object/meanRadius ?radius]])

(def median-radius-query
  '[:find (median ?radius) .
    :with ?e
    :where [?e :object/meanRadius ?radius]])

(def stddev-radius-query
  '[:find (stddev ?radius) .
    :with ?e
    :where [?e :object/meanRadius ?radius]])

(def random-object-name-query
  '[:find (rand ?name) .
    :where [?e :object/name ?name]])

(def smallest-three-radii-query
  '[:find (min 3 ?radius) .
    :with ?e
    :where [?e :object/meanRadius ?radius]])

(def largest-three-radii-query
  '[:find (max 3 ?radius) .
    :with ?e
    :where [?e :object/meanRadius ?radius]])

(def five-random-object-names-query
  '[:find (rand 5 ?name) .
    :with ?e
    :where [?e :object/name ?name]])

(def five-sampled-object-names-query
  '[:find (sample 5 ?name) .
    :with ?e
    :where [?e :object/name ?name]])

(def schema-name-average-length-query
  '[:find (avg ?length) .
    :with ?e
    :where
    [?e :db/ident ?ident]
    [(name ?ident) ?name]
    [(count ?name) ?length]])

(def schema-name-modes-query
  '[:find (datomic.samples.repl/modes ?length) .
    :with ?e
    :where
    [?e :db/ident ?ident]
    [(name ?ident) ?name]
    [(count ?name) ?length]])

(def schema-attribute-value-type-query
  '[:find (count ?a) (count-distinct ?vt)
    :where
    [?a :db/ident ?ident]
    [?a :db/valueType ?vt]])

(defn schema-name-modes
  [coll]
  (->> (frequencies coll)
       (reduce
        (fn [[modes ct] [k v]]
          (cond
            (< v ct) [modes ct]
            (= v ct) [(conj modes k) ct]
            (> v ct) [#{k} v]))
        [#{} 2])
       first))

(intern (create-ns 'datomic.samples.repl) 'modes schema-name-modes)

(defn- remove-store! [uri]
  (doseq [suffix ["" "-wal" "-shm"]]
    (let [file (io/file (str uri suffix))]
      (when (.exists file)
        (when-not (.delete file)
          (throw (ex-info "could not delete existing Vev store"
                          {:path (.getPath file)})))))))

(defn- normalize-upstream-entity [entity]
  (if (map? entity)
    (dissoc entity :db.install/_attribute)
    entity))

(defn- normalize-upstream-form [form]
  (if (vector? form)
    (mapv normalize-upstream-entity form)
    form))

(defn- aggregate-fact-form? [form]
  (and (vector? form)
       (some #(and (map? %)
                   (or (contains? % :db/ident)
                       (and (contains? % :object/name)
                            (contains? % :object/meanRadius))))
             form)))

(defn- read-upstream-forms []
  (let [counter (atom 0)
        eof (Object.)]
    (with-open [reader (java.io.PushbackReader. (io/reader fixture-path))]
      (loop [forms []]
        (let [form (edn/read {:eof eof
                              :readers {'db/id (fn [_]
                                                 (str "__dbid_" (swap! counter inc)))}}
                             reader)]
          (if (identical? eof form)
            forms
            (recur (conj forms (normalize-upstream-form form)))))))))

(defn setup! []
  (remove-store! default-uri)
  (io/make-parents default-uri)
  (with-open [conn (d/connect default-uri)]
    (doseq [tx (filter aggregate-fact-form? (read-upstream-forms))]
      (d/transact conn tx))
    (d/connection-info conn)))

(defn- close-enough? [expected actual tolerance]
  (<= (Math/abs (- expected actual)) tolerance))

(defn validate-opening-aggregates! []
  (with-open [conn (d/connect default-uri)]
    (let [db (d/db conn)
          object-count (d/q object-count-query db)
          largest-radius (d/q largest-radius-query db)
          smallest-radius (d/q smallest-radius-query db)
          average-radius (d/q average-radius-query db)
          median-radius (d/q median-radius-query db)
          stddev-radius (d/q stddev-radius-query db)
          random-object-name (d/q random-object-name-query db)
          smallest-three-radii (d/q smallest-three-radii-query db)
          largest-three-radii (d/q largest-three-radii-query db)
          five-random-object-names (d/q five-random-object-names-query db)
          five-sampled-object-names (d/q five-sampled-object-names-query db)
          schema-name-average-length (d/q schema-name-average-length-query db)
          schema-name-modes (d/q schema-name-modes-query db)
          schema-attribute-value-types (d/q schema-attribute-value-type-query db)
          object-names (set (map first (d/q object-names-query db)))]
      (assert (= 17 object-count))
      (assert (= 696000.0 largest-radius))
      (assert (= 1163.0 smallest-radius))
      (assert (= 53390.17647058824 average-radius))
      (assert (= 2631.2 median-radius))
      (assert (close-enough? 161902.52780945456 stddev-radius 0.0000001))
      (assert (string? random-object-name))
      (assert (contains? object-names random-object-name))
      (assert (= [1163.0 1353.4 1561.0] smallest-three-radii))
      (assert (= [696000.0 69911.0 58232.0] largest-three-radii))
      (assert (seq? five-random-object-names))
      (assert (= 5 (count five-random-object-names)))
      (assert (every? string? five-random-object-names))
      (assert (every? object-names five-random-object-names))
      (assert (vector? five-sampled-object-names))
      (assert (= 5 (count five-sampled-object-names)))
      (assert (= 5 (count (set five-sampled-object-names))))
      (assert (every? string? five-sampled-object-names))
      (assert (every? object-names five-sampled-object-names))
      (assert (close-enough? 6.666666666666667 schema-name-average-length 0.0000001))
      (assert (= #{} schema-name-modes))
      (assert (= #{[3 2]} schema-attribute-value-types))
      {:object-count object-count
       :largest-radius largest-radius
       :smallest-radius smallest-radius
       :average-radius average-radius
       :median-radius median-radius
       :stddev-radius stddev-radius
       :random-object-name random-object-name
       :smallest-three-radii smallest-three-radii
       :largest-three-radii largest-three-radii
       :five-random-object-names five-random-object-names
       :five-sampled-object-names five-sampled-object-names
       :schema-name-average-length schema-name-average-length
       :schema-name-modes schema-name-modes
       :schema-attribute-value-types schema-attribute-value-types})))
