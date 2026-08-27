(ns vev-bench.resident-transactions
  "Small transaction shapes shared by DataScript, Datalevin, and Datomic."
  (:import [java.nio.file Files Path]
           [java.util Comparator Locale UUID]))

(def schema
  {:item/index {:db/valueType :db.type/long
                :db/cardinality :db.cardinality/one}
   :item/name {:db/valueType :db.type/string
               :db/cardinality :db.cardinality/one}
   :item/tag {:db/valueType :db.type/string
              :db/cardinality :db.cardinality/many}
   :tx/source {:db/valueType :db.type/string
               :db/cardinality :db.cardinality/one}
   :tx/actor {:db/valueType :db.type/string
              :db/cardinality :db.cardinality/one}
   :tx/request {:db/valueType :db.type/string
                :db/cardinality :db.cardinality/one}})

(def workloads ["append" "replacement" "explicit-retract" "retract-entity" "ro-like"])

(def datascript-schema
  (into {} (map (fn [[attribute options]]
                  [attribute (dissoc options :db/valueType)]))
        schema))

(defn arg-value [args option default]
  (if-let [index (first (keep-indexed #(when (= option %2) %1) args))]
    (or (get args (inc index))
        (throw (ex-info (str "missing value for " option) {:option option})))
    default))

(defn resolve-required [symbol]
  (or (requiring-resolve symbol)
      (throw (ex-info (str "cannot resolve " symbol) {:symbol symbol}))))

(defn datomic-schema [tempid]
  (mapv
    (fn [[ident options]]
      {:db/id (tempid :db.part/db)
       :db/ident ident
       :db/valueType (:db/valueType options)
       :db/cardinality (:db/cardinality options)
       :db.install/_attribute :db.part/db})
    schema))

(defn delete-tree! [^Path root]
  (when (Files/exists root (make-array java.nio.file.LinkOption 0))
    (with-open [paths (Files/walk root (make-array java.nio.file.FileVisitOption 0))]
      (doseq [path (iterator-seq (.iterator (.sorted paths (Comparator/reverseOrder))))]
        (Files/deleteIfExists ^Path path)))))

(defn open-engine [engine]
  (case engine
    "datascript"
    (let [create-conn (resolve-required 'datascript.core/create-conn)
          transact! (resolve-required 'datascript.core/transact!)
          db (resolve-required 'datascript.core/db)
          q (resolve-required 'datascript.core/q)
          conn (create-conn datascript-schema)]
      {:engine "datascript"
       :storage "in-memory"
       :conn conn
       :tempid (fn [label] (str "temp-" label))
       :tx-entity :db/current-tx
       :transact (fn [tx-data] (transact! conn tx-data))
       :query (fn [query & inputs] (apply q query (db conn) inputs))
       :close (fn [])})

    "datalevin"
    (let [get-conn (resolve-required 'datalevin.core/get-conn)
          transact! (resolve-required 'datalevin.core/transact!)
          db (resolve-required 'datalevin.core/db)
          q (resolve-required 'datalevin.core/q)
          close (resolve-required 'datalevin.core/close)
          path (Files/createTempDirectory "vev-datalevin-resident-"
                                           (make-array java.nio.file.attribute.FileAttribute 0))
          conn (get-conn (.toString path) schema
                         {:wal? true :wal-durability-profile :strict})]
      {:engine "datalevin"
       :storage "durable-wal-strict"
       :conn conn
       :tempid (fn [label] (str "temp-" label))
       :tx-entity :db/current-tx
       :transact (fn [tx-data] (transact! conn tx-data))
       :query (fn [query & inputs] (apply q query (db conn) inputs))
       :close (fn []
                (close conn)
                (delete-tree! path))})

    "datomic"
    (let [create-database (resolve-required 'datomic.api/create-database)
          delete-database (resolve-required 'datomic.api/delete-database)
          connect (resolve-required 'datomic.api/connect)
          transact (resolve-required 'datomic.api/transact)
          db (resolve-required 'datomic.api/db)
          q (resolve-required 'datomic.api/q)
          tempid (resolve-required 'datomic.api/tempid)
          release (resolve-required 'datomic.api/release)
          configured-prefix (System/getenv "VEV_BENCH_DATOMIC_URI_PREFIX")
          prefix (or configured-prefix "datomic:mem://vev-resident-")
          uri (str prefix (UUID/randomUUID))]
      (when-not (create-database uri)
        (throw (ex-info "could not create Datomic benchmark database" {:uri uri})))
      (let [conn (connect uri)]
        @(transact conn (datomic-schema tempid))
        {:engine "datomic"
         :storage (if configured-prefix "durable-dev" "in-memory")
         :conn conn
         :tempid (fn [label]
                   (tempid :db.part/user (- (inc (Math/abs (long (hash label)))))))
         :tx-entity "datomic.tx"
         :transact (fn [tx-data] @(transact conn tx-data))
         :query (fn [query & inputs] (apply q query (db conn) inputs))
         :close (fn []
                  (release conn)
                  (delete-database uri))}))

    (throw (ex-info "unsupported engine" {:engine engine}))))

(defn seed! [api entity-count]
  ((:transact api)
   (mapv
    (fn [index]
      {:db/id ((:tempid api) (str "seed-" index))
       :item/index index
       :item/name (str "seed-" index)
       :item/tag "seed"})
    (range 1 (inc entity-count)))))

(def entity-by-index-query
  '[:find ?e .
    :in $ ?index
    :where [?e :item/index ?index]])

(defn transaction-for [api workload sample]
  (let [entity-by-index (fn [index]
                          ((:query api) entity-by-index-query index))]
    (case workload
      "append"
      [{:db/id ((:tempid api) (str "append-" sample))
        :item/name (str "append-" sample)}]

      "replacement"
      [[:db/add (entity-by-index 1) :item/name
        (if (even? sample) "replacement-a" "replacement-b")]]

      "explicit-retract"
      [[:db/retract (entity-by-index (inc sample)) :item/tag "seed"]]

      "retract-entity"
      [[:db.fn/retractEntity (entity-by-index (inc sample))]]

      "ro-like"
      [[:db/add (entity-by-index 1) :item/name
        (if (even? sample) "ro-a" "ro-b")]
       [:db/add (:tx-entity api) :tx/source "ro-ui"]
       [:db/add (:tx-entity api) :tx/actor "user-1"]
       [:db/add (:tx-entity api) :tx/request (str "request-" sample)]])))

(defn percentile [values quantile]
  (let [ordered (vec (sort values))
        rank (max 1 (long (Math/ceil (* quantile (count ordered)))))]
    (nth ordered (dec rank))))

(defn median [values]
  (let [ordered (vec (sort values))
        size (count ordered)
        middle (quot size 2)]
    (if (odd? size)
      (nth ordered middle)
      (/ (+ (nth ordered (dec middle)) (nth ordered middle)) 2.0))))

(defn tx-datom-count [report]
  (count (:tx-data report)))

(defn run-workload! [engine database entities workload samples warmups]
  (let [api (open-engine engine)]
    (try
      (seed! api entities)
      (dotimes [sample warmups]
        ((:transact api) (transaction-for api workload sample)))
      (let [results
            (mapv
             (fn [sample]
               (let [logical-sample (+ warmups sample)
                     tx-data (transaction-for api workload logical-sample)
                     started (System/nanoTime)
                     report ((:transact api) tx-data)
                     elapsed-us (/ (- (System/nanoTime) started) 1000.0)]
                 {:elapsed-us elapsed-us
                  :effective-datoms (tx-datom-count report)}))
             (range samples))
            timings (mapv :elapsed-us results)
            datom-counts (mapv :effective-datoms results)]
        (println
         (format
          (str "engine=%s storage=%s database=%s entities=%d workload=%s "
               "samples=%d median_us=%.1f p95_us=%.1f effective_tx_datoms=%.1f")
          (:engine api) (:storage api) database entities workload
          samples (double (median timings))
          (double (percentile timings 0.95))
          (double (median datom-counts)))))
      (finally
        ((:close api))))))

(defn selected? [selected value]
  (or (= selected "all") (= selected value)))

(defn -main [& raw-args]
  (Locale/setDefault Locale/US)
  (let [args (vec raw-args)
        engine (arg-value args "--engine" "datascript")
        selected-database (arg-value args "--database" "all")
        selected-workload (arg-value args "--workload" "all")
        samples (parse-long (arg-value args "--samples" "40"))
        warmups (parse-long (arg-value args "--warmups" "5"))]
    (doseq [[database entities] [["small" 50] ["large" 2000]]
            workload workloads
            :when (and (selected? selected-database database)
                       (selected? selected-workload workload))]
      (run-workload! engine database entities workload samples warmups))
    (shutdown-agents)))
