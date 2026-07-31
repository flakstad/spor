# Direct SQLite

VevDB is an immutable fact database. Applications may also need ordinary SQL
storage for data that does not belong in fact history, such as sessions,
caches, jobs, email, or search indexes.

VevDB already bundles SQLite. The direct SQLite API lets applications use that
same SQLite build instead of shipping another native library or requiring a
system SQLite installation.

Use a separate database file:

```text
application.vev       VevDB facts
application.sqlite    application SQL tables
```

The API does not expose VevDB's internal connection or schema. Do not use it to
open a VevDB store. Transactions cannot span a VevDB store and an application
SQLite database.

## Clojure

Require `vev.sqlite` separately from `vev.core`:

```clojure
(require '[vev.sqlite :as sql])

(def db (sql/open "application.sqlite"))

(sql/execute-script!
 db
 "create table if not exists items(
    item_key text primary key,
    value blob not null
  )")

(sql/execute!
 db
 "insert into items(item_key,value) values(?,?)
  on conflict(item_key) do update set value=excluded.value"
 ["example" "some serialized value"])

(sql/query db "select item_key,value from items")
;; => {:columns ["item_key" "value"]
;;     :rows [["example" "some serialized value"]]}
```

SQL values are `nil`, integers, floating-point numbers, strings, and byte
arrays. Strings may contain plain text, EDN, JSON, or any other serialization.

The main operations are:

- `execute-script!` runs one or more statements without parameters.
- `execute!` runs one mutation and returns `{:changes n}`.
- `query` returns ordered columns and row vectors.
- `query-one` returns one row vector or `nil`.
- `scalar` returns the first value of the first row or `nil`.
- `prepare` creates a reusable statement.
- `execute-batch!` executes many parameter groups.
- `reduce-rows` processes rows without retaining the complete result.

Positional `?` parameters take a vector. Named parameters take a map:

```clojure
(sql/query-one
 db
 "select item_key,value from items where item_key=:key"
 {:key "example"})
```

Use `with-transaction` for a transaction scope:

```clojure
(sql/with-transaction [tx db]
  (sql/execute! tx "delete from items where item_key=?" ["example"]))
```

Transactions are immediate by default. Add `{:mode :deferred}` to request a
deferred transaction.

`open` accepts `:mode` (`:read-write-create`, `:read-write`, or `:read-only`)
and `:busy-timeout-ms`.

`query` materializes its complete result. `query-one` stops after the first
row of a read. For a write using `RETURNING`, it completes the write but keeps
only the first returned row. Use `reduce-rows` for larger reads.

## Kvist

Import the SQLite package separately from the VevDB package:

```clojure
(import sql "deps:vev/kvist/sqlite")

(let [db (sql.open "application.sqlite")
      rows (sql.query db "select item_key,value from items")]
  (defer (sql.delete-query-result rows))
  (defer (sql.close db))
  ...)
```

Kvist provides the corresponding `execute-script`, `execute`, `query`,
`query-one`, `scalar`, `prepare`, `execute-batch`, and `visit-rows`
operations.

Values are explicit: `sql.null`, `sql.integer`, `sql.floating`, `sql.text`,
and `sql.blob`. Positional and named parameters are supported.

Kvist results own their strings, blobs, columns, and rows. Release them with
`delete-result`, `delete-query-result`, or `delete-scalar-result`.
`visit-rows` processes rows without retaining the complete result.

`Open-Options` supports `Read-Write-Create`, `Read-Write`, `Read-Only`, and a
busy timeout. Transactions use `begin!`, `begin-immediate!`, `commit!`, and
`rollback!`.

## C, Odin, and Java

The same functionality is available through:

- the `vev_sqlite_*` C API in `vev_sqlite.h`
- the typed `sqlite_*` functions in the Odin `vev` package
- the Java `VevSQLite` class

These are lower-level connection and prepared-statement APIs. The Clojure and
Kvist APIs build their result and convenience operations on top of them.

SQLite is compiled into `libvev`. VevDB does not export raw `sqlite3_*`
symbols or depend on a system SQLite library. Release builds include FTS5 and
disable dynamic extension loading.
