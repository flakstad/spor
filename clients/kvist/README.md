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

Build with `-collection:deps=vendor`. The facade finds `libvev` from `VEV_LIB`
for explicit development/test overrides, beside the executable for command-line
applications, or under `Contents/Frameworks` in a macOS application bundle.

Transactions and queries accept ordinary local Kvist `Data`; only canonical EDN
inputs and opaque native handles cross the library boundary. Canonical query
text is prepared once per connection, and typed result trees are traversed into
fresh local `Data` values without rendering result EDN.

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
