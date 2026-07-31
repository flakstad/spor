;; Copyright (c) Andreas Flakstad and Vev contributors
;; SPDX-License-Identifier: EPL-2.0

(require '[clojure.edn :as edn])
(require '[vev.sqlite :as sql])

(import '[java.nio.charset StandardCharsets])
(import '[java.util Arrays])

(defn check [condition message]
  (when-not condition
    (throw (ex-info message {}))))

(defn seed-schema! [db]
  (sql/execute-script!
   db
   "pragma foreign_keys=on;
    pragma journal_mode=wal;
    create table cache_entries(
      cache_key text primary key,
      value blob not null,
      encoding text not null,
      expires_at integer,
      updated_at integer not null
    );
    create index cache_expiry on cache_entries(expires_at);
    create table jobs(
      id integer primary key,
      queue text not null,
      payload text not null,
      priority integer not null default 0,
      available_at integer not null,
      attempts integer not null default 0,
      locked_by text,
      locked_at integer,
      unique_key text unique
    );
    create index jobs_ready
      on jobs(queue,available_at,priority desc,id);
    create table mailboxes(
      id integer primary key,
      address text not null unique
    );
    create table emails(
      id integer primary key,
      mailbox_id integer not null references mailboxes(id),
      message_id text not null unique,
      subject text not null,
      body text not null,
      raw_message blob not null,
      received_at integer not null
    );
    create virtual table email_search using
      fts5(subject,body,content='emails',content_rowid='id');
    create table outbox(
      id integer primary key,
      email_id integer not null references emails(id),
      state text not null,
      attempts integer not null default 0
    );"))

(defn test-cache! [db]
  (let [put-sql
        "insert into cache_entries(
           cache_key,value,encoding,expires_at,updated_at
         ) values(?,?,?,?,?)
         on conflict(cache_key) do update set
           value=excluded.value,
           encoding=excluded.encoding,
           expires_at=excluded.expires_at,
           updated_at=excluded.updated_at"
        edn-value {:answer 42 :tags #{:cached :edn}}
        binary-value (byte-array [0 -1 7 0 9])]
    (with-open [put (sql/prepare db put-sql)]
      (check
       (= {:changes 6}
          (sql/execute-batch!
           put
           [["session:1" "opaque-session-token" "text" 2000 1000]
            ["result:edn" (pr-str edn-value) "edn" nil 1001]
            ["plain:string" "just a string" "text" 900 1002]
            ["result:binary" binary-value "bytes" nil 1003]
            ["empty:text" "" "text" nil 1004]
            ["empty:bytes" (byte-array 0) "bytes" nil 1005]]))
       "prepared cache batch returned the wrong change count"))
    (check
     (= 1 (:changes
           (sql/execute!
            db
            "delete from cache_entries
             where expires_at is not null and expires_at <= ?"
            [1000])))
     "cache TTL eviction changed the wrong number of rows")
    (let [{:keys [columns rows]}
          (sql/query
           db
           "select cache_key,value,encoding
            from cache_entries order by cache_key")
          by-key (into {} (map (juxt first identity) rows))]
      (check (= ["cache_key" "value" "encoding"] columns)
             "cache columns changed")
      (check (= 5 (count rows)) "cache row count changed")
      (check (= "opaque-session-token" (get-in by-key ["session:1" 1]))
             "plain cache string did not round-trip")
      (check (= edn-value
                (edn/read-string (get-in by-key ["result:edn" 1])))
             "cached EDN did not round-trip")
      (check (Arrays/equals
              binary-value
              ^bytes (get-in by-key ["result:binary" 1]))
             "cached binary result did not round-trip")
      (check (= "" (get-in by-key ["empty:text" 1]))
             "empty cache text did not round-trip")
      (check (Arrays/equals
              (byte-array 0)
              ^bytes (get-in by-key ["empty:bytes" 1]))
             "empty cache bytes did not round-trip"))
    (check (= 5
              (sql/scalar db "select count(*) from cache_entries"))
           "cache scalar returned the wrong value")
    (check (= ["session:1" "text"]
              (sql/query-one
               db
               "select cache_key,encoding
                from cache_entries where cache_key=:key"
               {:key "session:1"}))
           "named parameters or single-row query changed")
    (check (= [1]
              (sql/query-one
               db
               "with numbers(value) as (
                  values(1),(-9223372036854775808)
                )
                select abs(value) from numbers"))
           "query-one evaluated rows after the first read row")
    (let [[cache-key]
          (sql/query-one
           db
           "update cache_entries
            set updated_at=updated_at+1
            returning cache_key")]
      (check (string? cache-key)
             "row-returning write did not return its first row")
      (check (= 5 (sql/changes db))
             "query-one did not complete a multi-row returning write"))
    (check (= ["empty:bytes" "empty:text" "result:binary"
               "result:edn" "session:1"]
              (sql/reduce-rows
               db
               "select cache_key from cache_entries order by cache_key"
               []
               (fn [keys [key]] (conj keys key))
               []))
           "streaming row reduction changed")
    (let [failure
          (try
            (sql/with-transaction [tx db]
              (sql/execute!
               tx put-sql
               ["rolled-back" "never visible" "text" nil 2000])
              (throw (ex-info "force rollback" {})))
            nil
            (catch clojure.lang.ExceptionInfo error
              (.getMessage error)))]
      (check (= "force rollback" failure)
             "cache rollback did not preserve the original failure")
      (check (sql/autocommit? db)
             "cache rollback did not restore autocommit")
      (check (= []
                (:rows
                 (sql/query
                  db
                  "select cache_key from cache_entries where cache_key=?"
                  ["rolled-back"])))
             "failed cache transaction was committed"))
    (let [mismatch
          (try
            (sql/query db "select ?" [])
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= {:expected 1 :actual 0}
                (select-keys mismatch [:expected :actual]))
             "parameter-count error lost its details"))
    (let [missing
          (try
            (sql/query db "select :required" {:other 1})
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= ":required" (:parameter missing))
             "missing named parameter lost its name"))
    (let [before (sql/scalar db "select count(*) from cache_entries")
          rejected
          (try
            (sql/execute!
             db
             "insert into cache_entries(
                cache_key,value,encoding,expires_at,updated_at
              ) values('must-not-run','x','text',null,0)
              returning cache_key")
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= :execute (:operation rejected))
             "execute! did not reject a row-returning statement")
      (check (= before
                (sql/scalar db "select count(*) from cache_entries"))
             "rejected row-returning execute! changed the database"))
    (let [nested
          (try
            (sql/with-transaction [outer db]
              (sql/with-transaction [inner outer]
                (sql/execute! inner "select 1")))
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= :transaction (:operation nested))
             "nested transaction was not rejected")
      (check (sql/autocommit? db)
             "nested transaction rejection did not roll back"))))

(defn test-queue! [db]
  (sql/execute-script!
   db
   "insert into jobs(queue,payload,priority,available_at,unique_key) values
      ('mail','{:email/id 1}',5,100,'send-1'),
      ('mail','plain payload',10,100,'send-2'),
      ('mail','later',100,500,'send-3');")
  (let [claimed
        (sql/with-transaction [tx db]
          (sql/query-one
           tx
           "update jobs set
              locked_by=:worker,
              locked_at=:now,
              attempts=attempts+1
            where id=(
              select id from jobs
              where queue=:queue
                and available_at<=:now
                and locked_by is null
              order by priority desc,id limit 1
            )
            returning id,payload,attempts"
           {:worker "worker-clojure" :now 101 :queue "mail"}))]
    (check (= [2 "plain payload" 1] claimed)
           "queue did not atomically claim the highest-priority ready job")
    (check (= 1 (:changes
                 (sql/execute!
                  db
                  "delete from jobs where id=? and locked_by=?"
                  [(first claimed) "worker-clojure"])))
           "queue acknowledgement changed the wrong number of rows"))
  (sql/execute!
   db
   "update jobs
    set locked_by=null,locked_at=null,available_at=200
    where id=?"
   [1]))

(defn test-email! [db]
  (let [raw-message
        (.getBytes
         "From: sender@example.com\r\nTo: ada@example.com\r\n\r\nBody\u0000tail"
         StandardCharsets/UTF_8)]
    (sql/with-transaction [tx db {:mode :deferred}]
      (sql/execute!
       tx "insert into mailboxes(address) values(?)"
       ["ada@example.com"])
      (sql/execute!
       tx
       "insert into emails(
           mailbox_id,message_id,subject,body,raw_message,received_at
         ) values(?,?,?,?,?,?)"
       [1 "<message-1@example.com>" "Quarterly cache report"
        "Queue processing completed" raw-message 1234567890])
      (sql/execute-script!
       tx
       "insert into email_search(rowid,subject,body)
          select id,subject,body from emails where id=1;
        insert into outbox(email_id,state) values(1,'pending');"))
    (let [{:keys [columns rows]}
          (sql/query
           db
           "select e.message_id,m.address,e.raw_message,o.state
            from email_search s
            join emails e on e.id=s.rowid
            join mailboxes m on m.id=e.mailbox_id
            join outbox o on o.email_id=e.id
            where email_search match ?"
           ["queue"])]
      (check (= ["message_id" "address" "raw_message" "state"] columns)
             "email query columns changed")
      (check (= 1 (count rows)) "email FTS search returned wrong row count")
      (check (= "<message-1@example.com>" (get-in rows [0 0]))
             "email message id did not round-trip")
      (check (= "ada@example.com" (get-in rows [0 1]))
             "email join returned wrong mailbox")
      (check (Arrays/equals raw-message ^bytes (get-in rows [0 2]))
             "raw MIME bytes did not round-trip")
      (check (= "pending" (get-in rows [0 3]))
             "outbox state did not round-trip"))
    (let [failure
          (try
            (sql/execute!
             db
             "insert into outbox(email_id,state) values(999,'pending')")
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= 19 (:code failure))
             "email foreign-key violation returned the wrong code"))))

(defn claim-ready-job! [db worker]
  (sql/with-transaction [tx db]
    (when-let [[id]
               (sql/query-one
                tx
                "update jobs set
                      locked_by=?,locked_at=?,attempts=attempts+1
                    where id=(
                      select id from jobs
                      where queue='concurrent'
                        and available_at<=1000
                        and locked_by is null
                      order by priority desc,id limit 1
                    )
                    returning id"
                [worker 1000])]
      (sql/execute!
       tx "delete from jobs where id=? and locked_by=?" [id worker])
      id)))

(defn test-concurrent-queue! [library-path database-path]
  (with-open [seed (sql/open library-path database-path)]
    (sql/execute-batch!
     seed
     "insert into jobs(
          queue,payload,priority,available_at,unique_key
        ) values('concurrent',?,?,100,?)"
     (for [id (range 1 25)]
       [(str "job-" id) (mod id 4) (str "concurrent-" id)])))
  (let [workers
        (doall
         (for [worker-index (range 4)]
           (future
             (with-open [db (sql/open library-path
                                      database-path
                                      {:busy-timeout-ms 5000})]
               (loop [claimed []]
                 (if-let [id
                          (claim-ready-job!
                           db
                           (str "worker-" worker-index))]
                   (recur (conj claimed id))
                   claimed))))))
        claimed (vec (mapcat deref workers))]
    (check (= 24 (count claimed))
           "concurrent queue workers did not claim every job")
    (check (= 24 (count (set claimed)))
           "concurrent queue workers claimed a job more than once")
    (with-open [db (sql/open library-path database-path)]
      (check (= [[0]]
                (:rows
                 (sql/query
                  db "select count(*) from jobs where queue='concurrent'")))
             "concurrent queue acknowledgement left jobs behind"))))

(defn test-interrupt! [library-path]
  (with-open [db (sql/open library-path ":memory:")]
    (let [started (promise)
          running
          (future
            (deliver started true)
            (try
              (sql/query
               db
               "with recursive counter(value) as (
                  values(0)
                  union all
                  select value+1 from counter where value<1000000000
                )
                select sum(value) from counter")
              {:completed true}
              (catch clojure.lang.ExceptionInfo error
                (ex-data error))))]
      @started
      (Thread/sleep 25)
      (sql/interrupt! db)
      (let [outcome (deref running 5000 ::timeout)]
        (check (not= ::timeout outcome) "interrupted query did not stop")
        (check (= 9 (:code outcome))
               "interrupted query returned the wrong result code")))))

(let [[library-path database-path] *command-line-args*]
  (when-not (and library-path database-path)
    (throw
     (ex-info
      "usage: sqlite_applications.clj <libvev-path> <database-path>"
      {})))
  (with-open [db (sql/open library-path
                           database-path
                           {:busy-timeout-ms 1000})]
    (seed-schema! db)
    (test-cache! db)
    (test-queue! db)
    (test-email! db))
  (with-open [read-only (sql/open library-path
                                  database-path
                                  {:mode :read-only})]
    (check (pos? (sql/scalar read-only
                             "select count(*) from cache_entries"))
           "read-only connection could not query")
    (let [failure
          (try
            (sql/execute!
             read-only
             "insert into cache_entries(
                cache_key,value,encoding,expires_at,updated_at
              ) values('read-only','x','text',null,0)")
            nil
            (catch clojure.lang.ExceptionInfo error
              (ex-data error)))]
      (check (= 8 (:code failure))
             "read-only connection accepted a write")))
  (test-concurrent-queue! library-path database-path)
  (test-interrupt! library-path)
  (shutdown-agents)
  (println ":vev-sqlite-applications-clojure-ok"))
