;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns compare-aggregates-tutorial
  (:require [aggregates-tutorial :as vev-agg]
            [datomic.api :as datomic]
            [datomic.samples.repl :as repl]
            [vev.core :as vev]))

;; Port source of truth:
;; build/upstream/day-of-datomic/tutorial/aggregates.clj
;; Section: file top through schema attribute/value-type aggregate query.

(defn close-enough?
  [expected actual tolerance]
  (<= (Math/abs (- (double expected) (double actual))) tolerance))

(defn assert-close!
  [label expected actual tolerance]
  (when-not (close-enough? expected actual tolerance)
    (throw (ex-info "aggregate comparison mismatch"
                    {:label label
                     :expected expected
                     :actual actual
                     :tolerance tolerance}))))

(defn assert-equal!
  [label expected actual]
  (when-not (= expected actual)
    (throw (ex-info "aggregate comparison mismatch"
                    {:label label
                     :expected expected
                     :actual actual}))))

(defn datomic-db []
  (let [conn (repl/scratch-conn)]
    (repl/transact-all conn (repl/resource "day-of-datomic/bigger-than-pluto.edn"))
    [(datomic/db conn) conn]))

(defn datomic-summary []
  (let [[db conn] (datomic-db)]
    (try
      {:object-count (datomic/q vev-agg/object-count-query db)
       :largest-radius (datomic/q vev-agg/largest-radius-query db)
       :smallest-radius (datomic/q vev-agg/smallest-radius-query db)
       :average-radius (datomic/q vev-agg/average-radius-query db)
       :median-radius (datomic/q vev-agg/median-radius-query db)
       :stddev-radius (datomic/q vev-agg/stddev-radius-query db)
       :smallest-three-radii (vec (datomic/q vev-agg/smallest-three-radii-query db))
       :largest-three-radii (vec (datomic/q vev-agg/largest-three-radii-query db))
       :object-names (set (map first (datomic/q vev-agg/object-names-query db)))
       :schema-name-average-length (datomic/q vev-agg/schema-name-average-length-query db)
       :schema-name-modes (datomic/q vev-agg/schema-name-modes-query db)
       :schema-attribute-value-types (datomic/q vev-agg/schema-attribute-value-type-query db)}
      (finally
        (datomic/release conn)))))

(defn vev-summary []
  (vev-agg/setup!)
  (let [summary (vev-agg/validate-opening-aggregates!)
        conn (vev/connect vev-agg/default-uri)]
    (assoc summary
           :object-names
           (try
             (set (map first (vev/q vev-agg/object-names-query (vev/db conn))))
             (finally
               (.close conn))))))

(defn compare-portable! [vev datomic]
  (assert-equal! :object-count (:object-count datomic) (:object-count vev))
  (assert-equal! :largest-radius (:largest-radius datomic) (:largest-radius vev))
  (assert-equal! :smallest-radius (:smallest-radius datomic) (:smallest-radius vev))
  (assert-close! :average-radius (:average-radius datomic) (:average-radius vev) 0.0000001)
  (assert-equal! :median-radius (:median-radius datomic) (:median-radius vev))
  (assert-close! :stddev-radius (:stddev-radius datomic) (:stddev-radius vev) 0.0000001)
  (assert-equal! :smallest-three-radii (:smallest-three-radii datomic) (:smallest-three-radii vev))
  (assert-equal! :largest-three-radii (:largest-three-radii datomic) (:largest-three-radii vev)))

(defn -main [& _]
  (try
    (let [vev (vev-summary)
          datomic (datomic-summary)]
      (compare-portable! vev datomic)
      (println (pr-str {:source "aggregates-tutorial"
                        :portable-status :match
                        :vev-portable (select-keys vev [:object-count
                                                         :largest-radius
                                                         :smallest-radius
                                                         :average-radius
                                                         :median-radius
                                                         :stddev-radius
                                                         :smallest-three-radii
                                                         :largest-three-radii])
                        :datomic-portable (select-keys datomic [:object-count
                                                                :largest-radius
                                                                :smallest-radius
                                                                :average-radius
                                                                :median-radius
                                                                :stddev-radius
                                                                :smallest-three-radii
                                                                :largest-three-radii])
                        :schema-status :intentional-datomic-system-schema-difference
                        :vev-schema (select-keys vev [:schema-name-average-length
                                                      :schema-name-modes
                                                      :schema-attribute-value-types])
                        :datomic-schema (select-keys datomic [:schema-name-average-length
                                                              :schema-name-modes
                                                              :schema-attribute-value-types])})))
    (finally
      (datomic/shutdown true))))

(-main)
