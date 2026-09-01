(ns decomposing-query
  (:require [vev.core :as d]))

;; Port source of truth:
;; build/upstream/day-of-datomic/tutorial/decomposing_a_query.clj
;; Section: opening in-memory `kvs` relation and first slow-query
;; decomposition examples.

(def kvs
  (into [] (for [e (range 2000)
                 a [:a :b :c :d :e]]
             [e a e])))

(def slow-query
  '[:find ?e1 ?e2
    :where
    [?e1 :a ?v1]
    [?e2 :a ?v2]
    [?e1 :a 10]
    [?e2 :a ?e1]])

(def drop-last-clause-query
  '[:find ?e1 ?e2
    :where
    [?e1 :a ?v1]
    [?e2 :a ?v2]
    [?e1 :a 10]])

(def cross-product-query
  '[:find ?e1 ?e2
    :where
    [?e1 :a ?v1]
    [?e2 :a ?v2]])

(def single-clause-query
  '[:find ?e1
    :where
    [?e1 :a ?v1]])

(def reordered-query
  '[:find ?e1 ?e2
    :where
    [?e1 :a ?v1]
    [?e1 :a 10]
    [?e2 :a ?e1]
    [?e2 :a ?v2]])

(def better-query
  '[:find ?e1 ?e2
    :in $ ?e1
    :where [?e2 :a ?e1]])

(defn query-count [query & inputs]
  (count (d/query {:query query
                   :args (into [kvs] inputs)
                   :timeout 10000})))

(defn validate-opening-decomposition! []
  (let [slow (query-count slow-query)
        dropped (query-count drop-last-clause-query)
        cross (query-count cross-product-query)
        single (query-count single-clause-query)
        reordered (query-count reordered-query)
        better (d/query {:query better-query
                         :args [kvs 10]
                         :timeout 10000})]
    (assert (= 10000 (count kvs)))
    (assert (= 1 slow))
    (assert (= 2000 dropped))
    (assert (= 4000000 cross))
    (assert (= 2000 single))
    (assert (= 1 reordered))
    (assert (= #{[10 10]} better))
    {:kvs-count (count kvs)
     :slow-query-count slow
     :drop-last-clause-count dropped
     :cross-product-count cross
     :single-clause-count single
     :reordered-query-count reordered
     :better-query better}))

(defn cross-product-timeout-example []
  (d/query {:query cross-product-query
            :args [kvs]
            :timeout 10000}))
