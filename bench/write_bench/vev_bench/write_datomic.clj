(ns vev-bench.write-datomic
  (:require [datomic.api :as d])
  (:import [java.util Locale]))

(def schema
  [{:db/ident :item/key
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one
    :db.install/_attribute :db.part/db}
   {:db/ident :item/value
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db.install/_attribute :db.part/db}])

(defn arg-value [args option default]
  (if-let [index (first (keep-indexed #(when (= option %2) %1) args))]
    (or (get args (inc index))
        (throw (ex-info (str "missing value for " option) {:option option})))
    default))

(defn item-value [index]
  (format "value-%d-0-000000000000000000000000000000000000"
          (* index 2)))

(defn item-transaction [start entities-per-tx]
  (mapv (fn [index]
          {:db/id (d/tempid :db.part/user)
           :item/key (* index 2)
           :item/value (item-value index)})
        (range start (+ start entities-per-tx))))

(defn run-benchmark! [uri entities-per-tx total]
  (when-not (d/create-database uri)
    (throw (ex-info "benchmark database already exists" {:uri uri})))
  (let [conn (d/connect uri)]
    (try
      @(d/transact conn schema)
      (println
       (format
        "engine=datomic workload=write entities_per_tx=%d total=%d columns=entities,elapsed_s,throughput_entities_per_s,commit_latency_ms"
        entities-per-tx total))
      (let [started (System/nanoTime)]
        (loop [written 0
               commit-ns 0
               commits 0]
          (if (< written total)
            (let [transaction-entities (min entities-per-tx (- total written))
                  tx (item-transaction (inc written) transaction-entities)
                  before (System/nanoTime)]
              @(d/transact conn tx)
              (recur (+ written transaction-entities)
                     (+ commit-ns (- (System/nanoTime) before))
                     (inc commits)))
            (let [elapsed-ns (- (System/nanoTime) started)
                  elapsed-s (/ (double elapsed-ns) 1.0e9)
                  throughput (/ total elapsed-s)
                  commit-ms (/ (double commit-ns) commits 1.0e6)
                  actual (d/q '[:find (count ?e) .
                                :where [?e :item/key]]
                              (d/db conn))]
              (when (not= total actual)
                (throw (ex-info "transaction count mismatch"
                                {:expected total :actual actual})))
              (println
               (format "%d,%.3f,%.2f,%.3f"
                       total elapsed-s throughput commit-ms))))))
      (finally
        (d/release conn)
        (d/delete-database uri)))))

(defn -main [& raw-args]
  (Locale/setDefault Locale/US)
  (let [args (vec raw-args)
        uri (arg-value args "--uri" "datomic:mem://vev-write-bench")
        entities-per-tx (parse-long
                         (arg-value args "--entities-per-tx"
                                    (arg-value args "--batch" "1")))
        total (parse-long (arg-value args "--total" "100"))]
    (when (or (not (pos? entities-per-tx)) (not (pos? total)))
      (throw (ex-info "--entities-per-tx and --total must be positive"
                      {:entities-per-tx entities-per-tx :total total})))
    (run-benchmark! uri entities-per-tx total)
    (shutdown-agents)
    (System/exit 0)))
