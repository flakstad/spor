;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns history-time-filters
  "Executable Datomic Peer/Vev parity example for as-of, since, and history."
  (:require [datomic.api :as datomic]
            [vev.core :as vev])
  (:import [java.nio.file Files Path]
           [java.util Date UUID]))

(def value-query
  '[:find ?count
    :where [_ :item/count ?count]])

(def history-query
  '[:find ?count ?added
    :where [_ :item/count ?count _ ?added]])

(def schema
  [{:db/ident :item/id
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :item/count
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}])

(defn data-tx [time-point count-value]
  [{:db/id "datomic.tx" :db/txInstant time-point}
   (if (= count-value 100)
     {:db/id "item" :item/id "DLC-42" :item/count count-value}
     [:db/add [:item/id "DLC-42"] :item/count count-value])])

(defn assert-match! [scenario expected datomic-result vev-result]
  (when-not (= expected datomic-result vev-result)
    (throw (ex-info "Datomic/Vev history filter mismatch"
                    {:scenario scenario
                     :expected expected
                     :datomic datomic-result
                     :vev vev-result})))
  {:scenario scenario :datomic datomic-result :vev vev-result})

(defn q-values [query db]
  (set (datomic/q query db)))

(defn vq-values [query db]
  (set (vev/q query db)))

(defn -main [& _]
  (let [datomic-uri (str "datomic:mem://vev-history-parity-" (UUID/randomUUID))
        vev-path (str (Files/createTempFile "vev-history-parity-" ".sqlite"
                                            (make-array java.nio.file.attribute.FileAttribute 0)))]
    (Files/deleteIfExists (Path/of vev-path (make-array String 0)))
    (datomic/create-database datomic-uri)
    (let [datomic-conn (datomic/connect datomic-uri)
          vev-conn (vev/connect vev-path)]
      (try
        @(datomic/transact datomic-conn schema)
        (vev/transact vev-conn schema)

        ;; Both systems receive the same explicit transaction instants. A short
        ;; pause keeps each instant monotonic and no newer than either wall clock.
        (Thread/sleep 20)
        (let [t1 (Date. (System/currentTimeMillis))
              datomic-tx1 @(datomic/transact datomic-conn (data-tx t1 100))
              _ (vev/transact vev-conn (data-tx t1 100))
              datomic-coordinate (datomic/basis-t (:db-after datomic-tx1))
              vev-coordinate (:basis-t (vev/connection-info vev-conn))]
          (Thread/sleep 20)
          (let [t2 (Date. (System/currentTimeMillis))]
            @(datomic/transact datomic-conn (data-tx t2 250))
            (vev/transact vev-conn (data-tx t2 250))
            (let [datomic-db (datomic/db datomic-conn)
                  vev-db (vev/db vev-conn)
                  between (Date. (quot (+ (.getTime t1) (.getTime t2)) 2))
                  before (Date. (dec (.getTime t1)))
                  after (Date. (inc (.getTime t2)))
                  rows [(assert-match!
                          :as-of-transaction
                          #{[100]}
                          (q-values value-query
                                    (datomic/as-of datomic-db datomic-coordinate))
                          (vq-values value-query
                                     (vev/as-of vev-db vev-coordinate)))
                        (assert-match!
                          :as-of-exact-date
                          #{[100]}
                          (q-values value-query (datomic/as-of datomic-db t1))
                          (vq-values value-query (vev/as-of vev-db t1)))
                        (assert-match!
                          :as-of-between-dates
                          #{[100]}
                          (q-values value-query (datomic/as-of datomic-db between))
                          (vq-values value-query (vev/as-of vev-db between)))
                        (assert-match!
                          :since-exact-date
                          #{[250]}
                          (q-values value-query (datomic/since datomic-db t1))
                          (vq-values value-query (vev/since vev-db t1)))
                        (assert-match!
                          :as-of-before-first
                          #{}
                          (q-values value-query (datomic/as-of datomic-db before))
                          (vq-values value-query (vev/as-of vev-db before)))
                        (assert-match!
                          :since-after-latest
                          #{}
                          (q-values value-query (datomic/since datomic-db after))
                          (vq-values value-query (vev/since vev-db after)))
                        (assert-match!
                          :history
                          #{[100 true] [100 false] [250 true]}
                          (q-values history-query (datomic/history datomic-db))
                          (vq-values history-query (vev/history vev-db)))
                        (assert-match!
                          :history-as-of-composition
                          #{[100 true]}
                          (q-values history-query
                                    (datomic/history (datomic/as-of datomic-db t1)))
                          (vq-values history-query
                                     (vev/history (vev/as-of vev-db t1))))]]
              ;; java.time.Instant is a Vev convenience in addition to
              ;; Datomic's documented java.util.Date time point.
              (when-not (= #{[100]}
                           (vq-values value-query
                                      (vev/as-of vev-db (.toInstant t1))))
                (throw (ex-info "Vev java.time.Instant mismatch" {})))
              (doseq [{:keys [scenario datomic vev]} rows]
                (println (format "%-30s Datomic=%-24s Vev=%s"
                                 (name scenario) (pr-str datomic) (pr-str vev))))
              (println "history time-filter parity: ok"))))
        (finally
          (.close vev-conn)
          (datomic/release datomic-conn)
          (datomic/delete-database datomic-uri)
          (Files/deleteIfExists (Path/of vev-path (make-array String 0)))
          (datomic/shutdown true))))))
