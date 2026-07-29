;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns compare-datomic-semantics
  (:require [datomic.api :as datomic]
            [vev.core :as vev])
  (:import [java.time Instant]
           [java.util Date UUID]))

(def ada-token
  (UUID/fromString "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"))

(def ada-created
  (Date/from (Instant/parse "1815-12-10T00:00:00Z")))

(def schema
  [{:db/ident :person/email
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :person/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/index true}
   {:db/ident :person/nickname
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :person/friend
    :db/valueType :db.type/ref
    :db/cardinality :db.cardinality/one}
   {:db/ident :person/score
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :person/number
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :person/role
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :person/enabled
    :db/valueType :db.type/boolean
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :person/token
    :db/valueType :db.type/uuid
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :person/created
    :db/valueType :db.type/instant
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :team/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :team/members
    :db/valueType :db.type/ref
    :db/cardinality :db.cardinality/many}])

(def people
  [{:db/id "ada"
    :person/email "ada@example.com"
    :person/name "Ada"
    :person/score 10.5
    :person/number 1815
    :person/role :role/mathematician
    :person/enabled true
    :person/token ada-token
    :person/created ada-created
    :person/friend "grace"}
   {:db/id "grace"
    :person/email "grace@example.com"
    :person/name "Grace"
    :person/score 20.5}
   {:db/id "team"
    :team/name "Pioneers"
    :team/members ["ada" "grace"]}])

(def names-query
  '[:find ?name
    :where
    [?e :person/name ?name]])

(def average-query
  '[:find (avg ?score) .
    :where
    [?e :person/score ?score]])

(def scenario-count (atom 0))

(defn check! [scenario expected actual]
  (swap! scenario-count inc)
  (when-not (= expected actual)
    (throw (ex-info "Datomic semantic compatibility mismatch"
                    {:scenario scenario
                     :expected expected
                     :actual actual}))))

(defn throws? [f]
  (try
    (f)
    false
    (catch Throwable _ true)))

(defn attr-summary [attribute]
  (into {}
        (map (fn [key] [key (get attribute key)]))
        [:ident :value-type :cardinality :indexed :has-avet :unique
         :is-component :no-history :fulltext]))

(defn datom-summary [ident-fn datoms]
  (->> datoms
       (map (fn [datom]
              [(ident-fn (:a datom)) (:v datom) (:added datom)]))
       set))

(defn assert-datom-contract! [engine datom]
  (check! [engine :datom-count] 5 (count datom))
  (doseq [[key index] [[:e 0] [:a 1] [:v 2] [:tx 3] [:added 4]]]
    (check! [engine :datom-access key] (get datom key) (nth datom index))))

(defn check-lookup-ref! [scenario datomic-db vev-db lookup-ref]
  (check! [scenario :entity]
          (:person/name (datomic/entity datomic-db lookup-ref))
          (:person/name (vev/entity vev-db lookup-ref)))
  (check! [scenario :entid]
          (some? (datomic/entid datomic-db lookup-ref))
          (some? (vev/entid vev-db lookup-ref))))

(defn run-contract! []
  (reset! scenario-count 0)
  (let [uri (str "datomic:mem://vev-semantic-compatibility-"
                 (UUID/randomUUID))]
    (datomic/create-database uri)
    (with-open [vev-conn (vev/create-conn)]
      (let [datomic-conn (datomic/connect uri)]
        (try
          @(datomic/transact datomic-conn schema)
          (vev/transact vev-conn schema)
          (let [datomic-report @(datomic/transact datomic-conn people)
                vev-report (vev/transact vev-conn people)
                datomic-db (:db-after datomic-report)
                vev-db (:db-after vev-report)]
            (check! :report-keys
                    (set (keys datomic-report))
                    (set (keys vev-report)))
            (assert-datom-contract! :datomic (first (:tx-data datomic-report)))
            (assert-datom-contract! :vev (first (:tx-data vev-report)))
            (check! :tempid-ada
                    (some? (datomic/resolve-tempid
                            datomic-db (:tempids datomic-report) "ada"))
                    (some? (vev/resolve-tempid
                            vev-db (:tempids vev-report) "ada")))
            (check! :query-names
                    (datomic/q names-query datomic-db)
                    (vev/q names-query vev-db))
            (check! :query-average
                    (datomic/q average-query datomic-db)
                    (vev/q average-query vev-db))
            (check! :pull
                    (datomic/pull datomic-db
                                  [:person/name :person/score]
                                  [:person/email "ada@example.com"])
                    (vev/pull vev-db
                              [:person/name :person/score]
                              [:person/email "ada@example.com"]))
            (check! :pull-wildcard
                    (select-keys
                     (datomic/pull
                      datomic-db '[*] [:person/email "ada@example.com"])
                     [:person/email :person/name :person/score])
                    (select-keys
                     (vev/pull
                      vev-db '[*] [:person/email "ada@example.com"])
                     [:person/email :person/name :person/score]))
            (check! :pull-default
                    (datomic/pull
                     datomic-db
                     '[[:person/nickname :default "Unknown"]]
                     [:person/email "ada@example.com"])
                    (vev/pull
                     vev-db
                     '[[:person/nickname :default "Unknown"]]
                     [:person/email "ada@example.com"]))
            (check! :pull-alias
                    (datomic/pull
                     datomic-db
                     '[[:person/name :as :display/name]]
                     [:person/email "ada@example.com"])
                    (vev/pull
                     vev-db
                     '[[:person/name :as :display/name]]
                     [:person/email "ada@example.com"]))
            (check! :pull-nested-forward
                    (datomic/pull
                     datomic-db
                     '[{:team/members [:person/name]}]
                     [:team/name "Pioneers"])
                    (vev/pull
                     vev-db
                     '[{:team/members [:person/name]}]
                     [:team/name "Pioneers"]))
            (check! :pull-reverse
                    (datomic/pull
                     datomic-db
                     '[{:team/_members [:team/name]}]
                     [:person/email "ada@example.com"])
                    (vev/pull
                     vev-db
                     '[{:team/_members [:team/name]}]
                     [:person/email "ada@example.com"]))
            (check! :pull-limit
                    (count
                     (:team/members
                      (datomic/pull
                       datomic-db
                       '[[:team/members :limit 1]]
                       [:team/name "Pioneers"])))
                    (count
                     (:team/members
                      (vev/pull
                       vev-db
                       '[[:team/members :limit 1]]
                       [:team/name "Pioneers"]))))
            (check! :pull-recursion
                    (datomic/pull
                     datomic-db
                     '[:person/name {:person/friend 1}]
                     [:person/email "ada@example.com"])
                    (vev/pull
                     vev-db
                     '[:person/name {:person/friend 1}]
                     [:person/email "ada@example.com"]))
            (check! :pull-db-id
                    (contains?
                     (datomic/pull
                      datomic-db
                      '[:db/id]
                      [:person/email "ada@example.com"])
                     :db/id)
                    (contains?
                     (vev/pull
                      vev-db
                      '[:db/id]
                      [:person/email "ada@example.com"])
                     :db/id))
            (check! :entity-name
                    (:person/name
                     (datomic/entity datomic-db
                                     [:person/email "grace@example.com"]))
                    (:person/name
                     (vev/entity vev-db
                                 [:person/email "grace@example.com"])))
            (doseq [[scenario lookup-ref]
                    [[:lookup-ref-long [:person/number 1815]]
                     [:lookup-ref-keyword
                      [:person/role :role/mathematician]]
                     [:lookup-ref-boolean [:person/enabled true]]
                     [:lookup-ref-uuid [:person/token ada-token]]
                     [:lookup-ref-instant [:person/created ada-created]]]]
              (check-lookup-ref! scenario datomic-db vev-db lookup-ref))
            (check! :lookup-ref-missing
                    (datomic/entity datomic-db [:person/number -1])
                    (vev/entity vev-db [:person/number -1]))
            (check! :attribute
                    (attr-summary
                     (datomic/attribute datomic-db :person/name))
                    (attr-summary
                     (vev/attribute vev-db :person/name)))
            (check! :attribute-datoms
                    (datom-summary #(datomic/ident datomic-db %)
                                   (datomic/datoms datomic-db
                                                  :avet :person/name))
                    (datom-summary #(vev/ident vev-db %)
                                   (vev/datoms vev-db
                                               :avet :person/name)))
            (let [datomic-name-id
                  (datomic/entid datomic-db :person/name)
                  vev-name-id
                  (vev/entid vev-db :person/name)
                  datomic-ident #(datomic/ident datomic-db %)
                  vev-ident #(vev/ident vev-db %)
                  same-name
                  (fn [ident-fn values]
                    (take-while
                     #(= :person/name (ident-fn (:a %)))
                     values))]
              (check! :numeric-attribute-ident
                      (datomic/ident datomic-db datomic-name-id)
                      (vev/ident vev-db vev-name-id))
              (check! :numeric-attribute-datoms
                      (datom-summary
                       datomic-ident
                       (datomic/datoms
                        datomic-db :avet datomic-name-id))
                      (datom-summary
                       vev-ident
                       (vev/datoms vev-db :avet vev-name-id)))
              (check! :numeric-attribute-seek
                      (datom-summary
                       datomic-ident
                       (same-name
                        datomic-ident
                        (datomic/seek-datoms
                         datomic-db :avet datomic-name-id "Grace")))
                      (datom-summary
                       vev-ident
                       (same-name
                        vev-ident
                        (vev/seek-datoms
                         vev-db :avet vev-name-id "Grace"))))
              (check! :numeric-attribute-index-range
                      (datom-summary
                       datomic-ident
                       (datomic/index-range
                        datomic-db datomic-name-id "A" "H"))
                      (datom-summary
                       vev-ident
                       (vev/index-range
                        vev-db vev-name-id "A" "H"))))
            (check! :is-history-current
                    (datomic/is-history datomic-db)
                    (vev/is-history vev-db))
            (with-open [vev-history (vev/history vev-db)]
              (check! :is-history-history
                      (datomic/is-history (datomic/history datomic-db))
                      (vev/is-history vev-history)))
            (check! :index-pull-avet
                    (vec (datomic/index-pull
                          datomic-db
                          {:index :avet
                           :selector [:person/name]
                           :start [:person/name]}))
                    (vev/index-pull
                     vev-db
                     {:index :avet
                      :selector [:person/name]
                      :start [:person/name]}))
            (check! :index-pull-avet-reverse
                    (vec (datomic/index-pull
                          datomic-db
                          {:index :avet
                           :selector [:person/name]
                           :start [:person/name]
                           :reverse true}))
                    (vev/index-pull
                     vev-db
                     {:index :avet
                      :selector [:person/name]
                      :start [:person/name]
                      :reverse true}))
            (check! :index-pull-avet-value-start
                    (vec (datomic/index-pull
                          datomic-db
                          {:index :avet
                           :selector [:person/name]
                           :start [:person/name "Grace"]}))
                    (vev/index-pull
                     vev-db
                     {:index :avet
                      :selector [:person/name]
                      :start [:person/name "Grace"]}))
            (check! :index-pull-avet-value-start-reverse
                    (vec (datomic/index-pull
                          datomic-db
                          {:index :avet
                           :selector [:person/name]
                           :start [:person/name "Grace"]
                           :reverse true}))
                    (vev/index-pull
                     vev-db
                     {:index :avet
                      :selector [:person/name]
                      :start [:person/name "Grace"]
                      :reverse true}))
            (check! :index-pull-aevt
                    (vec (datomic/index-pull
                          datomic-db
                          {:index :aevt
                           :selector [:person/name]
                           :start [:team/members]}))
                    (vev/index-pull
                     vev-db
                     {:index :aevt
                      :selector [:person/name]
                      :start [:team/members]}))
            (check! :index-pull-many-requires-value
                    (throws? #(doall
                               (datomic/index-pull
                                datomic-db
                                {:index :avet
                                 :selector [:person/name]
                                 :start [:team/members]})))
                    (throws? #(vev/index-pull
                               vev-db
                               {:index :avet
                                :selector [:person/name]
                                :start [:team/members]})))
            (check! :db-stats-person-name
                    (get-in (datomic/db-stats datomic-db)
                            [:attrs :person/name])
                    (get-in (vev/db-stats vev-db)
                            [:attrs :person/name]))
            (let [datomic-with
                  (datomic/with datomic-db
                                [[:db/add
                                  [:person/email "ada@example.com"]
                                  :person/name "Augusta Ada"]])
                  vev-with
                  (vev/with vev-db
                            [[:db/add
                              [:person/email "ada@example.com"]
                              :person/name "Augusta Ada"]])]
              (check! :with-source
                      (datomic/q names-query (:db-before datomic-with))
                      (vev/q names-query (:db-before vev-with)))
              (check! :with-result
                      (datomic/q names-query (:db-after datomic-with))
                      (vev/q names-query (:db-after vev-with))))
            (check! :transaction-rejection
                    (throws? #(deref
                               (datomic/transact
                                datomic-conn
                                [[:db/add
                                  [:person/email "ada@example.com"]
                                  :person/name nil]])))
                    (throws? #(vev/transact
                               vev-conn
                               [[:db/add
                                 [:person/email "ada@example.com"]
                                 :person/name nil]])))
            (let [datomic-squuid (datomic/squuid)
                  vev-squuid (vev/squuid)]
              (check! :datomic-squuid-seconds
                      0
                      (mod (datomic/squuid-time-millis datomic-squuid) 1000))
              (check! :vev-squuid-seconds
                      0
                      (mod (vev/squuid-time-millis vev-squuid) 1000)))
            (println
             (pr-str {:status :match
                      :suite :datomic-semantic-compatibility
                      :scenarios @scenario-count
                      :datomic-version "1.0.7277"})))
          (finally
            (datomic/release datomic-conn)
            (datomic/delete-database uri)
            (datomic/shutdown true)))))))

(run-contract!)
