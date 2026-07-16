;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns smoke
  (:require [vev.core :as vev]))

(defn delete-sqlite-files! [path]
  (doseq [suffix ["" "-wal" "-shm"]]
    (java.nio.file.Files/deleteIfExists
     (java.nio.file.Path/of (str path suffix) (make-array String 0)))))

(defn -main [& args]
  (when-not (= 1 (count args))
    (throw (ex-info "usage: smoke <path-to-native-library>" {})))
  (let [lib-path (first args)]
    (with-open [closed-conn (vev/create-conn lib-path)]
      (vev/transact closed-conn [{:db/id 10 :user/name "Closed"}])
      (let [closed-db (vev/db closed-conn)]
        (.close closed-conn)
        (when-not (= #{["Closed"]}
                     (vev/q closed-db
                            '[:find ?name :where [?e :user/name ?name]]))
          (throw (ex-info "DB value did not survive connection close" {})))))

    (with-open [conn (vev/create-conn lib-path)]
      (let [tx (vev/transact conn
                             [{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
                              {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}])]
        (println "tx:" tx)
        (when-not (and (:ok tx) (integer? (:tx tx)) (map? (:tempids tx)))
          (throw (ex-info "unexpected transaction report" {:report tx}))))

      (let [seen (atom [])]
        (with-open [_listener (vev/listen conn :smoke-listener
                                          #(swap! seen conj (:tx-data %)))]
          (vev/transact conn [[:db/add 1 :user/listener "heard"]])
          (when-not (= 1 (count @seen))
            (throw (ex-info "listener did not observe successful transaction"
                            {:seen @seen}))))
        (vev/transact conn [[:db/add 1 :user/listener "after-unlisten"]])
        (when-not (= 1 (count @seen))
          (throw (ex-info "listener observed transaction after close"
                          {:seen @seen}))))

      (let [db (vev/db conn)
            names (vev/q
                   db
                   '[:find ?name
                     :in $ [?email ...]
                     :where [?e :user/email ?email]
                     [?e :user/name ?name]]
                   ["ada@example.com" "grace@example.com"])]
        (println "input-collection:" names)
        (when-not (= #{["Ada"] ["Grace"]} names)
          (throw (ex-info "unexpected collection query output" {:rows names}))))

      (let [db (vev/db conn)
            requested (vev/query
                       {:query '[:find ?name
                                 :in $ ?email
                                 :where [?e :user/email ?email]
                                 [?e :user/name ?name]]
                        :args [db "ada@example.com"]})]
        (println "query-map:" requested)
        (when-not (= #{["Ada"]} requested)
          (throw (ex-info "unexpected query map output" {:rows requested}))))

      (let [db (vev/db conn)
            keyed (vev/query
                   {:query '[:find ?name ?email
                             :keys name email
                             :in $ ?email
                             :where [?e :user/email ?email]
                             [?e :user/name ?name]]
                    :args [db "ada@example.com"]})]
        (println "query-map keys:" keyed)
        (when-not (= #{{:name "Ada" :email "ada@example.com"}} keyed)
          (throw (ex-info "unexpected query map keyed output" {:rows keyed}))))

      (vev/transact conn
                    [[:db/add 90 :db/ident :user/email]
                     [:db/add 90 :db/unique :db.unique/identity]])

      (vev/transact conn
                    [[:db/add 91 :db/ident :user/status]
                     [:db/add 91 :db/unique :db.unique/identity]
                     [:db/add 92 :db/ident :user/code]
                     [:db/add 92 :db/unique :db.unique/identity]
                     [:db/add 1 :user/status :active]
                     [:db/add 2 :user/status :inactive]
                     [:db/add 1 :user/code 1001]
                     [:db/add 2 :user/code 1002]])

      (vev/transact conn
                    [[:db/add 100 :db/ident :user/friend]
                     [:db/add 100 :db/valueType :db.type/ref]
                     [:db/add 1 :user/friend 2]])

      (let [db (vev/db conn)]
        (with-open [ada (vev/entity db 1)
                    friend (vev/entity-ref ada :user/friend)
                    lookup (vev/entity db [:user/email "ada@example.com"])]
          (when-not (and (vev/entity-found? ada)
                         (= 1 (vev/entity-id ada))
                         (= "Ada" (:user/name ada))
                         (= ["Ada"] (vev/entity-values ada :user/name))
                         (= 2 (vev/entity-id friend))
                         (= "Grace" (:user/name friend))
                         (= [2] (vev/entity-refs ada :user/friend))
                         (= 1 (vev/entity-id lookup))
                         (= "Ada" (:user/name (vev/touch ada))))
            (throw (ex-info "unexpected entity view output"
                            {:entity (vev/touch ada)})))))

      (with-open [fns (vev/tx-fns conn {:user/set-name
                                        (fn [db e name]
                                          [[:db/add e :user/nickname name]])})]
        (vev/transact conn [[:db/add 101 :db/ident :user/set-name]])
        (let [tx-fn-report (vev/transact conn [[:user/set-name 6 "Edsger"]] fns)]
          (when-not (:ok tx-fn-report)
            (throw (ex-info "transaction function failed" {:report tx-fn-report})))
          (when-not (= #{["Edsger"]}
                       (vev/q '[:find ?name :where [6 :user/nickname ?name]]
                              (vev/db conn)))
            (throw (ex-info "transaction function did not apply tx-data" {})))))

      (with-open [email-query (vev/prepare conn
                                           '[:find ?e ?email
                                             :in $ ?needle
                                             :where [?e :user/email ?email]
                                             [(= ?email ?needle)]])]
        (let [prepared-ast (vev/prepared-edn email-query)]
          (when-not (and (:ok prepared-ast)
                         (seq (:clauses prepared-ast))
                         (seq (:input-specs prepared-ast)))
            (throw (ex-info "prepared query AST did not expose parser keys"
                            {:prepared prepared-ast}))))
        (let [clause-ast (vev/parse-clause conn '[?e :user/email ?email])]
          (when-not (and (:ok clause-ast)
                         (seq (:clauses clause-ast)))
            (throw (ex-info "parse-clause AST did not expose parser keys"
                            {:clause clause-ast}))))

        (let [db (vev/db conn)
              rows (vev/q db email-query "grace@example.com")]
          (println "prepared rows:" rows)
          (when-not (= #{[2 "grace@example.com"]} rows)
            (throw (ex-info "unexpected prepared rows" {:rows rows}))))

        (with-open [rule-query (vev/prepare conn
                                            '[:find ?name
                                              :in $ % ?email
                                              :where (email-name ?email ?name)])]
          (let [db (vev/db conn)
                rules '[[(email-name ?email ?name)
                         [?e :user/email ?email]
                         [?e :user/name ?name]]]
                rows (vev/q rule-query db rules "ada@example.com")]
            (println "prepared rule rows:" rows)
            (when-not (= #{["Ada"]} rows)
              (throw (ex-info "unexpected prepared rule rows" {:rows rows})))))

        (let [db (vev/db conn)
              pulled (vev/pull db
                               [:user/name {:user/friend [:user/name]}]
                               1)]
          (println "pull:" pulled)
          (when-not (= {:user/name "Ada"
                        :user/friend {:user/name "Grace"}}
                       pulled)
            (throw (ex-info "unexpected pull result" {:pull pulled}))))

        (with-open [pull-column-query (vev/prepare conn
                                                   '[:find (pull ?e [:user/name {:user/friend [:user/name]}])
                                                     :where [?e :user/name "Ada"]])
                    db (vev/db conn)]
          (let [columns (vev/columns pull-column-query db)
                pulled (first (first (:columns columns)))]
            (println "pull column batch:" columns)
            (when-not (and (= [:value] (:kinds columns))
                           (= {:user/name "Ada"
                               :user/friend {:user/name "Grace"}}
                              pulled))
              (throw (ex-info "unexpected pull column batch"
                              {:columns columns})))))

        (let [db (vev/db conn)]
          (with-open [prepared-pattern (vev/prepare-pull-pattern db [:user/name])]
            (let [prepared-pattern-ast (vev/prepared-edn prepared-pattern)
                  lookup-pull (vev/pull db
                                        [:user/name]
                                        [:user/email "ada@example.com"])
                  prepared-lookup-pull (vev/pull db
                                                 prepared-pattern
                                                 [:user/email "ada@example.com"])
                  keyword-lookup-pull (vev/pull db
                                                [:user/name]
                                                [:user/status :active])
                  int-lookup-pull (vev/pull db
                                            [:user/name]
                                            [:user/code 1001])
                  many-pull (vev/pull-many db [:user/name] [1 2])]
              (println "lookup pull:" lookup-pull)
              (println "prepared lookup pull:" prepared-lookup-pull)
              (println "keyword lookup pull:" keyword-lookup-pull)
              (println "int lookup pull:" int-lookup-pull)
              (println "pull many:" many-pull)
              (when-not (and (:ok prepared-pattern-ast)
                             (seq (:pattern prepared-pattern-ast))
                             (= :user/name (:attr (first (:pattern prepared-pattern-ast)))))
                (throw (ex-info "prepared pull pattern AST did not expose parser keys"
                                {:prepared prepared-pattern-ast})))
              (when-not (= {:user/name "Ada"} lookup-pull)
                (throw (ex-info "unexpected lookup-ref pull" {:pull lookup-pull})))
              (when-not (= {:user/name "Ada"} prepared-lookup-pull)
                (throw (ex-info "unexpected prepared lookup-ref pull" {:pull prepared-lookup-pull})))
              (when-not (= {:user/name "Ada"} keyword-lookup-pull)
                (throw (ex-info "unexpected keyword lookup-ref pull" {:pull keyword-lookup-pull})))
              (when-not (= {:user/name "Ada"} int-lookup-pull)
                (throw (ex-info "unexpected int lookup-ref pull" {:pull int-lookup-pull})))
              (when-not (= #{"Ada" "Grace"} (set (map :user/name many-pull)))
                (throw (ex-info "unexpected pull-many" {:pull many-pull}))))))

        (with-open [all-names (vev/prepare conn
                                           '[:find ?name
                                             :where [?e :user/name ?name]])
                    db (vev/db conn)]
          (let [columns (vev/columns all-names db)]
            (println "column batch:" columns)
            (when-not (and (= [:string] (:kinds columns))
                           (= #{"Ada" "Grace"} (set (first (:columns columns)))))
              (throw (ex-info "unexpected column batch" {:columns columns})))))

        (let [db (vev/db conn)
              immutable-report (vev/with db [{:db/id 4 :user/name "Barbara"}])
              immutable-report-with-dbs (vev/with-report db [{:db/id 4 :user/name "Barbara"}])
              immutable-next (vev/db-with db [{:db/id 4 :user/name "Barbara"}])]
          (println "with tx:" immutable-report)
          (when-not (and (:ok immutable-report)
                         (= #{} (vev/q db
                                       '[:find ?e
                                         :where [?e :user/name "Barbara"]])))
            (throw (ex-info "immutable with mutated source DB" {:report immutable-report})))
          (try
            (when-not (and (= #{} (vev/q (:db-before immutable-report-with-dbs)
                                         '[:find ?e
                                           :where [?e :user/name "Barbara"]]))
                           (= #{[4]} (vev/q (:db-after immutable-report-with-dbs)
                                            '[:find ?e
                                              :where [?e :user/name "Barbara"]])))
              (throw (ex-info "with-report db-before/db-after mismatch"
                              {:report immutable-report-with-dbs})))
            (finally
              (.close (:db-before immutable-report-with-dbs))
              (.close (:db-after immutable-report-with-dbs))))
          (when-not (= #{[4]}
                       (vev/q immutable-next
                              '[:find ?e
                                :where [?e :user/name "Barbara"]]))
            (throw (ex-info "db-with did not produce expected DB" {})))
          (with-open [derived-conn (vev/conn-from-db immutable-next)]
            (vev/transact derived-conn [{:db/id 5 :user/name "Dorothy"}])
            (when-not (and (= #{[4]}
                              (vev/q (vev/db derived-conn)
                                     '[:find ?e
                                       :where [?e :user/name "Barbara"]]))
                           (= #{[5]}
                              (vev/q (vev/db derived-conn)
                                     '[:find ?e
                                       :where [?e :user/name "Dorothy"]])))
              (throw (ex-info "conn-from-db did not initialize from DB value" {})))))

        (with-open [all-emails (vev/prepare conn
                                            '[:find ?e ?email
                                              :where [?e :user/email ?email]])
                    snapshot (vev/db conn)]
          (vev/transact conn
                        [{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}])
          (let [current (vev/db conn)
                current-rows (count (vev/q current all-emails))
                snapshot-rows (count (vev/q snapshot all-emails))]
            (println "current-db rows:" current-rows)
            (println "snapshot-db rows:" snapshot-rows)
            (when-not (and (= 3 current-rows) (= 2 snapshot-rows))
              (throw (ex-info "unexpected snapshot row counts"
                              {:current current-rows :snapshot snapshot-rows})))))))

    (let [sqlite-path "tmp.vev.clojure.sqlite"
          first-basis (atom 0)]
      (delete-sqlite-files! sqlite-path)
      (try
        (with-open [durable (vev/connect lib-path sqlite-path)]
          (when (not= {:backend :sqlite :path sqlite-path :basis-t 0 :tx-count 0 :tx-ids []} (vev/connection-info durable))
            (throw (ex-info "unexpected durable connection metadata" {})))
          (let [tx (vev/transact durable
                                 [{:db/id 1
                                   :user/name "Durable Ada"
                                   :user/email "durable-ada@example.com"}])]
            (when-not (:ok tx)
              (throw (ex-info "unexpected SQLite transaction report" {:report tx}))))
          (reset! first-basis (:basis-t (vev/connection-info durable)))
          (when (zero? @first-basis)
            (throw (ex-info "unexpected durable basis after first tx" {})))
          (when (not= 1 (:tx-count (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx count after first tx" {})))
          (when (not= [@first-basis] (:tx-ids (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx ids after first tx" {})))
          (with-open [bulk-a (vev/tx-builder durable 1)
                      bulk-b (vev/tx-builder durable 1)]
            (vev/tx-add! bulk-a 2 :user/name "Durable Grace")
            (vev/tx-add! bulk-b 3 :user/name "Durable Hedy")
            (let [tx (vev/transact-bulk durable [bulk-a bulk-b])]
              (when-not (:ok tx)
                (throw (ex-info "unexpected durable bulk builder report"
                                {:report tx})))))
          (when (not= (inc @first-basis) (:basis-t (vev/connection-info durable)))
            (throw (ex-info "unexpected durable basis after bulk builder tx" {})))
          (when (not= 2 (:tx-count (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx count after bulk builder tx" {})))
          (when (not= [@first-basis (inc @first-basis)] (:tx-ids (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx ids after bulk builder tx" {})))
          (with-open [logical-a (vev/tx-builder durable 1)
                      logical-b (vev/tx-builder durable 1)]
            (vev/tx-add! logical-a 4 :user/name "Durable Ada")
            (vev/tx-add! logical-b 5 :user/name "Durable Dorothy")
            (let [reports (vev/transact-logical-bulk durable [logical-a logical-b])]
              (when-not (and (= 2 (count reports))
                             (every? :ok reports))
                (throw (ex-info "unexpected durable logical group reports"
                                {:reports reports})))))
          (let [reports (vev/transact-logical-bulk durable [])]
            (when-not (empty? reports)
              (throw (ex-info "unexpected empty logical group reports"
                              {:reports reports}))))
          (let [reports (vev/transact-logical durable
                                              [[{:db/id 6
                                                 :user/name "Durable Katherine"}]
                                               "[{:db/id 7 :user/name \"Durable Mary\"}]"])]
            (when-not (and (= 2 (count reports))
                           (every? :ok reports))
              (throw (ex-info "unexpected durable logical EDN group reports"
                              {:reports reports}))))
          (when (not= (+ @first-basis 5) (:basis-t (vev/connection-info durable)))
            (throw (ex-info "unexpected durable basis after logical group tx" {})))
          (when (not= 6 (:tx-count (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx count after logical group tx" {})))
          (when (not= (mapv #(+ @first-basis %) (range 6)) (:tx-ids (vev/connection-info durable)))
            (throw (ex-info "unexpected durable tx ids after logical group tx" {})))
          (when-not (vev/compact-indexes! durable)
            (throw (ex-info "durable index compaction failed" {})))
          (with-open [db (vev/db durable)
                      all-emails (vev/prepare durable
                                              '[:find ?e ?email
                                                :where [?e :user/email ?email]])]
            (let [rows (vev/q db all-emails)]
              (println "sqlite-live rows:" rows)
              (when-not (= 1 (count rows))
                (throw (ex-info "unexpected SQLite live row count" {:rows rows}))))))
        (with-open [durable (vev/connect lib-path sqlite-path)
                    db (vev/db durable)
                    all-emails (vev/prepare durable
                                            '[:find ?e ?email
                                              :where [?e :user/email ?email]])]
          (when (not= (+ @first-basis 5) (:basis-t (vev/connection-info durable)))
            (throw (ex-info "unexpected reopened durable basis" {})))
          (when (not= 6 (:tx-count (vev/connection-info durable)))
            (throw (ex-info "unexpected reopened durable tx count" {})))
          (when (not= (mapv #(+ @first-basis %) (range 6)) (:tx-ids (vev/connection-info durable)))
            (throw (ex-info "unexpected reopened durable tx ids" {})))
          (let [rows (vev/q db all-emails)]
            (println "sqlite-reopened rows:" rows)
            (when-not (= 1 (count rows))
              (throw (ex-info "unexpected SQLite reopened row count" {:rows rows})))))
        (finally
          (delete-sqlite-files! sqlite-path))))))

(apply -main *command-line-args*)
