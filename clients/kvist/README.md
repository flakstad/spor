# VevDB for Kvist

**Status: built in.**

This package preserves Kvist's `Data`-oriented Vev API while loading the
prebuilt Vev native engine through its stable C ABI. Importing it does not
compile Vev's implementation into the application.

Unpack the platform bundle under `vendor/vev` and import its `kvist` package:

```clojure
(import d "deps:vev/kvist")

(let [conn (d.connect "example.db")
      db (d.db conn)
      names (d.q '[:find ?name :where [?e :person/name ?name]] db)]
  ...)
```

Replace `example.db` with the path you want.

For a long-lived local process that prioritizes predictable latency over the
smallest memory footprint, select resident execution once after connecting:

```clojure
(let [conn (d.connect "example.db")]
  (when (not (d.ensure-resident! conn))
    (panic "could not load resident Vev state"))
  ...)
```

`db`, queries, and transaction planning then use immutable in-memory indexes
owned by that connection. Successful transactions remain ordinary durable Vev
transactions and survive closing and reopening the file.

`transact` always returns the ordinary rich Vev report. Its immutable
`db-before` and `db-after` values are cheap retained snapshot handles, not
eager copies of the database.

Create a consistent durable backup without copying SQLite/WAL files directly:

```clojure
(let [[basis ok error] (d.backup conn "backup.vev")]
  ...)
```

The destination must be new. `basis` identifies exactly the committed Vev
generation in the independently openable result.

Inspect durable coordinates without opening a Vev connection:

```clojure
(let [[head head-ok head-error] (d.storage-head-basis-t "example.db")
      [indexed indexed-ok indexed-error]
        (d.storage-indexed-basis-t "example.db")]
  ...)
```

`storage-head-basis-t` is the latest fully committed transaction and is the
coordinate exposed by the current DB after reopen. `storage-indexed-basis-t`
is the latest durable index-root coordinate and may lag behind head while
maintenance is deferred. `persisted-basis-t` remains a compatibility alias for
`storage-indexed-basis-t`.

General SQLite access is a separate package in the same bundle:

```clojure
(import sql "deps:vev/kvist/sqlite")

(let [email (sql.open "email.sqlite")
      rows (sql.query email "select id, subject from email")]
  (defer (sql.delete-query-result rows))
  (defer (sql.close email))
  ...)
```

It opens application-owned SQLite files using the SQLite already contained in
VevDB. It does not expose the VevDB store connection.

The usual shape is `execute-script` for schema setup, `execute` for mutations,
and `query`, `query-one`, or `scalar` for returned data. Positional and named
parameters, reusable prepared statements, batches, read-only connections, busy
timeouts, and row visitors are supported. Kvist values and results have
explicit ownership; see the SQLite guide for the complete contract.

Build with `-collection:deps=vendor`. The facade finds `libvev` from `VEV_LIB`
for explicit development/test overrides, beside the executable for command-line
applications, or under `Contents/Frameworks` in a macOS application bundle.

Transactions and queries accept ordinary local Kvist `Data`; canonical EDN
inputs and opaque native handles cross into the library. Canonical query text
is prepared once per connection. Typed query and transaction-report Value
trees are traversed into fresh local `Data` values without rendering result or
report EDN. The EDN report API remains available at the C compatibility layer.

`transact` and `with` return native `Tx-Report` structs with explicit database,
transaction-data, tempid, metadata, and Vev error fields. Reports own their DB
snapshots and local data, so close them when done:

```clojure
(let [report (d.transact conn [{:db/id "ada" :person/name "Ada"}])]
  (defer (d.close (addr report)))
  (when (not report.ok)
    (panic report.error))
  (let [[entity resolved?]
        (d.resolve-tempid report.db-after report.tempids "ada")]
    ...))
```

Kvist and Clojure are VevDB's paired primary APIs. Kvist provides the same core
database operations—including `as-of`, `since`, history inspection, datom index
reads, entity and lookup-ref resolution, pull, `db-with`, transaction reports,
and synchronized snapshots—with Kvist-native ownership and result types.

See [Datomic and VevDB](../../docs/datomic-syntax.md) for the shared data model,
tutorial adaptations, supported Peer operations, and deliberate non-goals.
See [SQLite](../../docs/sqlite.md) for SQL values, ownership, transactions, and
the C ABI.
