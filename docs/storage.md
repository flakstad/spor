# Storage

VevDB supports in-memory databases and durable local stores.

```clojure
(d/create-conn)             ; in memory
(d/connect "example.db")    ; durable
```

Both expose the same transaction, database-value, query, pull, entity, index,
and history model.

## Transaction semantics

VevDB preserves the Datomic-shaped database-value contract independently of
its storage representation:

- A database value is immutable and identifies one time basis.
- A successful transaction is atomic and advances the connection once.
- Its report's `db-before` is the exact value used to plan and validate that
  transaction, and `db-after` is the exact value produced by it.
- `tx-data` contains the transaction's assertions and retractions, while
  `tempids` resolves temporary identities allocated by that transaction.
- Retaining either report database value keeps that basis even after later
  transactions or compaction.
- `with` applies the same transaction semantics to an immutable database value
  without persisting anything or advancing a connection.

The Kvist API is synchronous rather than returning a future, requires explicit
`close` at its native resource boundary, and represents transaction rejection
as a report with `ok = false` rather than a Clojure exception. Those are API
surface differences, not database-model differences.

## Durable stores

Durable stores use SQLite internally. The native library includes a pinned
SQLite build with FTS5. Applications do not install SQLite, create tables, run
migrations, or issue SQL.

VevDB stores datoms, transaction metadata, and persistent EAVT, AEVT, AVET, and
VAET index roots. Reads use immutable snapshots backed by those indexes.

### Consistent storage backups

Use `backup` on a durable connection to create an independently openable Vev
store at a new path:

```clojure
(let [[basis ok error] (d.backup conn "backup.vev")]
  ...)
```

This is a storage backup, distinct from an immutable in-process DB value. Vev
uses SQLite's online-backup protocol, so committed data in the WAL is included
and concurrent readers remain valid. The destination must not already exist;
Vev never silently replaces it. On success, `basis` is the public transaction
coordinate contained in the completed destination—not an estimate taken from
the source before copying.

The result is a normal writable Vev store. A backup system should independently
open it, verify its application metadata, and add its own manifest and checksum
before considering a backup complete. Application caches and external files are
outside this storage operation.

Long-lived latency-sensitive applications can explicitly call
`ensure-resident!` after connecting. That connection then retains the current
immutable datoms and indexes in memory, so repeated queries and transaction
planning use VevDB's resident execution path. Transactions are still appended
to the same durable SQLite store and a newly opened connection observes them.
The choice is per connection: it is a memory/latency policy, not another store
format or source of truth.

Resident execution does not change transaction semantics. `transact` returns
the ordinary rich report with immutable `db-before` and `db-after` values;
those values retain persistent/chunked snapshot roots rather than cloning the
database. Before the call returns, SQLite has durably appended the transaction
log and published the corresponding EAVT, AEVT, AVET, and VAET roots. A fresh
connection can therefore read the same transaction immediately.

Index compaction remains derived maintenance and may run independently. It can
replace a deep run tree with a shallower equivalent root, but it never changes
the transaction basis or the facts visible at that basis.

Public database values are immutable root descriptors. Creating one does not
leave statements or a read transaction attached to the writable connection's
live SQLite handle. Its first storage-backed read opens an independent snapshot
at the descriptor's exact root row, so callers may retain `db-before`,
`db-after`, and `db` values across later writes without blocking the writer or
silently advancing the retained value.

Opening or promoting a connection to resident execution reads its root basis,
datom log, manifests, and validation metadata through one SQLite read
transaction on one handle. A concurrent writer therefore cannot make the
loader combine parts of two storage generations. Existing current-format
stores also skip schema DDL during open, so an ordinary reader does not become
a schema writer or spuriously contend with a transaction.

Rich resident reports carry their database-value ownership explicitly. A live
transaction transfers `db-after` to its connection, while a pure `with` report
owns both immutable values. Report cleanup follows that recorded mode; callers
do not have to infer ownership from which transaction entry point produced the
report.

Persistent indexes use a total order. Entity allocation is monotonic inside
the ordinary partition, but new ordinary entities still sort before the high
transaction partition in EAVT and are merged accordingly. Log position is the
final tie-breaker for otherwise identical datoms, including duplicate
retractions emitted by one logical transaction. Resident roots, durable run
roots, and a canonical rebuild therefore have the same order.

Ordinary paths and `sqlite://` paths select the same backend. VevDB does not
require a file extension. Replace `example.db` above with the path you want.

## Concurrency

Several connections and processes may open one store.

- Readers use stable snapshots.
- One writer commits at a time.
- Writers refresh the current basis before assigning a transaction ID.
- Existing database values do not change.
- Call `db` again to observe newer commits.
- Concurrent open and resident promotion observe one coherent storage
  generation, never a root from one commit and a log from another.

SQLite WAL mode provides the file-level reader/writer coordination.

The store format is private to VevDB. Use VevDB APIs for reads, writes, and
inspection.
