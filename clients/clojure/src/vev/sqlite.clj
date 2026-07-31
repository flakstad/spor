;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(ns vev.sqlite
  "Direct application SQL using the SQLite implementation bundled with VevDB.

  Use a database file separate from the Vev fact store. SQL values are nil,
  integers, floating-point numbers, strings, or byte arrays."
  (:refer-clojure :exclude [open])
  (:import [java.nio.file Path]
           [com.vevdb VevSQLite VevSQLite$Connection VevSQLite$SQLiteException
            VevSQLite$Statement]))

(defrecord DB [^VevSQLite engine ^VevSQLite$Connection native]
  java.lang.AutoCloseable
  (close [_]
    (try
      (.close native)
      (finally
        (.close engine)))))

(defrecord Prepared [^DB db ^VevSQLite$Statement native sql]
  java.lang.AutoCloseable
  (close [_]
    (.close native)))

(defn- path [value]
  (cond
    (instance? Path value) value
    (string? value) (Path/of value (make-array String 0))
    :else (throw (ex-info "expected SQLite database path" {:value value}))))

(defn- sqlite-exception [^VevSQLite$SQLiteException error]
  (ex-info (.getMessage error)
           {:code (.code error)
            :extended-code (.extendedCode error)}
           error))

(defn- open-flags [mode]
  (case mode
    :read-only
    (bit-or VevSQLite/OPEN_READONLY VevSQLite/OPEN_FULLMUTEX)

    :read-write
    (bit-or VevSQLite/OPEN_READWRITE VevSQLite/OPEN_FULLMUTEX)

    :read-write-create
    (bit-or VevSQLite/OPEN_READWRITE
            VevSQLite/OPEN_CREATE
            VevSQLite/OPEN_FULLMUTEX)

    (throw (ex-info "unsupported SQLite open mode"
                    {:mode mode
                     :supported #{:read-only
                                  :read-write
                                  :read-write-create}}))))

(defn- open* [library-path database-path options]
  (let [engine (if library-path
                 (VevSQLite/load (path library-path))
                 (VevSQLite/load))
        mode (:mode options :read-write-create)]
    (try
      (let [native (.open engine
                          (path database-path)
                          (open-flags mode))]
        (try
          (when-let [milliseconds (:busy-timeout-ms options)]
            (let [code (.busyTimeout native (int milliseconds))]
              (when-not (= code VevSQLite/OK)
                (throw
                 (ex-info (.errorMessage native)
                          {:code (.errorCode native)
                           :extended-code (.extendedErrorCode native)
                           :operation :open})))))
          (->DB engine native)
          (catch Throwable error
            (.close native)
            (throw error))))
      (catch VevSQLite$SQLiteException error
        (.close engine)
        (throw (sqlite-exception error)))
      (catch Throwable error
        (.close engine)
        (throw error)))))

(defn open
  "Open an application SQLite database.

  Options support :mode (:read-only, :read-write, or :read-write-create) and
  :busy-timeout-ms. With an explicit library path, use three arguments."
  ([database-path]
   (open* nil database-path {}))
  ([database-or-library-path options-or-database-path]
   (if (map? options-or-database-path)
     (open* nil database-or-library-path options-or-database-path)
     (open* database-or-library-path options-or-database-path {})))
  ([library-path database-path options]
   (open* library-path database-path options)))

(defn version
  "Return the bundled SQLite version."
  ([]
   (with-open [engine (VevSQLite/load)]
     (.version engine)))
  ([library-path]
   (with-open [engine (VevSQLite/load (path library-path))]
     (.version engine))))

(defn source-id
  "Return the bundled SQLite source identifier."
  ([]
   (with-open [engine (VevSQLite/load)]
     (.sourceId engine)))
  ([library-path]
   (with-open [engine (VevSQLite/load (path library-path))]
     (.sourceId engine))))

(defn compile-option-used?
  "Return true when the bundled SQLite was built with option."
  ([option]
   (with-open [engine (VevSQLite/load)]
     (.compileOptionUsed engine (str option))))
  ([library-path option]
   (with-open [engine (VevSQLite/load (path library-path))]
     (.compileOptionUsed engine (str option)))))

(defn- throw-db-error [^DB db operation sql]
  (let [native (:native db)]
    (throw (ex-info (.errorMessage native)
                    {:code (.errorCode native)
                     :extended-code (.extendedErrorCode native)
                     :operation operation
                     :sql sql}))))

(defn- require-code [^DB db code expected operation sql]
  (when-not (= expected code)
    (throw-db-error db operation sql))
  code)

(defn busy-timeout!
  "Set how long this connection waits for a conflicting SQLite writer."
  [^DB db milliseconds]
  (require-code db
                (.busyTimeout (:native db) (int milliseconds))
                VevSQLite/OK
                :busy-timeout
                nil)
  db)

(defn interrupt!
  "Interrupt work currently running on this connection."
  [^DB db]
  (.interrupt (:native db))
  nil)

(defn execute-script!
  "Execute one or more SQL statements without parameters.

  Returns {:changes n}, where n is SQLite's change count for the final
  statement. Include explicit BEGIN/COMMIT when the whole script must be
  atomic."
  [^DB db sql]
  (let [sql (str sql)]
    (require-code db
                  (.exec (:native db) sql)
                  VevSQLite/OK
                  :execute-script
                  sql)
    {:changes (.changes (:native db))}))

(defn prepare
  "Prepare one reusable SQL statement.

  Close the statement before closing its DB. A prepared statement may be
  passed to execute!, query, query-one, scalar, reduce-rows, or
  execute-batch!."
  [^DB db sql]
  (let [sql (str sql)]
    (try
      (->Prepared db (.prepare (:native db) sql) sql)
      (catch VevSQLite$SQLiteException error
        (throw
         (ex-info (.getMessage error)
                  {:code (.code error)
                   :extended-code (.extendedCode error)
                   :operation :prepare
                   :sql sql}
                  error))))))

(defn- named-parameter-value [params parameter-name]
  (when (empty? parameter-name)
    (throw (ex-info "named parameters require named SQL placeholders"
                    {:parameter parameter-name})))
  (let [plain-name (subs parameter-name 1)
        candidates [parameter-name plain-name (keyword plain-name)]]
    (if-let [key (some #(when (contains? params %) %) candidates)]
      (get params key)
      (throw (ex-info "missing named SQL parameter"
                      {:parameter parameter-name})))))

(defn- bind-params! [^Prepared prepared params operation]
  (let [db (:db prepared)
        statement (:native prepared)
        sql (:sql prepared)
        expected (.parameterCount statement)]
    ;; sqlite3_reset reports the previous step's error. Its reset side effect
    ;; still occurred, so only clear_bindings is checked here.
    (.reset statement)
    (require-code db
                  (.clearBindings statement)
                  VevSQLite/OK
                  operation
                  sql)
    (cond
      (map? params)
      (doseq [index (range 1 (inc expected))]
        (let [parameter-name (.parameterName statement index)
              value (named-parameter-value params parameter-name)
              code (.bind statement index value)]
          (when-not (= code VevSQLite/OK)
            (throw-db-error db operation sql))))

      (sequential? params)
      (let [params (vec params)]
        (when-not (= expected (count params))
          (throw (ex-info "SQL parameter count does not match values"
                          {:expected expected
                           :actual (count params)
                           :operation operation
                           :sql sql})))
        (doseq [[offset value] (map-indexed vector params)]
          (let [code (.bind statement (inc offset) value)]
            (when-not (= code VevSQLite/OK)
              (throw-db-error db operation sql)))))

      :else
      (throw (ex-info "SQL parameters must be a sequential collection or map"
                      {:params-type (type params)
                       :operation operation
                       :sql sql})))))

(defn- execute-prepared! [^Prepared prepared params]
  (let [db (:db prepared)
        statement (:native prepared)
        sql (:sql prepared)]
    (bind-params! prepared params :execute)
    (when (pos? (.columnCount statement))
      (throw (ex-info "execute! cannot discard rows; use query or query-one"
                      {:operation :execute :sql sql})))
    (let [code (.step statement)]
      (if (= code VevSQLite/DONE)
        {:changes (.changes (:native db))}
        (throw-db-error db :execute sql)))))

(defn execute!
  "Execute one prepared SQL statement.

  Parameters may be nil, integers, floating-point numbers, strings, or byte
  arrays. Named placeholders accept a map. Returns {:changes n}. SQL that
  returns rows must use query or query-one."
  ([prepared]
   (if (instance? Prepared prepared)
     (execute-prepared! prepared [])
     (throw (ex-info "one-argument execute! expects a prepared statement"
                     {:value prepared}))))
  ([target sql-or-params]
   (if (instance? Prepared target)
     (execute-prepared! target sql-or-params)
     (with-open [prepared (prepare target sql-or-params)]
       (execute-prepared! prepared []))))
  ([^DB db sql params]
   (with-open [prepared (prepare db sql)]
     (execute-prepared! prepared params))))

(defn- query-columns [^Prepared prepared]
  (let [statement (:native prepared)
        column-count (.columnCount statement)]
    (mapv #(.columnName statement %) (range column-count))))

(defn- current-row [^Prepared prepared]
  (let [statement (:native prepared)
        column-count (.columnCount statement)]
    (mapv #(.columnValue statement %) (range column-count))))

(defn- reduce-prepared-rows [^Prepared prepared params rf initial]
  (let [db (:db prepared)
        statement (:native prepared)
        sql (:sql prepared)]
    (bind-params! prepared params :query)
    (loop [acc initial]
      (let [code (.step statement)]
        (cond
          (= code VevSQLite/ROW)
          (let [next-acc (rf acc (current-row prepared))]
            (if (reduced? next-acc)
              @next-acc
              (recur next-acc)))

          (= code VevSQLite/DONE)
          acc

          :else
          (throw-db-error db :query sql))))))

(defn reduce-rows
  "Reduce query rows without retaining the complete result.

  Intended for row-returning reads. Each row is a copied value vector."
  ([prepared params rf initial]
   (if (instance? Prepared prepared)
     (reduce-prepared-rows prepared params rf initial)
     (throw (ex-info "four-argument reduce-rows expects a prepared statement"
                     {:value prepared}))))
  ([db sql params rf initial]
   (with-open [prepared (prepare db sql)]
     (reduce-prepared-rows prepared params rf initial))))

(defn- query-prepared [^Prepared prepared params]
  {:columns (query-columns prepared)
   :rows (reduce-prepared-rows prepared params conj [])})

(defn query
  "Execute a query and copy its result.

  Returns {:columns [name ...] :rows [[value ...] ...]}. Values are nil,
  longs, doubles, strings, or byte arrays."
  ([prepared]
   (if (instance? Prepared prepared)
     (query-prepared prepared [])
     (throw (ex-info "one-argument query expects a prepared statement"
                     {:value prepared}))))
  ([target sql-or-params]
   (if (instance? Prepared target)
     (query-prepared target sql-or-params)
     (with-open [prepared (prepare target sql-or-params)]
       (query-prepared prepared []))))
  ([^DB db sql params]
   (with-open [prepared (prepare db sql)]
     (query-prepared prepared params))))

(defn- finish-write-returning! [^Prepared prepared]
  (let [db (:db prepared)
        statement (:native prepared)
        sql (:sql prepared)]
    (loop [code (.step statement)]
      (cond
        (= code VevSQLite/ROW) (recur (.step statement))
        (= code VevSQLite/DONE) nil
        :else (throw-db-error db :query sql)))))

(defn- query-one-prepared [^Prepared prepared params]
  (let [db (:db prepared)
        statement (:native prepared)
        sql (:sql prepared)]
    (bind-params! prepared params :query)
    (let [code (.step statement)]
      (cond
        (= code VevSQLite/ROW)
        (let [row (current-row prepared)]
          (when-not (.readonly statement)
            (finish-write-returning! prepared))
          row)

        (= code VevSQLite/DONE)
        nil

        :else
        (throw-db-error db :query sql)))))

(defn query-one
  "Return the first row vector, or nil, without retaining later rows.

  Read statements stop after the first row. Row-returning writes continue to
  completion but discard any later rows."
  ([prepared]
   (if (instance? Prepared prepared)
     (query-one-prepared prepared [])
     (throw (ex-info "one-argument query-one expects a prepared statement"
                     {:value prepared}))))
  ([target sql-or-params]
   (if (instance? Prepared target)
     (query-one-prepared target sql-or-params)
     (with-open [prepared (prepare target sql-or-params)]
       (query-one-prepared prepared []))))
  ([db sql params]
   (with-open [prepared (prepare db sql)]
     (query-one-prepared prepared params))))

(defn scalar
  "Return the first column of the first row, or nil."
  ([prepared]
   (first (query-one prepared)))
  ([target sql-or-params]
   (first (query-one target sql-or-params)))
  ([db sql params]
   (first (query-one db sql params))))

(defn execute-batch!
  "Execute one non-row statement for every parameter group using one prepared
  statement. Returns the sum of per-execution changes.

  The batch does not create a transaction; wrap it in with-transaction when
  atomicity is required."
  ([^Prepared prepared parameter-groups]
   (reduce
    (fn [result params]
      (update result :changes + (:changes (execute-prepared! prepared params))))
    {:changes 0}
    parameter-groups))
  ([db sql parameter-groups]
   (with-open [prepared (prepare db sql)]
     (execute-batch! prepared parameter-groups))))

(defn changes
  "Return rows changed by the most recent statement."
  [^DB db]
  (.changes (:native db)))

(defn total-changes
  "Return rows changed over this connection's lifetime."
  [^DB db]
  (.totalChanges (:native db)))

(defn last-insert-rowid
  "Return the most recent inserted rowid on this connection."
  [^DB db]
  (.lastInsertRowid (:native db)))

(defn autocommit?
  "Return false while an explicit transaction is active."
  [^DB db]
  (.autocommit (:native db)))

(defn begin!
  [db]
  (execute! db "BEGIN"))

(defn begin-immediate!
  [db]
  (execute! db "BEGIN IMMEDIATE"))

(defn commit!
  [db]
  (execute! db "COMMIT"))

(defn rollback!
  [db]
  (execute! db "ROLLBACK"))

(defn transact
  "Run f with db in an immediate transaction, committing its result.

  Options support :mode :immediate (the default) or :deferred. Nested
  transactions are rejected. Rolls back and rethrows if f fails."
  ([db f]
   (transact db {} f))
  ([db options f]
   (when-not (autocommit? db)
     (throw (ex-info "nested SQLite transactions are not supported"
                     {:operation :transaction})))
   (case (:mode options :immediate)
     :immediate (begin-immediate! db)
     :deferred (begin! db)
     (throw (ex-info "unsupported SQLite transaction mode"
                     {:mode (:mode options)
                      :supported #{:immediate :deferred}})))
   (try
     (let [value (f db)]
       (commit! db)
       value)
     (catch Throwable error
       (when-not (autocommit? db)
         (rollback! db))
       (throw error)))))

(defmacro with-transaction
  "Bind a transaction connection, commit body on success, and roll back on
  failure.

  (with-transaction [tx db] ...)
  (with-transaction [tx db {:mode :deferred}] ...)"
  [[binding db & [options]] & body]
  (if options
    `(transact ~db ~options (fn [~binding] ~@body))
    `(transact ~db (fn [~binding] ~@body))))
