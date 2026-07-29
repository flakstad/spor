# Datomic and VevDB

VevDB follows Datomic's data model where it fits an embedded database. Datoms,
transactions, immutable database values, Datalog queries, pull, entities,
indexes, and history use the same core ideas.

Datomic is a semantic reference and tutorial corpus for VevDB. It is not an
architectural specification. VevDB runs inside the application, stores durable
databases in local files, and has no transactor, Peer protocol, or database
catalog.

The practical goal is simple: a Datomic tutorial about data should also teach
you how to use VevDB.

## Following a Datomic tutorial

Most Clojure tutorial code needs three changes:

```diff
- (require '[datomic.api :as d])
+ (require '[vev.core :as d])

- (d/create-database uri)
- (def conn (d/connect uri))
+ (def conn (d/connect "tutorial.vev"))

- (def report @(d/transact conn tx))
+ (def report  (d/transact conn tx))
```

VevDB creates or opens the local store in `connect`. `transact` and `sync`
return completed values directly, so there is no future to dereference.

The schema, transaction data, query, pull pattern, lookup ref, and immutable DB
operations can usually remain unchanged.

## The same example

Here is ordinary VevDB Clojure:

```clojure
(require '[vev.core :as d])

(def conn (d/connect "people.vev"))

(def schema
  [{:db/id "person/email"
    :db/ident :person/email
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/id "person/name"
    :db/ident :person/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}])

(d/transact conn schema)

(def report
  (d/transact conn
    [{:db/id "ada"
      :person/email "ada@example.com"
      :person/name "Ada Lovelace"}]))

(def db (d/db conn))

(d/q
  '[:find ?name .
    :in $ ?email
    :where
    [?e :person/email ?email]
    [?e :person/name ?name]]
  db
  "ada@example.com")
;; => "Ada Lovelace"

(d/pull db
  [:person/email :person/name]
  [:person/email "ada@example.com"])

(def ada
  (d/entity db [:person/email "ada@example.com"]))

(:person/name ada)
;; => "Ada Lovelace"

(d/datoms db :avet :person/email "ada@example.com")

(def old-db
  (d/as-of db (d/basis-t (:db-before report))))
```

The Datomic version uses the same schema, transaction, query, pull, entity,
index, and `as-of` forms. It changes the namespace and connection setup and
dereferences the value returned by `transact`.

`conn`, `db`, and `ada` may be normal long-lived REPL definitions. They wrap
native resources in VevDB, so close them when their application lifetime ends:

```clojure
(.close ada)
(.close old-db)
(.close db)
(.close conn)
```

Use `with-open` for a short, bounded operation when that is more convenient. It
is not required by the data model.

## The same model in Kvist

Clojure and Kvist are VevDB's primary APIs. Kvist uses the same transaction
data, query data, lookup refs, and immutable DB operations:

```clojure
(package people)

(import d "deps:vev/kvist")
(import data "kvist:data")

(defn main []
  (let [conn (d.connect "people.vev")]
    (defer (d.close conn))

    (let [schema-report
          (d.transact
            conn
            [{:db/id "person/email"
              :db/ident :person/email
              :db/valueType :db.type/string
              :db/cardinality :db.cardinality/one
              :db/unique :db.unique/identity}
             {:db/id "person/name"
              :db/ident :person/name
              :db/valueType :db.type/string
              :db/cardinality :db.cardinality/one}])]
      (defer (d.close (addr schema-report)))
      (when (not schema-report.ok)
        (panic schema-report.error)))

    (let [report
          (d.transact
            conn
            [{:db/id "ada"
              :person/email "ada@example.com"
              :person/name "Ada Lovelace"}])]
      (defer (d.close (addr report)))
      (when (not report.ok)
        (panic report.error)))

    (let [db (d.db conn)]
      (defer (d.close db))

      (let [name
            (d.q
              '[:find ?name .
                :in $ ?email
                :where
                [?e :person/email ?email]
                [?e :person/name ?name]]
              db
              "ada@example.com")]
        (defer (data.release name)))

      (let [person
            (d.pull
              db
              '[:person/email :person/name]
              [:person/email "ada@example.com"])]
        (defer (data.release person))))))
```

Kvist makes ownership explicit. Transaction reports are structs, DB and entity
handles are closed with `d.close`, and returned `Data` values are released.
Names also follow Kvist syntax: `t-to-tx` and `tx-to-t` correspond to Clojure's
`t->tx` and `tx->t`.

## Supported Peer operations

The compatibility inventory is pinned to Datomic Peer `1.0.7277`.

| Area | Supported operations |
| --- | --- |
| Connection and DB | `connect`, `db`, `sync`, `basis-t`, `next-t`, `db-stats` |
| Query | `q`, `query` |
| Entity and schema | `attribute`, `entity`, `entity-db`, `entid`, `ident`, `touch` |
| Pull | `pull`, `pull-many`, `index-pull` |
| Indexes | `datoms`, `seek-datoms`, `index-range` |
| Time | `as-of`, `as-of-t`, `since`, `since-t`, `history`, `is-history`, `t->tx`, `tx->t` |
| Transactions | `transact`, `with`, `resolve-tempid` |
| Log | `log`, `tx-range` |
| Utilities | `squuid`, `squuid-time-millis` |

`entity-db` is a Clojure adapter over the native entity capability. The other
operations in this table have native VevDB implementations.

VevDB also provides `rseek-datoms`, `db-with`, prepared queries, direct
listeners, bulk ingestion, and explicit index maintenance.

## Intentional differences

| Datomic Peer | VevDB |
| --- | --- |
| Connects through a Datomic URI and deployment | Opens an embedded local store |
| Uses a transactor and Peer coordination | Runs transactions in the application process |
| `transact` and `sync` use JVM asynchronous delivery | Returns the completed report or DB directly |
| Uses Datomic and JVM exception data | Uses `:vev.error/*` data and ordinary `ExceptionInfo` |
| Owns Datomic entity-ID and partition layout | Allocates VevDB IDs; compare logical identity instead |
| Provides the full Peer query implementation | Supports the documented VevDB query dialect |
| Provides the full Peer pull implementation | Supports the documented VevDB pull dialect |
| Can interrupt a timed-out query | VevDB can report an exceeded timeout but cannot interrupt native execution |
| Has Datomic-specific `db-stats` data | Returns VevDB storage and attribute statistics |
| Requires installed schema for normal attributes | Also permits VevDB schemaless attributes |

Query result order is only stable when the query asks for an order. Generated
entity IDs and implicit transaction instants may differ between Datomic and
VevDB even when the logical result is the same.

Rejected Clojure transactions throw `ExceptionInfo`. `try-transact` and
`try-with` are VevDB extensions for code that prefers explicit result values.
Kvist reports success or failure in its native `Tx-Report`.

## Deliberate non-goals

VevDB does not emulate APIs that belong to Datomic's deployment, JVM, or ID
architecture.

| Area | Not provided |
| --- | --- |
| Database catalog and administration | `administer-system`, `create-database`, `delete-database`, `get-database-names`, `rename-database`, `gc-storage`, `shutdown` |
| Datomic index administration | `request-index`, `sync-index`, `sync-schema` |
| Datomic deployment and excision | `sync-excise` |
| JVM asynchronous delivery | `cancel`, `qseq`, `transact-async`, `tx-report-queue`, `remove-tx-report-queue`, `release` |
| Datomic listener delivery | `add-listener`; use VevDB's direct `listen` instead |
| Datomic partitions and ID helpers | `entid-at`, `implicit-part`, `implicit-part-id`, `part`, `tempid` |
| Persisted JVM functions | `function`, `invoke` |
| Host-predicate filtered DBs | `filter`, `is-filtered` |

String tempids in transaction data are supported. The unsupported `tempid`
operation above is Datomic's partition-aware ID-construction function.

## Compatibility aliases

VevDB accepts `datomic.api/entid` and supported `clojure.string/*` functions
inside query data so copied tutorial queries continue to work. Portable VevDB
queries should use the corresponding unqualified operation when one exists.

The `"datomic.tx"` transaction tempid is accepted as the current transaction
for tutorial compatibility. Other strings, including `"datascript.tx"`, are
ordinary VevDB tempids.

## Exact inventory and tests

The machine-readable
[Peer compatibility inventory](../compat/datomic-peer-api.edn) records all 62
reviewed Peer operations as native, adapter, or non-goal. It is the exact
inventory; the tables above are the shorter human guide.

Run the manifest check and executable comparisons with:

```sh
scripts/check_datomic_peer_manifest.sh
scripts/compare_datomic_semantics.sh
scripts/contact_book.sh
scripts/compare_history_time_filters.sh
scripts/compare_aggregates_tutorial.sh
scripts/compare_musicbrainz_workshop.sh
```
