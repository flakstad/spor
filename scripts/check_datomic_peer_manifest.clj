(require '[clojure.edn :as edn]
         '[clojure.java.io :as io]
         '[clojure.set :as set])

(def required-inventory
  '#{add-listener administer-system as-of as-of-t attribute basis-t cancel
     connect create-database datoms db db-stats delete-database entid entid-at
     entity entity-db filter function gc-storage get-database-names history
     ident implicit-part implicit-part-id index-pull index-range invoke
     is-filtered is-history log next-t part pull pull-many q qseq query release
     remove-tx-report-queue rename-database request-index resolve-tempid
     seek-datoms shutdown since since-t squuid squuid-time-millis sync
     sync-excise sync-index sync-schema t->tx tempid touch transact
     transact-async tx->t tx-range tx-report-queue with})

(def allowed-dispositions #{:native :adapter :semantic-gap :non-goal})

(defn fail! [message data]
  (throw (ex-info message data)))

(let [path (or (first *command-line-args*) "compat/datomic-peer-api.edn")
      manifest (edn/read-string (slurp (io/file path)))
      operations (:operations manifest)
      names (map :name operations)
      actual-inventory (set names)
      name-counts (frequencies names)
      duplicates (->> name-counts
                      (keep (fn [[name n]] (when (> n 1) name)))
                      set)
      missing (set/difference required-inventory actual-inventory)
      unexpected (set/difference actual-inventory required-inventory)
      disposition-counts (frequencies (map :disposition operations))]
  (when-not (= 2 (:format-version manifest))
    (fail! "unsupported compatibility inventory format"
           {:format-version (:format-version manifest)}))
  (when-not (= :core-model-tutorial-compatibility
               (get-in manifest [:policy :goal]))
    (fail! "compatibility inventory requires an explicit semantic goal"
           {:goal (get-in manifest [:policy :goal])}))
  (when-not (= #{:clojure :kvist} (get-in manifest [:policy :primary-apis]))
    (fail! "Clojure and Kvist must remain the paired primary APIs"
           {:primary-apis (get-in manifest [:policy :primary-apis])}))
  (when-not (= :complete-primary-api-substrate
               (get-in manifest [:policy :c-abi-role]))
    (fail! "the C ABI must remain the primary API substrate"
           {:c-abi-role (get-in manifest [:policy :c-abi-role])}))
  (when (seq duplicates)
    (fail! "duplicate compatibility operations" {:duplicates duplicates}))
  (when (seq missing)
    (fail! "Peer operations missing from compatibility inventory"
           {:missing missing}))
  (when (seq unexpected)
    (fail! "unexpected operations in Peer compatibility inventory"
           {:unexpected unexpected}))
  (when (some #(contains? % :status) operations)
    (fail! "legacy completion statuses are not allowed" {}))
  (when-not (some #(= :non-goal (:disposition %)) operations)
    (fail! "compatibility inventory must state explicit non-goals" {}))
  (when-not (some #(= :bounded (:coverage %)) operations)
    (fail! "bounded native capabilities must remain representable" {}))
  (doseq [operation operations]
    (when-not (contains? allowed-dispositions (:disposition operation))
      (fail! "invalid compatibility disposition" {:operation operation}))
    (when (and (contains? #{:native :adapter} (:disposition operation))
               (nil? (:vev-api operation)))
      (fail! "native and adapter dispositions require a Vev API mapping"
             {:operation operation}))
    (when (and (= :semantic-gap (:disposition operation))
               (nil? (:intent operation)))
      (fail! "semantic gaps require an explicit Vev intent"
             {:operation operation}))
    (when (and (= :non-goal (:disposition operation))
               (nil? (:reason operation)))
      (fail! "non-goals require a reason" {:operation operation})))
  (doseq [alias (:aliases manifest)]
    (when-not (and (:syntax alias) (:canonical alias) (:scope alias))
      (fail! "compatibility aliases require syntax, canonical form, and scope"
             {:alias alias})))
  (when (some #(= "datascript.tx" (:syntax %)) (:aliases manifest))
    (fail! "datascript.tx is not a Datomic compatibility alias" {}))
  (println
   (pr-str
    {:status :ok
     :reference (get-in manifest [:reference :version])
     :inventory-count (count operations)
     :dispositions disposition-counts})))
