;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns vev.core
  (:require [clojure.edn :as edn]
            [clojure.set :as set])
  (:import [java.nio.file Path]
           [com.vevdb Vev Vev$ColumnResult Vev$DB Vev$Entity Vev$EntityView Vev$Keyword Vev$MapValue Vev$PreparedPullPattern Vev$QueryAggregate Vev$QueryPredicate Vev$Symbol Vev$TxFunction Vev$TxReportListener]))

(defn- path [value]
  (cond
    (instance? Path value) value
    (string? value) (Path/of value (make-array String 0))
    :else (throw (ex-info "expected native library path" {:value value}))))

(defn- edn-text [value]
  (cond
    (string? value) value
    (keyword? value) (str value)
    (symbol? value) (str value)
    :else
    (binding [*print-namespace-maps* false]
      (pr-str value))))

(defn- inputs-text [inputs]
  (binding [*print-namespace-maps* false]
    (pr-str (vec inputs))))

(defn- load-engine
  ([]
   (Vev/load))
  ([lib-path]
   (Vev/load (path lib-path))))

(defn- keyword-text? [value]
  (and (string? value)
       (.startsWith ^String value ":")))

(defn- key-value [value]
  (if (keyword-text? value)
    (keyword (subs value 1))
    value))

(defn- clj-value [value]
  (cond
    (instance? Vev$Entity value)
    (.id ^Vev$Entity value)

    (instance? Vev$Keyword value)
    (keyword (subs (.text ^Vev$Keyword value) 1))

    (instance? Vev$Symbol value)
    (symbol (.text ^Vev$Symbol value))

    (instance? Vev$MapValue value)
    (persistent!
     (reduce (fn [out entry]
               (assoc! out
                       (key-value (clj-value (.key entry)))
                       (clj-value (.value entry))))
             (transient {})
             (.entries ^Vev$MapValue value)))

    (instance? java.util.Set value)
    (set (map clj-value value))

    (instance? java.util.List value)
    (mapv clj-value value)

    :else
    value))

(deftype KeyedRow [m values]
  clojure.lang.IPersistentMap
  (assoc [_ key value]
    (assoc m key value))
  (assocEx [_ key value]
    (.assocEx ^clojure.lang.IPersistentMap m key value))
  (without [_ key]
    (dissoc m key))
  (containsKey [_ key]
    (contains? m key))
  (entryAt [_ key]
    (find m key))
  (cons [_ value]
    (conj m value))
  (empty [_]
    (empty m))
  (equiv [_ other]
    (cond
      (instance? KeyedRow other) (= m (.-m ^KeyedRow other))
      :else (= m other)))
  clojure.lang.ILookup
  (valAt [_ key]
    (get m key))
  (valAt [_ key not-found]
    (get m key not-found))
  clojure.lang.Indexed
  (nth [_ index]
    (nth values index))
  (nth [_ index not-found]
    (nth values index not-found))
  clojure.lang.Counted
  (count [_]
    (count values))
  clojure.lang.IHashEq
  (hasheq [_]
    (clojure.lang.Util/hasheq m))
  clojure.lang.Seqable
  (seq [_]
    (seq m))
  Iterable
  (iterator [_]
    (.iterator ^Iterable m))
  Object
  (equals [_ other]
    (cond
      (instance? KeyedRow other) (= m (.-m ^KeyedRow other))
      (map? other) (= m other)
      :else false))
  (hashCode [_]
    (hash m))
  (toString [_]
    (str m)))

(deftype CountedRelationResult [n materialized]
  clojure.lang.Counted
  (count [_]
    (int n))
  clojure.lang.Seqable
  (seq [_]
    (seq @materialized))
  Object
  (toString [_]
    (str @materialized)))

(defrecord Conn [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord DurableConn [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord Log [conn])

(defrecord SQLiteConn [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord DB [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(declare entity-get)

(deftype EntityView [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native))
  clojure.lang.ILookup
  (valAt [this key]
    (entity-get this key))
  (valAt [this key not-found]
    (let [value (entity-get this key)]
      (if (nil? value) not-found value))))

(defn retain-db
  "Return another owned handle to the same immutable DB value."
  [^DB db]
  (->DB (:engine db) (.retain (:native db))))

(defrecord PreparedQuery [^Vev engine native query]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord PreparedPullPattern [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord TxBuilder [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord TxFnRegistry [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord QueryFnRegistry [^Vev engine native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defrecord TxListenerRegistration [native]
  java.lang.AutoCloseable
  (close [_]
    (.close ^java.lang.AutoCloseable native)))

(defn create-conn
  "Create an in-memory Vev connection.

  With no arguments, uses the Java wrapper's native library resolution:
  `vev.library`, `VEV_LIB`, local `build/lib`, then bundled native resource."
  ([]
   (let [engine (load-engine)]
     (try
       (->Conn engine (.createConn engine))
       (catch Throwable error
         (.close engine)
         (throw error)))))
  ([lib-path]
   (let [engine (load-engine lib-path)]
     (try
       (->Conn engine (.createConn engine))
       (catch Throwable error
         (.close engine)
         (throw error))))))

(def open create-conn)

(defn connect
  "Open a durable Vev connection.

  A plain filesystem path opens a local Vev store. The current local backend is
  SQLite internally, but application code should treat the returned handle as a
  Vev connection."
  ([uri]
   (let [engine (load-engine)]
     (try
       (->DurableConn engine (.connect engine (str uri)))
       (catch Throwable error
         (.close engine)
         (throw error)))))
  ([lib-path uri]
   (let [engine (load-engine lib-path)]
     (try
       (->DurableConn engine (.connect engine (str uri)))
       (catch Throwable error
         (.close engine)
         (throw error))))))

(defn open-sqlite
  "Open a durable SQLite-backed Vev connection.

  Prefer `connect` for application code; this backend-specific alias is for
  storage tests and migration/debugging."
  ([sqlite-path]
   (connect sqlite-path))
  ([lib-path sqlite-path]
   (connect lib-path sqlite-path)))

(defn db
  "Return an immutable DB snapshot from a connection."
  [conn]
  (cond
    (instance? Conn conn)
    (->DB (:engine conn) (.db (:native conn)))

    (instance? DurableConn conn)
    (->DB (:engine conn) (.db (:native conn)))

    (instance? SQLiteConn conn)
    (->DB (:engine conn) (.db (:native conn)))

    :else
    (throw (ex-info "expected Vev connection" {:source conn}))))

(defn connection-info
  "Return storage metadata for a durable connection."
  [conn]
  (cond
    (instance? DurableConn conn)
    {:backend (keyword (.backend (:native conn)))
     :path (.path (:native conn))
     :basis-t (.basisT (:native conn))
     :tx-count (.txCount (:native conn))
     :tx-ids (vec (.txIds (:native conn)))}

    :else
    (throw (ex-info "expected Vev durable connection" {:source conn}))))

(defn log
  "Return a Datomic-style transaction log value for a durable connection."
  [conn]
  (when-not (instance? DurableConn conn)
    (throw (ex-info "expected Vev durable connection" {:source conn})))
  (->Log conn))

(defn compact-indexes!
  "Compact durable index roots as an explicit maintenance operation."
  [conn]
  (cond
    (or (instance? DurableConn conn)
        (instance? SQLiteConn conn))
    (.compactIndexes (:native conn))

    :else
    (throw (ex-info "expected Vev durable connection" {:source conn}))))

(defn conn-from-db
  "Create a mutable connection initialized from a resident/in-memory DB value.

  Durable DB handles are immutable values; query/pull/with them directly
  instead of converting them back into connections."
  [^DB db]
  (->Conn (:engine db) (.connFromDb (:engine db) (:native db))))

(defn entity
  "Create an entity id value, or a DB-backed entity view.

  `(entity id)` returns an explicit entity id value for typed native APIs.
  `(entity db id)` returns a Datomic-style entity view over an immutable DB
  value. The view can be used with keyword lookup and closed explicitly when a
  caller wants prompt native release."
  ([id]
   (Vev$Entity. (long id)))
  ([^DB db eid]
   (let [native (cond
                  (integer? eid)
                  (.entity ^Vev$DB (:native db) (long eid))

                  (keyword? eid)
                  (.entityIdent ^Vev$DB (:native db) (edn-text eid))

                  (and (vector? eid)
                       (= 2 (count eid))
                       (keyword? (first eid))
                       (string? (second eid)))
                  (.entityLookupRefString ^Vev$DB (:native db)
                                          (edn-text (first eid))
                                          (second eid))

                  :else
                  (throw (ex-info "unsupported entity id"
                                  {:eid eid
                                   :supported #{:integer :ident-keyword :string-lookup-ref}})))]
     (EntityView. (:engine db) native))))

(defn entity-found?
  "Return true when a DB-backed entity view resolved to an entity."
  [^EntityView entity-view]
  (.found ^Vev$EntityView (.-native entity-view)))

(defn entity-id
  "Return the entity id for a DB-backed entity view."
  [^EntityView entity-view]
  (.id ^Vev$EntityView (.-native entity-view)))

(defn entity-get
  "Read the first value for attr from a DB-backed entity view."
  [^EntityView entity-view attr]
  (clj-value (.get ^Vev$EntityView (.-native entity-view) (edn-text attr))))

(defn entity-values
  "Read all values for attr from a DB-backed entity view."
  [^EntityView entity-view attr]
  (vec (clj-value (.values ^Vev$EntityView (.-native entity-view) (edn-text attr)))))

(defn entity-ref
  "Read the first ref attr as another DB-backed entity view."
  [^EntityView entity-view attr]
  (EntityView. (.-engine entity-view)
               (.ref ^Vev$EntityView (.-native entity-view) (edn-text attr))))

(defn entity-refs
  "Read all ref attr values as entity ids."
  [^EntityView entity-view attr]
  (vec (.refs ^Vev$EntityView (.-native entity-view) (edn-text attr))))

(defn touch
  "Return a realized map for a DB-backed entity view."
  [^EntityView entity-view]
  (clj-value (.touch ^Vev$EntityView (.-native entity-view))))

(defn- source-engine [source]
  (or (:engine source)
      (throw (ex-info "expected Vev source" {:source source}))))

(defn transact-text
  "Transact Clojure data or EDN text and return the raw EDN report text."
  [conn tx]
  (with-open [report (.transactReport (:native conn) (edn-text tx))]
    (.edn report)))

(def transact-text! transact-text)

(defn transact
  "Transact Clojure data or EDN text against a connection.

  Returns a Clojure transaction report map."
  ([conn tx]
   (with-open [report (if (instance? TxBuilder tx)
                        (.transactReport (:native conn) (:native tx))
                        (.transactReport (:native conn) (edn-text tx)))]
     (clj-value (.value report))))
  ([conn tx tx-fns]
   (when (instance? TxBuilder tx)
     (throw (ex-info "transaction function registries apply to EDN tx data, not TxBuilder values"
                     {:tx tx})))
   (when-not (or (instance? Conn conn)
                 (instance? DurableConn conn))
     (throw (ex-info "transaction function registries require a Vev connection"
                     {:conn conn})))
   (with-open [report (.transactReport (:native conn)
                                       (edn-text tx)
                                       (:native tx-fns))]
     (clj-value (.value report)))))

(def transact! transact)

(defn transact-bulk
  "Commit several native TxBuilder values as one durable transaction.

  This is explicit bulk ingestion: Vev flattens the builders into one ordinary
  transaction report, so the result has one tx id. Use ordinary `transact` when
  each input must remain its own transaction."
  [conn tx-builders]
  (when-not (instance? DurableConn conn)
    (throw (ex-info "transact-bulk requires a durable Vev connection"
                    {:conn conn})))
  (let [builders (vec tx-builders)]
    (when (empty? builders)
      (throw (ex-info "transact-bulk requires at least one TxBuilder" {})))
    (doseq [builder builders]
      (when-not (instance? TxBuilder builder)
        (throw (ex-info "transact-bulk expects TxBuilder values"
                        {:builder builder}))))
    (with-open [report (.transactReport (:native conn)
                                        (java.util.ArrayList.
                                         (mapv :native builders)))]
      (clj-value (.value report)))))

(defn transact-logical-bulk
  "Commit several native TxBuilder values as several logical transactions under
  one durable commit.

  Unlike `transact-bulk`, this preserves one tx id and one transaction report
  per input builder."
  [conn tx-builders]
  (when-not (instance? DurableConn conn)
    (throw (ex-info "transact-logical-bulk requires a durable Vev connection"
                    {:conn conn})))
  (let [builders (vec tx-builders)]
    (doseq [builder builders]
      (when-not (instance? TxBuilder builder)
        (throw (ex-info "transact-logical-bulk expects TxBuilder values"
                        {:builder builder}))))
    (with-open [reports (.transactLogicalReports (:native conn)
                                                 (java.util.ArrayList.
                                                  (mapv :native builders)))]
      (mapv clj-value (.values reports)))))

(defn transact-logical
  "Commit several Clojure tx-data values or EDN tx strings as several logical
  transactions under one durable commit.

  This is the Datomic-style host-facing group shape: each input remains its own
  tx id and report, while Vev shares the durable SQLite commit."
  [conn txs]
  (when-not (instance? DurableConn conn)
    (throw (ex-info "transact-logical requires a durable Vev connection"
                    {:conn conn})))
  (let [texts (mapv edn-text txs)]
    (with-open [reports (.transactLogicalEdnReports (:native conn)
                                                    (java.util.ArrayList.
                                                     texts))]
      (mapv clj-value (.values reports)))))

(defn- listener-name [key]
  (cond
    (keyword? key) (str key)
    (symbol? key) (str key)
    (string? key) key
    :else (throw (ex-info "listener key must be a keyword, symbol, or string"
                          {:key key}))))

(defn listen
  "Register a transaction listener on a connection.

  The callback receives a Clojure transaction report map after successful
  commits. The returned registration is AutoCloseable; `unlisten` can also
  remove by key."
  [conn key f]
  (let [callback (reify Vev$TxReportListener
                   (accept [_ report]
                     (f (clj-value report))))]
    (cond
      (instance? Conn conn)
      (->TxListenerRegistration
       (.listen (:native conn) (listener-name key) callback))

      (instance? DurableConn conn)
      (->TxListenerRegistration
       (.listen (:native conn) (listener-name key) callback))

      :else
      (throw (ex-info "transaction listeners require a Vev connection"
                      {:conn conn})))))

(def listen! listen)

(defn unlisten
  "Remove a transaction listener registration or listener key."
  [conn key-or-registration]
  (cond
    (instance? TxListenerRegistration key-or-registration)
    (do
      (.close ^java.lang.AutoCloseable key-or-registration)
      true)

    (or (instance? Conn conn)
        (instance? DurableConn conn))
    (.unlisten (:native conn) (listener-name key-or-registration))

    :else
    (throw (ex-info "transaction listeners require a Vev connection"
                    {:conn conn}))))

(def unlisten! unlisten)

(defn empty-db
  "Return an owned immutable empty DB value."
  ([]
   (with-open [conn (create-conn)]
     (db conn)))
  ([lib-path]
   (with-open [conn (create-conn lib-path)]
     (db conn))))

(defn with-text
  "Apply EDN tx text to an immutable DB and return the raw EDN report text."
  [^DB db tx]
  (.with (:native db) (edn-text tx)))

(defn with
  "Apply tx data to an immutable DB and return a transaction report map."
  ([^DB db tx]
   (with-open [report (.withReport (:native db) (edn-text tx))]
     (clj-value (.value report))))
  ([^DB db tx tx-fns]
   (with-open [report (.withReport (:native db) (edn-text tx) (:native tx-fns))]
     (clj-value (.value report)))))

(defn with-report
  "Apply tx data to an immutable DB and return a transaction report map with
  owned `:db-before` and `:db-after` DB values."
  ([^DB db tx]
   (with-open [report (.withReport (:native db) (edn-text tx))]
     (assoc (clj-value (.value report))
            :db-before (->DB (:engine db) (.dbBefore report))
            :db-after (->DB (:engine db) (.dbAfter report)))))
  ([^DB db tx tx-fns]
   (with-open [report (.withReport (:native db) (edn-text tx) (:native tx-fns))]
     (assoc (clj-value (.value report))
            :db-before (->DB (:engine db) (.dbBefore report))
            :db-after (->DB (:engine db) (.dbAfter report))))))

(defn db-with
  "Apply tx data to an immutable DB and return the resulting immutable DB value."
  [^DB db tx]
  (if (instance? TxBuilder tx)
    (->DB (:engine db) (.dbWith (:native db) (:native tx)))
    (->DB (:engine db) (.dbWith (:native db) (edn-text tx)))))

(defn tx-builder
  "Create a native transaction builder for direct typed bulk tx construction."
  ([source]
   (tx-builder source 0))
  ([source capacity]
   (let [engine (:engine source)]
     (->TxBuilder engine (.txBuilder engine (int capacity))))))

(defn register-tx-fn
  "Register a Datomic-shaped transaction function in a registry.

  The callback receives `(db & args)` and returns ordinary tx-data."
  [^TxFnRegistry registry ident f]
  (let [engine (:engine registry)
        native-fn (reify Vev$TxFunction
                    (apply [_ native-db args]
                      (edn-text
                       (apply f
                              (->DB engine native-db)
                              (mapv clj-value args)))))]
    (.register (:native registry) (edn-text ident) native-fn)
    registry))

(defn tx-fns
  "Create a transaction function registry from `{ident fn}`.

  Registered functions can be called from tx-data with Datomic-style ident
  shorthand or `:db.fn/call` and passed to `transact` / `with`."
  [source registry]
  (let [engine (source-engine source)
        out (->TxFnRegistry engine (.txFunctionRegistry engine))]
    (try
      (doseq [[ident f] registry]
        (register-tx-fn out ident f))
      out
      (catch Throwable error
        (.close out)
        (throw error)))))

(defn- attr-text [attr]
  (cond
    (keyword? attr) (str attr)
    (string? attr) attr
    :else (throw (ex-info "expected tx attr keyword or string" {:attr attr}))))

(defn tx-add!
  "Append one :db/add datom to a native transaction builder."
  [^TxBuilder tx e attr value]
  (let [native (:native tx)
        e (long e)
        attr (attr-text attr)]
    (cond
      (string? value)
      (.addString native e attr value)

      (keyword? value)
      (.addKeyword native e attr (str value))

      (integer? value)
      (.addInt native e attr (long value))

      (boolean? value)
      (.addBool native e attr value)

      (instance? Vev$Entity value)
      (.addEntity native e attr (.id ^Vev$Entity value))

      :else
      (throw (ex-info "unsupported native tx builder value" {:value value}))))
  tx)

(defn bulk-add!
  "Append Datomic/DataScript-style entity maps to a native transaction builder."
  [^TxBuilder tx entities]
  (doseq [entity entities]
    (let [e (:db/id entity)]
      (when-not (integer? e)
        (throw (ex-info "bulk entity map requires integer :db/id" {:entity entity})))
      (doseq [[attr value] entity]
        (when-not (= attr :db/id)
          (tx-add! tx e attr value)))))
  tx)

(defn init-db
  "Create an immutable DB initialized by applying tx data to an empty DB."
  ([tx]
   (with-open [initial (empty-db)]
     (db-with initial tx)))
  ([lib-path tx]
   (with-open [initial (empty-db lib-path)]
     (db-with initial tx))))

(defn prepare
  "Prepare a query from Clojure data or EDN text."
  [source query]
  (let [engine (:engine source)]
    (->PreparedQuery engine (.prepare engine (edn-text query)) query)))

(defn prepared-edn
  "Return the portable EDN-ish parser value for a prepared query or pull pattern."
  [prepared]
  (edn/read-string
   (cond
     (instance? PreparedQuery prepared)
     (.edn (:native prepared))

     (instance? PreparedPullPattern prepared)
     (.edn (:native prepared))

     :else
     (throw (ex-info "prepared-edn expects a prepared query or pull pattern"
                     {:value prepared})))))

(defn parse-clause
  "Parse one Datalog where clause and return Vev's portable parser value."
  [source clause]
  (let [engine (:engine source)]
    (edn/read-string (.parseClauseEdn engine (edn-text clause)))))

(defn prepare-pull-pattern
  "Prepare a pull pattern from Clojure data or EDN text."
  [source pattern]
  (let [engine (:engine source)]
    (->PreparedPullPattern engine (.preparePullPattern engine (edn-text pattern)))))

(defn- source? [value]
  (or (instance? Conn value)
      (instance? DurableConn value)
      (instance? SQLiteConn value)
      (instance? Log value)
      (instance? DB value)))

(defn- datom-triple-source? [value]
  (and (vector? value)
       (every? (fn [datom]
                 (and (vector? datom)
                      (= 3 (count datom))))
               value)))

(defn- datom-triples->tx [datoms]
  (mapv (fn [[e a v]]
          [:db/add e a v])
        datoms))

(defn- normalize-query-call [first-arg second-arg inputs]
  (if (source? first-arg)
    {:source first-arg :query second-arg :inputs inputs}
    {:source second-arg :query first-arg :inputs inputs}))

(defn- query-in-forms [query]
  (cond
    (instance? PreparedQuery query)
    (query-in-forms (:query query))

    (map? query)
    (:in query)

    (vector? query)
    (let [tail (drop-while #(not= :in %) query)]
      (when (seq tail)
        (take-while #(not (#{:where :with :keys :strs :syms} %)) (rest tail))))

    :else
    nil))

(defn- query-explicitly-takes-db? [query]
  (some #(= '$ %) (query-in-forms query)))

(defn- source-less-query-call? [query source]
  (and (not (source? source))
       (some? (query-in-forms query))
       (not (query-explicitly-takes-db? query))))

(defn- query-find-forms [query]
  (cond
    (instance? PreparedQuery query)
    (query-find-forms (:query query))

    (map? query)
    (:find query)

    (vector? query)
    (let [tail (drop-while #(not= :find %) query)]
      (when (seq tail)
        (take-while #(not (#{:where :with :in :keys :strs :syms} %)) (rest tail))))

    (string? query)
    (try
      (query-find-forms (edn/read-string query))
      (catch Exception _ nil))

    :else
    nil))

(defn- query-find-shape [query]
  (let [find-forms (vec (or (query-find-forms query) []))
        first-form (first find-forms)]
    (cond
      (and (= 2 (count find-forms))
           (= '. (second find-forms)))
      :scalar

      (and (= 1 (count find-forms))
           (vector? first-form)
           (= 2 (count first-form))
           (= '... (second first-form)))
      :collection

      (and (= 1 (count find-forms))
           (vector? first-form)
           (not= '... (second first-form)))
      :tuple

      :else
      :relation)))

(defn- first-row-value [rows]
  (some-> rows first first))

(defn- distinct-aggregate-form? [form]
  (and (seq? form)
       (= 'distinct (first form))))

(defn- distinct-aggregate-indexes [query]
  (keep-indexed (fn [index form]
                  (when (distinct-aggregate-form? form)
                    index))
                (or (query-find-forms query) [])))

(defn- limited-rand-aggregate-form? [form]
  (and (seq? form)
       (= 'rand (first form))
       (= 3 (count form))))

(defn- limited-rand-aggregate-indexes [query]
  (keep-indexed (fn [index form]
                  (when (limited-rand-aggregate-form? form)
                    index))
                (or (query-find-forms query) [])))

(defn- coerce-distinct-aggregate-value [value]
  (if (sequential? value)
    (set value)
    value))

(defn- coerce-limited-rand-aggregate-value [value]
  (if (sequential? value)
    (seq value)
    value))

(defn- coerce-distinct-aggregate-row [indexes row]
  (if (seq indexes)
    (reduce (fn [out index]
              (if (< index (count out))
                (assoc out index (coerce-distinct-aggregate-value (nth out index)))
                out))
            (vec row)
            indexes)
    row))

(defn- coerce-limited-rand-aggregate-row [indexes row]
  (if (seq indexes)
    (reduce (fn [out index]
              (if (< index (count out))
                (assoc out index (coerce-limited-rand-aggregate-value (nth out index)))
                out))
            (vec row)
            indexes)
    row))

(defn- coerce-distinct-aggregates [query rows]
  (let [indexes (vec (distinct-aggregate-indexes query))]
    (if (seq indexes)
      (mapv #(coerce-distinct-aggregate-row indexes %) rows)
      rows)))

(defn- coerce-limited-rand-aggregates [query rows]
  (let [indexes (vec (limited-rand-aggregate-indexes query))]
    (if (seq indexes)
      (mapv #(coerce-limited-rand-aggregate-row indexes %) rows)
      rows)))

(defn- apply-find-shape [query rows]
  (let [rows (->> rows
                  (coerce-distinct-aggregates query)
                  (coerce-limited-rand-aggregates query))]
    (case (query-find-shape query)
      :scalar (first-row-value rows)
      :collection (vec (distinct (map first rows)))
      :tuple (first rows)
      :relation (set rows))))

(defn- log-input-env [query inputs]
  (let [inputv (vec inputs)]
    (loop [forms (rest (vec (or (query-in-forms query) [])))
           index 0
           out {}]
      (if-let [form (first forms)]
        (if (symbol? form)
          (recur (rest forms) (inc index) (assoc out form (nth inputv index nil)))
          (recur (rest forms) index out))
        out))))

(defn- log-term-value [env term]
  (cond
    (symbol? term) (get env term)
    :else term))

(defn- log-where-forms [query]
  (cond
    (map? query)
    (:where query)

    (vector? query)
    (let [tail (drop-while #(not= :where %) query)]
      (when (seq tail)
        (take-while #(not (#{:in :keys :strs :syms} %)) (rest tail))))

    :else
    nil))

(defn- log-function-clause [query]
  (some (fn [form]
          (when (and (vector? form)
                     (= 2 (count form))
                     (seq? (first form)))
            form))
        (log-where-forms query)))

(defn- log-tx-data [^Log log-value tx]
  (edn/read-string (.txDataEdn (:native (:conn log-value)) (long tx))))

(defn- log-output-vars [binding]
  (cond
    (and (vector? binding)
         (= 2 (count binding))
         (= '... (second binding)))
    [(first binding)]

    (and (vector? binding)
         (= 1 (count binding))
         (vector? (first binding)))
    (vec (first binding))

    (vector? binding)
    (vec binding)

    :else
    []))

(defn- log-query-rows [^Log log-value query inputs]
  (let [query (if (string? query) (edn/read-string query) query)
        env (log-input-env query inputs)
        clause (log-function-clause query)
        call (first clause)
        binding (second clause)
        op (first call)]
    (case op
      tx-ids
      (let [start (long (log-term-value env (nth call 2)))
            end (long (log-term-value env (nth call 3)))
            ids (filter #(and (<= start %) (< % end))
                        (.txIds (:native (:conn log-value))))]
        (mapv vector ids))

      tx-data
      (let [tx (long (log-term-value env (nth call 2)))
            datoms (log-tx-data log-value tx)
            vars (log-output-vars binding)
            width (max 1 (count vars))]
        (mapv (fn [datom]
                (vec (take width datom)))
              datoms))

      (throw (ex-info "unsupported Vev log query function" {:op op :query query})))))

(defn- log-query-output [^Log log-value query inputs]
  (let [query (if (string? query) (edn/read-string query) query)]
    (apply-find-shape query (log-query-rows log-value query inputs))))

(defn- marker-key [marker value]
  (case marker
    :keys (cond
            (keyword? value) value
            (symbol? value) (keyword (name value))
            (string? value) (keyword value)
            :else value)
    :strs (cond
            (keyword? value) (name value)
            (symbol? value) (name value)
            :else value)
    :syms (cond
            (keyword? value) (symbol (name value))
            (string? value) (symbol value)
            :else value)))

(defn- query-return-map [query]
  (let [from-map (fn [query]
                   (some (fn [marker]
                           (when-let [items (get query marker)]
                             {:marker marker
                              :keys (mapv #(marker-key marker %) items)}))
                         [:keys :strs :syms]))
        from-vector (fn [query]
                      (loop [items (seq query)]
                        (when-let [item (first items)]
                          (if (#{:keys :strs :syms} item)
                            {:marker item
                             :keys (mapv #(marker-key item %)
                                         (take-while #(not (#{:in :where :with} %))
                                                     (rest items)))}
                            (recur (rest items))))))]
    (cond
      (instance? PreparedQuery query) (query-return-map (:query query))
      (map? query) (from-map query)
      (vector? query) (from-vector query)
      (string? query) (try
                        (query-return-map (edn/read-string query))
                        (catch Exception _ nil))
      :else nil)))

(defn- query-where-forms [query]
  (cond
    (map? query)
    (:where query)

    (vector? query)
    (let [tail (drop-while #(not= :where %) query)]
      (when (seq tail)
        (take-while #(not (#{:in :keys :strs :syms} %)) (rest tail))))

    (string? query)
    (try
      (query-where-forms (edn/read-string query))
      (catch Exception _ nil))

    :else
    nil))

(defn- query-with-forms [query]
  (cond
    (map? query)
    (:with query)

    (vector? query)
    (let [tail (drop-while #(not= :with %) query)]
      (when (seq tail)
        (take-while #(not (#{:in :where :keys :strs :syms} %)) (rest tail))))

    (string? query)
    (try
      (query-with-forms (edn/read-string query))
      (catch Exception _ nil))

    :else
    nil))

(defn- relation-source-clause-vars [clause]
  (set (filter symbol? clause)))

(defn- relation-source-components [clauses]
  (reduce
   (fn [components clause]
     (let [vars (relation-source-clause-vars clause)
           matches (filter #(seq (set/intersection (:vars %) vars)) components)
           others (remove #(seq (set/intersection (:vars %) vars)) components)
           merged {:vars (apply set/union vars (map :vars matches))
                   :clauses (vec (cons clause (mapcat :clauses matches)))}]
       (conj (vec others) merged)))
   []
   clauses))

(defn- relation-source-row-term-value [row position]
  (when (and (vector? row) (< position (count row)))
    (nth row position)))

(defn- relation-source-term-matches? [binding row position term]
  (let [actual (relation-source-row-term-value row position)]
    (cond
      (nil? actual) nil
      (= '_ term) binding
      (symbol? term) (if-let [existing (get binding term)]
                       (when (= existing actual) binding)
                       (assoc binding term actual))
      :else (when (= term actual) binding))))

(defn- relation-source-match-clause [row clause]
  (when (and (vector? row) (= 3 (count clause)) (= 3 (count row)))
    (loop [position 0
           binding {}]
      (if (= position 3)
        binding
        (when-let [next-binding (relation-source-term-matches? binding row position (nth clause position))]
          (recur (inc position) next-binding))))))

(defn- relation-source-single-clause-component-count [rows clause projection-vars]
  (let [seen (transient #{})]
    (doseq [row rows]
      (when-let [binding (relation-source-match-clause row clause)]
        (conj! seen (mapv binding projection-vars))))
    (count (persistent! seen))))

(defn- relation-source-fast-projected-count [query rows]
  (when (and (= :relation (query-find-shape query))
             (not (seq (query-with-forms query))))
    (let [find-vars (vec (filter symbol? (query-find-forms query)))
          where-forms (vec (query-where-forms query))
          clauses (vec (filter #(and (vector? %) (= 3 (count %))) where-forms))
          components (relation-source-components clauses)]
      (when (and (seq find-vars)
                 (= (count clauses) (count where-forms))
                 (every? #(= 1 (count (:clauses %))) components))
        (loop [remaining components
               covered #{}
               out 1]
          (if (empty? remaining)
            (when (= (set find-vars) covered)
              out)
            (let [component (first remaining)
                  projection-vars (vec (filter (:vars component) find-vars))
                  clause (first (:clauses component))]
              (when (seq projection-vars)
                (recur (rest remaining)
                       (set/union covered (set projection-vars))
                       (* out (relation-source-single-clause-component-count rows clause projection-vars)))))))))))

(defn- host-symbol? [value]
  (and (symbol? value) (some? (namespace value))))

(defn- host-aggregate-symbols [query]
  (->> (query-find-forms query)
       (keep (fn [form]
               (when (and (seq? form)
                          (host-symbol? (first form)))
                 (first form))))
       distinct
       vec))

(defn- host-predicate-symbols [query]
  (->> (query-where-forms query)
       (keep (fn [form]
               (when (and (vector? form)
                          (= 1 (count form))
                          (seq? (first form))
                          (host-symbol? (ffirst form)))
                 (ffirst form))))
       distinct
       vec))

(defn- resolve-host-fn [sym]
  (or (resolve sym)
      (requiring-resolve sym)))

(defn query-fns
  "Create a query function registry from maps of namespaced Clojure callbacks.

  `:predicates` callbacks return truthy/falsey values. `:aggregates` callbacks
  receive a vector of values and return any EDN-printable Vev value."
  [source {:keys [predicates aggregates]}]
  (let [engine (source-engine source)
        out (->QueryFnRegistry engine (.queryFunctionRegistry engine))]
    (try
      (doseq [[ident f] predicates]
        (let [native-fn (reify Vev$QueryPredicate
                          (test [_ args]
                            (boolean (f (mapv clj-value args)))))]
          (.registerPredicate (:native out) (str ident) native-fn)))
      (doseq [[ident f] aggregates]
        (let [native-fn (reify Vev$QueryAggregate
                          (apply [_ values]
                            (edn-text (f (mapv clj-value values)))))]
          (.registerAggregate (:native out) (str ident) native-fn)))
      out
      (catch Throwable error
        (.close out)
        (throw error)))))

(defn- auto-query-fns [source query]
  (let [predicates (into {}
                         (map (fn [sym] [sym (resolve-host-fn sym)]))
                         (host-predicate-symbols query))
        aggregates (into {}
                         (map (fn [sym] [sym (resolve-host-fn sym)]))
                         (host-aggregate-symbols query))]
    (when (or (seq predicates) (seq aggregates))
      (query-fns source {:predicates predicates :aggregates aggregates}))))

(defn- keyed-rows [return-map rows]
  (let [keys (:keys return-map)]
    (mapv (fn [row]
            (KeyedRow. (zipmap keys row) (vec row)))
          rows)))

(defn- keyed-set [return-map rows]
  (set (keyed-rows return-map rows)))

(defn- normalize-rules-input [rules]
  (if (and (seq? rules)
           (not (vector? rules)))
    (vec rules)
    rules))

(defn- split-rules-input [query inputs]
  (let [in-forms (query-in-forms query)
        inputv (vec inputs)]
    (if-not (seq in-forms)
      {:inputs inputs}
      (loop [forms in-forms
             input-index 0]
        (if-let [form (first forms)]
          (cond
            (= '$ form)
            (recur (rest forms) input-index)

            (= '% form)
            (if (< input-index (count inputv))
              {:rules (normalize-rules-input (nth inputv input-index))
               :inputs (vec (concat (subvec inputv 0 input-index)
                                    (subvec inputv (inc input-index))))}
              {:inputs inputs})

            :else
            (recur (rest forms) (inc input-index)))
          {:inputs inputs})))))

(defn query-result
  "Run a prepared query and return the native result handle. Caller owns it."
  [source ^PreparedQuery prepared & inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? Conn source)
      (.query (:native source) (:native prepared) input-edn)

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) input-edn))

      (instance? DB source)
      (.query (:native source) (:native prepared) input-edn)

      :else
      (throw (ex-info "expected Vev connection or DB" {:source source})))))

(defn query-result-with-fns
  "Run a prepared query with a query function registry. Caller owns result."
  [source ^PreparedQuery prepared ^QueryFnRegistry registry & inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) input-edn (:native registry)))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) input-edn (:native registry)))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) input-edn (:native registry)))

      (instance? DB source)
      (.query (:native source) (:native prepared) input-edn (:native registry))

      :else
      (throw (ex-info "expected Vev connection or DB" {:source source})))))

(defn query-result-with-rules
  "Run a prepared query with rules and return the native result handle. Caller owns it."
  [source ^PreparedQuery prepared rules & inputs]
  (let [rules-edn (edn-text rules)
        input-edn (inputs-text inputs)]
    (cond
      (instance? Conn source)
      (.query (:native source) (:native prepared) rules-edn input-edn)

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) rules-edn input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.query (:native snapshot) (:native prepared) rules-edn input-edn))

      (instance? DB source)
      (.query (:native source) (:native prepared) rules-edn input-edn)

      :else
      (throw (ex-info "expected Vev connection or DB" {:source source})))))

(defn- single-entity-rows [result]
  (when-let [ids (.singleEntityColumn result)]
    (let [^longs ids ids
          n (alength ids)]
      (loop [index 0
             out (transient [])]
        (if (< index n)
          (recur (inc index)
                 (conj! out [(long (aget ids index))]))
          (persistent! out))))))

(defn- rows-from-result [result]
  (or (single-entity-rows result)
      (mapv clj-value (.rows result))))

(defn- q-from-result [result]
  (if-let [ids (.singleEntityColumn result)]
    (let [^longs ids ids
          n (alength ids)]
      (loop [index 0
             out (transient #{})]
        (if (< index n)
          (recur (inc index)
                 (conj! out [(long (aget ids index))]))
          (persistent! out))))
    (set (mapv clj-value (.rows result)))))

(defn- entity-column [source ^PreparedQuery prepared inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryEntityColumn (:native source) (:native prepared) input-edn)

      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.queryEntityColumn (:native snapshot) (:native prepared) input-edn))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.queryEntityColumn (:native snapshot) (:native prepared) input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.queryEntityColumn (:native snapshot) (:native prepared) input-edn))

      :else
      nil)))

(defn- string-column [source ^PreparedQuery prepared inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryStringColumn (:native source) (:native prepared) input-edn)

      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.queryStringColumn (:native snapshot) (:native prepared) input-edn))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.queryStringColumn (:native snapshot) (:native prepared) input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.queryStringColumn (:native snapshot) (:native prepared) input-edn))

      :else
      nil)))

(defn- entity-int-pair-columns [source ^PreparedQuery prepared inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryEntityIntPairColumns (:native source) (:native prepared) input-edn)

      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.queryEntityIntPairColumns (:native snapshot) (:native prepared) input-edn))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.queryEntityIntPairColumns (:native snapshot) (:native prepared) input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.queryEntityIntPairColumns (:native snapshot) (:native prepared) input-edn))

      :else
      nil)))

(defn- entity-string-int-triples [source ^PreparedQuery prepared inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryEntityStringIntTripleColumns (:native source) (:native prepared) input-edn)

      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.queryEntityStringIntTripleColumns (:native snapshot) (:native prepared) input-edn))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.queryEntityStringIntTripleColumns (:native snapshot) (:native prepared) input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.queryEntityStringIntTripleColumns (:native snapshot) (:native prepared) input-edn))

      :else
      nil)))

(defn- column-result [source ^PreparedQuery prepared inputs]
  (let [input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryColumns (:native source) (:native prepared) input-edn)

      (instance? Conn source)
      (.queryColumns (:native source) (:native prepared) input-edn)

      (instance? DurableConn source)
      (.queryColumns (:native source) (:native prepared) input-edn)

      (instance? SQLiteConn source)
      (.queryColumns (:native source) (:native prepared) input-edn)

      :else
      nil)))

(defn- column-result-with-rules [source ^PreparedQuery prepared rules inputs]
  (let [rules-edn (edn-text rules)
        input-edn (inputs-text inputs)]
    (cond
      (instance? DB source)
      (.queryColumns (:native source) (:native prepared) rules-edn input-edn)

      (instance? Conn source)
      (with-open [snapshot (db source)]
        (.queryColumns (:native snapshot) (:native prepared) rules-edn input-edn))

      (instance? DurableConn source)
      (with-open [snapshot (db source)]
        (.queryColumns (:native snapshot) (:native prepared) rules-edn input-edn))

      (instance? SQLiteConn source)
      (with-open [snapshot (db source)]
        (.queryColumns (:native snapshot) (:native prepared) rules-edn input-edn))

      :else
      nil)))

(defn- column-kind [kind]
  (cond
    (= kind Vev/COLUMN_ENTITY) :entity
    (= kind Vev/COLUMN_STRING) :string
    (= kind Vev/COLUMN_INT) :int
    (= kind Vev/COLUMN_MIXED) :mixed
    (= kind Vev/COLUMN_BOOL) :bool
    (= kind Vev/COLUMN_FLOAT) :float
    (= kind Vev/COLUMN_VALUE) :value
    (= kind Vev/COLUMN_KEYWORD) :keyword
    (= kind Vev/COLUMN_SYMBOL) :symbol
    (= kind Vev/COLUMN_UUID) :uuid
    :else :unknown))

(defn- column-result->map [^Vev$ColumnResult result]
  (let [^ints kinds (.kinds result)
        ^objects columns (.columns result)
        width (alength kinds)]
    {:row-count (.rowCount result)
     :kinds (mapv #(column-kind (aget kinds %)) (range width))
     :columns (mapv #(mapv clj-value (aget columns %)) (range width))}))

(defn column-batch
  "Run a query and return Vev's native column batch when the result can be
  represented as flat primitive columns.

  Returns nil when the query needs the general row/result representation. This
  is the low-overhead host API for callers that want column-oriented data."
  [query source & inputs]
  (let [{:keys [query source inputs]} (normalize-query-call query source inputs)]
    (if (instance? PreparedQuery query)
      (column-result source query inputs)
      (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
        (with-open [prepared (prepare source query)]
          (if rules
            (column-result-with-rules source prepared rules inputs)
            (column-result source prepared inputs)))))))

(defn columns
  "Run a query and return an ergonomic column result map:

  `{:row-count n :kinds [:entity :string ...] :columns [[...]
  [...]]}`.

  Returns nil when the query needs the general row/result representation."
  [query source & inputs]
  (when-let [result (apply column-batch query source inputs)]
    (column-result->map result)))

(defn- entity-column-rows [ids]
  (let [^longs ids ids
        n (alength ids)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget ids index))]))
        (persistent! out)))))

(defn- entity-column-set [ids]
  (let [^longs ids ids
        n (alength ids)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget ids index))]))
        (persistent! out)))))

(defn- string-column-rows [values]
  (let [^objects values values
        n (alength values)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget values index)]))
        (persistent! out)))))

(defn- string-column-set [values]
  (let [^objects values values
        n (alength values)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget values index)]))
        (persistent! out)))))

(defn- entity-int-pair-rows [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^longs values (aget columns 1)
        n (alength entities)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index)) (long (aget values index))]))
        (persistent! out)))))

(defn- entity-int-pair-set [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^longs values (aget columns 1)
        n (alength entities)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index)) (long (aget values index))]))
        (persistent! out)))))

(defn- entity-string-pair-rows [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^objects values (aget columns 1)
        n (alength entities)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index)) (aget values index)]))
        (persistent! out)))))

(defn- entity-string-pair-set [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^objects values (aget columns 1)
        n (alength entities)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index)) (aget values index)]))
        (persistent! out)))))

(defn- string-int-pair-rows [columns]
  (let [^objects columns columns
        ^objects strings (aget columns 0)
        ^longs values (aget columns 1)
        n (alength strings)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget strings index) (long (aget values index))]))
        (persistent! out)))))

(defn- string-int-pair-set [columns]
  (let [^objects columns columns
        ^objects strings (aget columns 0)
        ^longs values (aget columns 1)
        n (alength strings)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget strings index) (long (aget values index))]))
        (persistent! out)))))

(defn- string-string-pair-rows [columns]
  (let [^objects columns columns
        ^objects first-values (aget columns 0)
        ^objects second-values (aget columns 1)
        n (alength first-values)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget first-values index) (aget second-values index)]))
        (persistent! out)))))

(defn- string-string-pair-set [columns]
  (let [^objects columns columns
        ^objects first-values (aget columns 0)
        ^objects second-values (aget columns 1)
        n (alength first-values)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget first-values index) (aget second-values index)]))
        (persistent! out)))))

(defn- entity-string-int-triple-rows [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^objects strings (aget columns 1)
        ^longs values (aget columns 2)
        n (alength entities)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index))
                           (aget strings index)
                           (long (aget values index))]))
        (persistent! out)))))

(defn- entity-string-int-triple-set [columns]
  (let [^objects columns columns
        ^longs entities (aget columns 0)
        ^objects strings (aget columns 1)
        ^longs values (aget columns 2)
        n (alength entities)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(long (aget entities index))
                           (aget strings index)
                           (long (aget values index))]))
        (persistent! out)))))

(defn- string-string-int-triple-rows [columns]
  (let [^objects columns columns
        ^objects first-values (aget columns 0)
        ^objects second-values (aget columns 1)
        ^longs third-values (aget columns 2)
        n (alength first-values)]
    (loop [index 0
           out (transient [])]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget first-values index)
                           (aget second-values index)
                           (long (aget third-values index))]))
        (persistent! out)))))

(defn- string-string-int-triple-set [columns]
  (let [^objects columns columns
        ^objects first-values (aget columns 0)
        ^objects second-values (aget columns 1)
        ^longs third-values (aget columns 2)
        n (alength first-values)]
    (loop [index 0
           out (transient #{})]
      (if (< index n)
        (recur (inc index)
               (conj! out [(aget first-values index)
                           (aget second-values index)
                           (long (aget third-values index))]))
        (persistent! out)))))

(defn- column-value-at [^ints kinds ^objects columns column row]
  (let [kind (aget kinds column)
        values (aget columns column)]
    (cond
      (= kind Vev/COLUMN_ENTITY)
      (long (aget ^longs values row))

      (= kind Vev/COLUMN_INT)
      (long (aget ^longs values row))

      (= kind Vev/COLUMN_STRING)
      (aget ^objects values row)

      (= kind Vev/COLUMN_KEYWORD)
      (keyword (subs (aget ^objects values row) 1))

      (= kind Vev/COLUMN_SYMBOL)
      (symbol (aget ^objects values row))

      (= kind Vev/COLUMN_UUID)
      (java.util.UUID/fromString (aget ^objects values row))

      (= kind Vev/COLUMN_BOOL)
      (boolean (aget ^booleans values row))

      (= kind Vev/COLUMN_FLOAT)
      (double (aget ^doubles values row))

      :else
      (clj-value (aget ^objects values row)))))

(defn- column-result-rows [^Vev$ColumnResult result]
  (let [^ints kinds (.kinds result)
        ^objects columns (.columns result)
        width (alength kinds)
        row-count (.rowCount result)]
    (loop [row 0
           out (transient [])]
      (if (< row row-count)
        (recur (inc row)
               (conj! out
                      (loop [column 0
                             row-values (transient [])]
                        (if (< column width)
                          (recur (inc column)
                                 (conj! row-values (column-value-at kinds columns column row)))
                          (persistent! row-values)))))
        (persistent! out)))))

(defn- column-result-set [^Vev$ColumnResult result]
  (let [^ints kinds (.kinds result)
        ^objects columns (.columns result)
        width (alength kinds)
        row-count (.rowCount result)]
    (loop [row 0
           out (transient #{})]
      (if (< row row-count)
        (recur (inc row)
               (conj! out
                      (loop [column 0
                             row-values (transient [])]
                        (if (< column width)
                          (recur (inc column)
                                 (conj! row-values (column-value-at kinds columns column row)))
                          (persistent! row-values)))))
        (persistent! out)))))

(defn- optimized-query-output [source prepared inputs entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (if-let [columns (column-result source prepared inputs)]
    (let [^Vev$ColumnResult columns columns
          ^ints kinds (.kinds columns)
          ^objects values (.columns columns)]
      (cond
        (and (= (alength kinds) 1)
             (= (aget kinds 0) Vev/COLUMN_ENTITY))
        (entity-fn (aget values 0))

        (and (= (alength kinds) 1)
             (= (aget kinds 0) Vev/COLUMN_STRING))
        (string-fn (aget values 0))

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_ENTITY))
        (pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_INT))
        (pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_STRING))
        (string-pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_INT))
        (string-int-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_STRING))
        (string-string-fn values)

        (and (= (alength kinds) 3)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_STRING)
             (= (aget kinds 2) Vev/COLUMN_INT))
        (triple-fn values)

        (and (= (alength kinds) 3)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_STRING)
             (= (aget kinds 2) Vev/COLUMN_INT))
        (string-string-int-triple-fn values)

        :else
        nil))
    (if-let [ids (entity-column source prepared inputs)]
      (entity-fn ids)
      (if-let [values (string-column source prepared inputs)]
        (string-fn values)
        (if-let [columns (entity-int-pair-columns source prepared inputs)]
          (pair-fn columns)
          (when-let [columns (entity-string-int-triples source prepared inputs)]
            (triple-fn columns)))))))

(defn- optimized-column-output [^Vev$ColumnResult columns entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (when columns
    (let [^ints kinds (.kinds columns)
          ^objects values (.columns columns)]
      (cond
        (and (= (alength kinds) 1)
             (= (aget kinds 0) Vev/COLUMN_ENTITY))
        (entity-fn (aget values 0))

        (and (= (alength kinds) 1)
             (= (aget kinds 0) Vev/COLUMN_STRING))
        (string-fn (aget values 0))

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_ENTITY))
        (pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_INT))
        (pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_STRING))
        (string-pair-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_INT))
        (string-int-fn values)

        (and (= (alength kinds) 2)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_STRING))
        (string-string-fn values)

        (and (= (alength kinds) 3)
             (= (aget kinds 0) Vev/COLUMN_ENTITY)
             (= (aget kinds 1) Vev/COLUMN_STRING)
             (= (aget kinds 2) Vev/COLUMN_INT))
        (triple-fn values)

        (and (= (alength kinds) 3)
             (= (aget kinds 0) Vev/COLUMN_STRING)
             (= (aget kinds 1) Vev/COLUMN_STRING)
             (= (aget kinds 2) Vev/COLUMN_INT))
        (string-string-int-triple-fn values)

        :else
        nil))))

(defn- column-output [^Vev$ColumnResult columns generic-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (or (optimized-column-output columns
                               entity-fn
                               string-fn
                               pair-fn
                               string-pair-fn
                               string-int-fn
                               string-string-fn
                               triple-fn
                               string-string-int-triple-fn)
      (when columns
        (generic-fn columns))))

(defn- relation-db-query-output [query rows inputs result-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (with-open [engine (load-engine)
              prepared (.prepare engine (edn-text query))]
    (or (optimized-column-output (.queryRelationDbColumns engine (edn-text rows) prepared (inputs-text inputs))
                                 entity-fn
                                 string-fn
                                 pair-fn
                                 string-pair-fn
                                 string-int-fn
                                 string-string-fn
                                 triple-fn
                                 string-string-int-triple-fn)
        (with-open [result (.queryRelationDb engine (edn-text rows) prepared (inputs-text inputs))]
          (result-fn result)))))

(defn- relation-db-result-count [query rows inputs]
  (with-open [engine (load-engine)
              prepared (.prepare engine (edn-text query))]
    (let [row-count (.queryRelationDbRowCount engine (edn-text rows) prepared (inputs-text inputs))]
      (when (not (neg? row-count))
        row-count))))

(defn- q-relation-db [query rows inputs]
  (if-let [return-map (query-return-map query)]
    (keyed-set return-map
               (relation-db-query-output query rows inputs
                                         rows-from-result
                                         entity-column-rows
                                         string-column-rows
                                         entity-int-pair-rows
                                         entity-string-pair-rows
                                         string-int-pair-rows
                                         string-string-pair-rows
                                         entity-string-int-triple-rows
                                         string-string-int-triple-rows))
    (if (= :relation (query-find-shape query))
      (let [materialize #(relation-db-query-output query rows inputs
                                                   q-from-result
                                                   entity-column-set
                                                   string-column-set
                                                   entity-int-pair-set
                                                   entity-string-pair-set
                                                   string-int-pair-set
                                                   string-string-pair-set
                                                   entity-string-int-triple-set
                                                   string-string-int-triple-set)
            row-count (or (relation-source-fast-projected-count query rows)
                          (relation-db-result-count query rows inputs))]
        (if (and row-count (> row-count 100000))
          (CountedRelationResult. row-count (delay (materialize)))
          (materialize)))
      (apply-find-shape
       query
       (relation-db-query-output query rows inputs
                                 rows-from-result
                                 entity-column-rows
                                 string-column-rows
                                 entity-int-pair-rows
                                 entity-string-pair-rows
                                 string-int-pair-rows
                                 string-string-pair-rows
                                 entity-string-int-triple-rows
                                 string-string-int-triple-rows)))))

(defn- prepared-query-output [source prepared inputs result-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (or (optimized-query-output source prepared inputs entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn)
      (with-open [result (apply query-result source prepared inputs)]
        (result-fn result))))

(defn- prepared-query-output-with-fns [source prepared inputs registry result-fn]
  (with-open [result (apply query-result-with-fns source prepared registry inputs)]
    (result-fn result)))

(defn profile
  "Run a prepared query against a DB and return Vev's native query stats."
  [^PreparedQuery prepared ^DB db & inputs]
  (edn/read-string (.profileEdn (:native db) (:native prepared) (inputs-text inputs))))

(defn profile-with-rules
  "Run a prepared query with Datomic-style rules against a DB and return Vev's native query stats."
  [^PreparedQuery prepared ^DB db rules & inputs]
  (edn/read-string (.profileEdn (:native db)
                                (:native prepared)
                                (edn-text rules)
                                (inputs-text inputs))))

(defn- query-output [source prepared rules inputs result-fn column-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (if rules
    (or (column-output (column-result-with-rules source prepared rules inputs)
                       column-fn
                       entity-fn
                       string-fn
                       pair-fn
                       string-pair-fn
                       string-int-fn
                       string-string-fn
                       triple-fn
                       string-string-int-triple-fn)
        (with-open [result (apply query-result-with-rules source prepared rules inputs)]
          (result-fn result)))
    (prepared-query-output source prepared inputs result-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn)))

(defn- query-output-with-auto-fns [source query prepared rules inputs result-fn column-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn]
  (if-let [registry (auto-query-fns source query)]
    (with-open [registry registry]
      (if rules
        (or (column-output (column-result-with-rules source prepared rules inputs)
                           column-fn
                           entity-fn
                           string-fn
                           pair-fn
                           string-pair-fn
                           string-int-fn
                           string-string-fn
                           triple-fn
                           string-string-int-triple-fn)
            (with-open [result (apply query-result-with-rules source prepared rules inputs)]
              (result-fn result)))
        (prepared-query-output-with-fns source prepared inputs registry result-fn)))
    (query-output source prepared rules inputs result-fn column-fn entity-fn string-fn pair-fn string-pair-fn string-int-fn string-string-fn triple-fn string-string-int-triple-fn)))

(defn rows
  "Run a query and return rows as a vector of Clojure vectors.

  Accepts both DB-first Vev style and query-first Datomic/DataScript style."
  [query source & inputs]
  (let [{:keys [query source inputs]} (normalize-query-call query source inputs)]
    (if (source-less-query-call? query source)
      (with-open [empty-source (empty-db)]
        (apply rows query empty-source source inputs))
      (if (instance? Log source)
        (log-query-rows source query inputs)
        (if (instance? PreparedQuery query)
          (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
            (query-output source query rules inputs
                          rows-from-result
                          column-result-rows
                          entity-column-rows
                          string-column-rows
                          entity-int-pair-rows
                          entity-string-pair-rows
                          string-int-pair-rows
                          string-string-pair-rows
                          entity-string-int-triple-rows
                          string-string-int-triple-rows))
          (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
            (with-open [prepared (prepare source query)]
              (let [result (query-output-with-auto-fns source query prepared rules inputs
                                                       rows-from-result
                                                       column-result-rows
                                                       entity-column-rows
                                                       string-column-rows
                                                       entity-int-pair-rows
                                                       entity-string-pair-rows
                                                       string-int-pair-rows
                                                       string-string-pair-rows
                                                       entity-string-int-triple-rows
                                                       string-string-int-triple-rows)]
                (if-let [return-map (query-return-map query)]
                  (keyed-rows return-map result)
                  result)))))))))

(defn q
  "Run a query and return Datomic-style results for the query find spec."
  [query source & inputs]
  (let [{:keys [query source inputs]} (normalize-query-call query source inputs)]
    (if (source-less-query-call? query source)
      (with-open [empty-source (empty-db)]
        (apply q query empty-source source inputs))
      (if (instance? Log source)
        (log-query-output source query inputs)
        (if (instance? PreparedQuery query)
          (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
            (if-let [return-map (query-return-map query)]
              (let [result (query-output source query rules inputs
                                         rows-from-result
                                         column-result-rows
                                         entity-column-rows
                                         string-column-rows
                                         entity-int-pair-rows
                                         entity-string-pair-rows
                                         string-int-pair-rows
                                         string-string-pair-rows
                                         entity-string-int-triple-rows
                                         string-string-int-triple-rows)]
                (keyed-set return-map result))
              (if (= :relation (query-find-shape query))
                (query-output source query rules inputs
                              q-from-result
                              column-result-set
                              entity-column-set
                              string-column-set
                              entity-int-pair-set
                              entity-string-pair-set
                              string-int-pair-set
                              string-string-pair-set
                              entity-string-int-triple-set
                              string-string-int-triple-set)
                (let [result (query-output source query rules inputs
                                           rows-from-result
                                           column-result-rows
                                           entity-column-rows
                                           string-column-rows
                                           entity-int-pair-rows
                                           entity-string-pair-rows
                                           string-int-pair-rows
                                           string-string-pair-rows
                                           entity-string-int-triple-rows
                                           string-string-int-triple-rows)]
                  (apply-find-shape query result)))))
          (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
            (with-open [prepared (prepare source query)]
              (if-let [return-map (query-return-map query)]
                (let [result (query-output-with-auto-fns source query prepared rules inputs
                                                         rows-from-result
                                                         column-result-rows
                                                         entity-column-rows
                                                         string-column-rows
                                                         entity-int-pair-rows
                                                         entity-string-pair-rows
                                                         string-int-pair-rows
                                                         string-string-pair-rows
                                                         entity-string-int-triple-rows
                                                         string-string-int-triple-rows)]
                  (keyed-set return-map result))
                (if (= :relation (query-find-shape query))
                  (query-output-with-auto-fns source query prepared rules inputs
                                              q-from-result
                                              column-result-set
                                              entity-column-set
                                              string-column-set
                                              entity-int-pair-set
                                              entity-string-pair-set
                                              string-int-pair-set
                                              string-string-pair-set
                                              entity-string-int-triple-set
                                              string-string-int-triple-set)
                  (let [result (query-output-with-auto-fns source query prepared rules inputs
                                                           rows-from-result
                                                           column-result-rows
                                                           entity-column-rows
                                                           string-column-rows
                                                           entity-int-pair-rows
                                                           entity-string-pair-rows
                                                           string-int-pair-rows
                                                           string-string-pair-rows
                                                           entity-string-int-triple-rows
                                                           string-string-int-triple-rows)]
                    (apply-find-shape query result)))))))))))

(defn query
  "Run a Datomic-style query.

  With one argument, accepts a map shaped like `{:query q :args [db ...]}` and
  returns the same result shape as `q`. With `:query-stats true`, returns a map
  containing `:ret` and `:query-stats`. With `:timeout` in milliseconds,
  throws if the request exceeds the timeout."
  ([request]
   (when-not (map? request)
     (throw (ex-info "expected query request map" {:request request})))
   (let [{query :query args :args} request]
     (when-not query
       (throw (ex-info "query request requires :query" {:request request})))
     (when-not (vector? args)
       (throw (ex-info "query request requires vector :args" {:request request})))
     (let [finish (fn [started result]
                    (let [timeout-ms (:timeout request)
                          elapsed-ms (/ (double (- (System/nanoTime) started)) 1000000.0)]
                      (when (and timeout-ms (> elapsed-ms (double timeout-ms)))
                        (throw (ex-info "query timed out"
                                        {:timeout timeout-ms
                                         :elapsed-ms elapsed-ms})))
                      result))
           run (fn [args]
                 (let [timeout-ms (:timeout request)
                       started (System/nanoTime)
                       ret (apply q query args)
                       result (if (:query-stats request)
                                (let [[source & inputs] args]
                                  (when-not (instance? DB source)
                                    (throw (ex-info "query-stats request requires a DB value as first arg"
                                                    {:source source})))
                                  (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
                                    (with-open [prepared (prepare source query)]
                                      {:ret ret
                                       :query-stats (if rules
                                                      (apply profile-with-rules prepared source rules inputs)
                                                      (apply profile prepared source inputs))})))
                                ret)
                       elapsed-ms (/ (double (- (System/nanoTime) started)) 1000000.0)]
                   (when (and timeout-ms (> elapsed-ms (double timeout-ms)))
                     (throw (ex-info "query timed out"
                                     {:timeout timeout-ms
                                      :elapsed-ms elapsed-ms})))
                   result))
           run-relation-db (fn [rows inputs]
                             (when (:query-stats request)
                               (throw (ex-info "query-stats is not supported for relation DB sources yet"
                                               {:query query})))
                             (let [started (System/nanoTime)
                                   ret (q-relation-db query rows inputs)]
                               (finish started ret)))]
       (if (datom-triple-source? (first args))
         (run-relation-db (first args) (rest args))
         (run args)))))
  ([query source & inputs]
   (apply q query source inputs)))

(defn scalar
  "Run a query expected to return one value."
  [query source & inputs]
  (let [{:keys [query source inputs]} (normalize-query-call query source inputs)]
    (if (instance? PreparedQuery query)
      (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
        (if rules
          (with-open [result (apply query-result-with-rules source query rules inputs)]
            (clj-value (.scalar result)))
          (with-open [result (apply query-result source query inputs)]
            (clj-value (.scalar result)))))
      (let [{rules :rules inputs :inputs} (split-rules-input query (vec inputs))]
        (with-open [prepared (prepare source query)]
          (if rules
            (with-open [result (apply query-result-with-rules source prepared rules inputs)]
              (clj-value (.scalar result)))
            (with-open [result (apply query-result source prepared inputs)]
              (clj-value (.scalar result)))))))))

(defn- with-db-source [source f]
  (cond
    (instance? DB source)
    (f source)

    (instance? Conn source)
    (with-open [snapshot (db source)]
      (f snapshot))

    (instance? DurableConn source)
    (with-open [snapshot (db source)]
      (f snapshot))

    (instance? SQLiteConn source)
    (with-open [snapshot (db source)]
      (f snapshot))

    :else
    (throw (ex-info "expected Vev connection or DB" {:source source}))))

(defn pull
  "Pull one entity or lookup-ref from a DB or connection."
  [source pattern eid]
  (with-db-source
    source
    (fn [db]
      (clj-value
       (cond
         (and (vector? eid)
              (= 2 (count eid))
              (keyword? (first eid)))
         (let [attr-text (edn-text (first eid))
               value (second eid)]
           (cond
             (string? value)
             (if (instance? PreparedPullPattern pattern)
               (.pullLookupRefString (:native db) ^Vev$PreparedPullPattern (:native pattern) attr-text value)
               (.pullLookupRefString (:native db) (edn-text pattern) attr-text value))

             (keyword? value)
             (if (instance? PreparedPullPattern pattern)
               (.pullLookupRefKeyword (:native db) ^Vev$PreparedPullPattern (:native pattern) attr-text (str value))
               (.pullLookupRefKeyword (:native db) (edn-text pattern) attr-text (str value)))

             (instance? java.util.UUID value)
             (if (instance? PreparedPullPattern pattern)
               (.pullLookupRefUuid (:native db) ^Vev$PreparedPullPattern (:native pattern) attr-text value)
               (.pullLookupRefUuid (:native db) (edn-text pattern) attr-text value))

             (integer? value)
             (if (instance? PreparedPullPattern pattern)
               (.pullLookupRefInt (:native db) ^Vev$PreparedPullPattern (:native pattern) attr-text (long value))
               (.pullLookupRefInt (:native db) (edn-text pattern) attr-text (long value)))

             (instance? Vev$Entity value)
             (if (instance? PreparedPullPattern pattern)
               (.pullLookupRefEntity (:native db) ^Vev$PreparedPullPattern (:native pattern) attr-text (.id ^Vev$Entity value))
               (.pullLookupRefEntity (:native db) (edn-text pattern) attr-text (.id ^Vev$Entity value)))

             :else
             (throw (ex-info "unsupported lookup-ref pull value"
                             {:value value
                              :supported #{:string :keyword :uuid :integer :entity}}))))
         (keyword? eid)
         (if (instance? PreparedPullPattern pattern)
           (.pullLookupRefKeyword (:native db) ^Vev$PreparedPullPattern (:native pattern) ":db/ident" (str eid))
           (.pullLookupRefKeyword (:native db) (edn-text pattern) ":db/ident" (str eid)))

         :else
         (if (instance? PreparedPullPattern pattern)
           (.pull (:native db) ^Vev$PreparedPullPattern (:native pattern) (long eid))
           (.pull (:native db) (edn-text pattern) (long eid))))))))

(defn- same-uuid-lookup-refs [eids]
  (when (seq eids)
    (let [attr (ffirst eids)]
      (when (and (keyword? attr)
                 (every? #(and (vector? %)
                               (= 2 (count %))
                               (= attr (first %))
                               (instance? java.util.UUID (second %)))
                         eids))
        {:attr attr
         :values (mapv second eids)}))))

(defn- same-string-lookup-refs [eids]
  (when (seq eids)
    (let [attr (ffirst eids)]
      (when (and (keyword? attr)
                 (every? #(and (vector? %)
                               (= 2 (count %))
                               (= attr (first %))
                               (string? (second %)))
                         eids))
        {:attr attr
         :values (mapv second eids)}))))

(defn pull-many
  "Pull several entities, preserving input order."
  [source pattern eids]
  (if (every? integer? eids)
    (with-db-source
      source
      (fn [db]
        (clj-value
         (if (instance? PreparedPullPattern pattern)
           (.pullMany (:native db)
                      ^Vev$PreparedPullPattern (:native pattern)
                      (long-array eids))
           (.pullMany (:native db)
                      (edn-text pattern)
                      (long-array eids))))))
    (if-let [{:keys [attr values]} (same-string-lookup-refs eids)]
      (with-db-source
        source
        (fn [db]
          (clj-value
           (if (instance? PreparedPullPattern pattern)
             (.pullManyLookupRefString (:native db)
                                       ^Vev$PreparedPullPattern (:native pattern)
                                       (edn-text attr)
                                       (into-array String values))
             (.pullManyLookupRefString (:native db)
                                       (edn-text pattern)
                                       (edn-text attr)
                                       (into-array String values))))))
      (if-let [{:keys [attr values]} (same-uuid-lookup-refs eids)]
        (with-db-source
          source
          (fn [db]
            (clj-value
             (if (instance? PreparedPullPattern pattern)
               (.pullManyLookupRefUuid (:native db)
                                       ^Vev$PreparedPullPattern (:native pattern)
                                       (edn-text attr)
                                       (into-array java.util.UUID values))
               (.pullManyLookupRefUuid (:native db)
                                       (edn-text pattern)
                                       (edn-text attr)
                                       (into-array java.util.UUID values))))))
        (mapv #(pull source pattern %) eids)))))

(defn rows-legacy
  "Deprecated connection-first row helper kept for early examples."
  [source query & inputs]
  (apply rows source query inputs))

(comment
  ;; Early wrapper shape retained by normalize-query-call:
  (with-open [conn (create-conn)]
    (rows conn '[:find ?e :where [?e :name ?name]])))

(defn q-text
  "Run an EDN string query through the rendered text API."
  ([^Conn conn query]
   (q-text conn query []))
  ([^Conn conn query inputs]
   (.queryText (:native conn) query (pr-str inputs))))
