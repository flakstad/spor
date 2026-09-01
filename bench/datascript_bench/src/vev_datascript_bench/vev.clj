(ns vev-datascript-bench.vev
  (:require [vev.core :as v]
            [vev-datascript-bench.core :as core]))

(def schema-tx
  [{:db/id 100 :db/ident :follows :db/valueType :db.type/ref :db/cardinality :db.cardinality/many}
   {:db/id 101 :db/ident :name :db/valueType :db.type/string}
   {:db/id 102 :db/ident :last-name :db/valueType :db.type/string}
   {:db/id 103 :db/ident :sex :db/valueType :db.type/keyword}
   {:db/id 104 :db/ident :age :db/valueType :db.type/long}
   {:db/id 105 :db/ident :salary :db/valueType :db.type/long}])

(defn library-path []
  (or (System/getProperty "vev.library")
      (System/getenv "VEV_LIB")
      "build/lib/libvev.dylib"))

(defn db-with-bulk [db entities]
  (let [datom-count (reduce + 0 (map #(dec (count %)) entities))]
    (with-open [tx (v/tx-builder db datom-count)]
      (v/bulk-add! tx entities)
      (v/db-with db tx))))

(defn people-db []
  (with-open [initial (v/empty-db (library-path))
              schema-db (db-with-bulk initial schema-tx)]
    (db-with-bulk schema-db @core/people20k)))

(def shared-db (delay (people-db)))

(defn isolated-dbs? []
  (= "true" (System/getenv "VEV_BENCH_ISOLATED_DBS")))

(defn bench-db []
  (if (isolated-dbs?)
    (delay (people-db))
    shared-db))

(def db100k-1 (bench-db))
(def db100k-2 (bench-db))
(def db100k-2s (bench-db))
(def db100k-3 (bench-db))
(def db100k-4 (bench-db))
(def db100k-5 (bench-db))
(def db100k-p1 (bench-db))
(def db100k-p2 (bench-db))

(def q1-query
  '[:find ?e
    :where [?e :name "Ivan"]])

(def q2-query
  '[:find ?e ?a
    :where
    [?e :name "Ivan"]
    [?e :age ?a]])

(def q2-switch-query
  '[:find ?e ?a
    :where
    [?e :age ?a]
    [?e :name "Ivan"]])

(def q3-query
  '[:find ?e ?a
    :where
    [?e :name "Ivan"]
    [?e :age ?a]
    [?e :sex :male]])

(def q4-query
  '[:find ?e ?l ?a
    :where
    [?e :name "Ivan"]
    [?e :last-name ?l]
    [?e :age ?a]
    [?e :sex :male]])

(def q5-query
  '[:find ?e1 ?l ?a
    :where
    [?e :name "Ivan"]
    [?e :age ?a]
    [?e1 :age ?a]
    [?e1 :last-name ?l]])

(def qpred1-query
  '[:find ?e ?s
    :where
    [?e :salary ?s]
    [(> ?s 50000)]])

(def qpred2-query
  '[:find ?e ?s
    :in $ ?min-s
    :where
    [?e :salary ?s]
    [(> ?s ?min-s)]])

(defn wide-entities
  ([depth width]
   (wide-entities 1 depth width))
  ([id depth width]
   (if (pos? depth)
     (let [children (map #(+ (* id width) %) (range width))]
       (concat
         (map (fn [child]
                {:db/id id
                 :name "Ivan"
                 :follows (v/entity child)})
              children)
         (mapcat #(wide-entities % (dec depth) width) children)))
     [{:db/id id :name "Ivan"}])))

(defn long-entities [depth width]
  (apply concat
         (for [x (range width)
               y (range depth)
               :let [from (+ (* x (inc depth)) y)
                     to (+ (* x (inc depth)) y 1)]]
           [{:db/id (inc from)
             :name "Ivan"
             :follows (v/entity (inc to))}
            {:db/id (inc to)
             :name "Ivan"}])))

(defn rule-db [entities]
  (with-open [initial (v/empty-db (library-path))
              schema-db (db-with-bulk initial schema-tx)]
    (db-with-bulk schema-db entities)))

(defn bench-rules [db]
  (v/q '[:find ?e ?e2
         :in $ %
         :where (follows ?e ?e2)]
       db
       '[[(follows ?x ?y)
          [?x :follows ?y]]
         [(follows ?x ?y)
          [?x :follows ?t]
          (follows ?t ?y)]]))

(defn q1 []
  (core/bench
    (v/q q1-query @db100k-1)))

(defn q1-prepared []
  (with-open [prepared (v/prepare @db100k-1 q1-query)]
    (core/bench
      (v/q prepared @db100k-1))))

(defn q1-rows-prepared []
  (with-open [prepared (v/prepare @db100k-1 q1-query)]
    (core/bench
      (v/rows prepared @db100k-1))))

(defn q1-profile-prepared []
  (with-open [prepared (v/prepare @db100k-1 q1-query)]
    (core/bench
      (v/profile prepared @db100k-1))))

(defn q2 []
  (core/bench
    (v/q q2-query @db100k-2)))

(defn q2-prepared []
  (with-open [prepared (v/prepare @db100k-2 q2-query)]
    (core/bench
      (v/q prepared @db100k-2))))

(defn q2-rows-prepared []
  (with-open [prepared (v/prepare @db100k-2 q2-query)]
    (core/bench
      (v/rows prepared @db100k-2))))

(defn q2-columns-prepared []
  (with-open [prepared (v/prepare @db100k-2 q2-query)]
    (core/bench
      (v/column-batch prepared @db100k-2))))

(defn q2-profile-prepared []
  (with-open [prepared (v/prepare @db100k-2 q2-query)]
    (core/bench
      (v/profile prepared @db100k-2))))

(defn q2-switch []
  (core/bench
    (v/q q2-switch-query @db100k-2s)))

(defn q2-switch-prepared []
  (with-open [prepared (v/prepare @db100k-2s q2-switch-query)]
    (core/bench
      (v/q prepared @db100k-2s))))

(defn q2-switch-rows-prepared []
  (with-open [prepared (v/prepare @db100k-2s q2-switch-query)]
    (core/bench
      (v/rows prepared @db100k-2s))))

(defn q3 []
  (core/bench
    (v/q q3-query @db100k-3)))

(defn q3-prepared []
  (with-open [prepared (v/prepare @db100k-3 q3-query)]
    (core/bench
      (v/q prepared @db100k-3))))

(defn q3-rows-prepared []
  (with-open [prepared (v/prepare @db100k-3 q3-query)]
    (core/bench
      (v/rows prepared @db100k-3))))

(defn q4 []
  (core/bench
    (v/q q4-query @db100k-4)))

(defn q4-prepared []
  (with-open [prepared (v/prepare @db100k-4 q4-query)]
    (core/bench
      (v/q prepared @db100k-4))))

(defn q4-rows-prepared []
  (with-open [prepared (v/prepare @db100k-4 q4-query)]
    (core/bench
      (v/rows prepared @db100k-4))))

(defn q4-columns-prepared []
  (with-open [prepared (v/prepare @db100k-4 q4-query)]
    (core/bench
      (v/column-batch prepared @db100k-4))))

(defn q5 []
  (core/bench
    (v/q q5-query @db100k-5)))

(defn q5-prepared []
  (with-open [prepared (v/prepare @db100k-5 q5-query)]
    (core/bench
      (v/q prepared @db100k-5))))

(defn q5-rows-prepared []
  (with-open [prepared (v/prepare @db100k-5 q5-query)]
    (core/bench
      (v/rows prepared @db100k-5))))

(defn q5-columns-prepared []
  (with-open [prepared (v/prepare @db100k-5 q5-query)]
    (core/bench
      (v/column-batch prepared @db100k-5))))

(defn qpred1 []
  (core/bench
    (v/q qpred1-query @db100k-p1)))

(defn qpred1-prepared []
  (with-open [prepared (v/prepare @db100k-p1 qpred1-query)]
    (core/bench
      (v/q prepared @db100k-p1))))

(defn qpred1-rows-prepared []
  (with-open [prepared (v/prepare @db100k-p1 qpred1-query)]
    (core/bench
      (v/rows prepared @db100k-p1))))

(defn qpred1-columns-prepared []
  (with-open [prepared (v/prepare @db100k-p1 qpred1-query)]
    (core/bench
      (v/column-batch prepared @db100k-p1))))

(defn qpred2 []
  (core/bench
    (v/q qpred2-query @db100k-p2 50000)))

(defn qpred2-prepared []
  (with-open [prepared (v/prepare @db100k-p2 qpred2-query)]
    (core/bench
      (v/q prepared @db100k-p2 50000))))

(defn qpred2-rows-prepared []
  (with-open [prepared (v/prepare @db100k-p2 qpred2-query)]
    (core/bench
      (v/rows prepared @db100k-p2 50000))))

(defn qpred2-columns-prepared []
  (with-open [prepared (v/prepare @db100k-p2 qpred2-query)]
    (core/bench
      (v/column-batch prepared @db100k-p2 50000))))

(defn rules-wide-3x3 []
  (with-open [db (rule-db (wide-entities 3 3))]
    (core/bench
      (bench-rules db))))

(defn rules-wide-5x3 []
  (with-open [db (rule-db (wide-entities 5 3))]
    (core/bench
      (bench-rules db))))

(defn rules-wide-7x3 []
  (with-open [db (rule-db (wide-entities 7 3))]
    (core/bench
      (bench-rules db))))

(defn rules-wide-4x6 []
  (with-open [db (rule-db (wide-entities 4 6))]
    (core/bench
      (bench-rules db))))

(defn rules-long-10x3 []
  (with-open [db (rule-db (long-entities 10 3))]
    (core/bench
      (bench-rules db))))

(defn rules-long-30x3 []
  (with-open [db (rule-db (long-entities 30 3))]
    (core/bench
      (bench-rules db))))

(defn rules-long-30x5 []
  (with-open [db (rule-db (long-entities 30 5))]
    (core/bench
      (bench-rules db))))

(def default-benchmarks
  ["q1" "q2" "q2-switch" "q3" "q4" "qpred1" "qpred2"])

(defn -main [& names]
  (let [names (if (seq names) names default-benchmarks)]
    (doseq [n names]
      (if-some [benchmark (ns-resolve 'vev-datascript-bench.vev (symbol n))]
        (let [perf (benchmark)]
          (print (core/round perf) "\t")
          (flush))
        (do
          (print "---" "\t")
          (flush))))
    (println)))
