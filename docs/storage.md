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
log. Publishing a new EAVT, AEVT, AVET, and VAET checkpoint is independent,
derived work; a fresh connection reads the last checkpoint plus the committed
log tail and therefore sees the transaction immediately.

Index compaction remains derived maintenance and may run independently. It can
replace a deep run tree with a shallower equivalent root, but it never changes
the transaction basis or the facts visible at that basis.

### Canonical history and derived retention

The durable schema separates semantic history from rebuildable acceleration:

| Storage object | Purpose | Retention |
| --- | --- | --- |
| `vev_transactions` | committed transaction coordinates | canonical, permanent |
| `vev_datoms` | assertions, retractions, and transaction datoms | canonical, permanent |
| `vev_tx_meta` | transaction metadata values | canonical, permanent |
| selected `vev_datoms_*` SQLite indexes | log position, EAVT/entity, AVET, and ref-entity access paths | derived, retained for performance |
| `vev_fulltext*`, `vev_text_terms` | text-search acceleration | derived |
| `vev_index_roots`, `vev_index_root_pages` | immutable EAVT/AEVT/AVET/VAET checkpoints | derived; latest checkpoint retained |
| `vev_index_run_manifests`, runs, and range tables | legacy/delta-root plans and cursor pruning | derived; not created by ordinary novelty commits |
| `vev_index_chunks`, entries, and edges | immutable B-tree-like checkpoint pages | derived; latest-reachable pages retained |
| `vev_index_maintenance` | pending merge work | transient |
| `vev_snapshots` | legacy serialized-store compatibility | legacy migration input |
| `vev_meta` | store format and retention markers | semantic format metadata |

An ordinary commit writes canonical transaction, datom, transaction-metadata,
and full-text rows only. It does not create four roots, chunks, manifests, or
range rows. A database value is composed from the latest immutable checkpoint
and the canonical novelty after its basis. The novelty is replayed in
transaction order and merged into index scans, pulls, validation, `history`,
and immutable transaction reports.

VevDB publishes a broad checkpoint when the novelty reaches either 128
transactions or 4,096 datoms. Checkpoint publication and deletion of obsolete
derived artifacts are atomic, but do not run `VACUUM`; freed pages remain on
SQLite's freelist and are reused by later commits. The first transaction in a
new store creates the bootstrap checkpoint. The logical multi-transaction API
keeps one immutable in-process overlay per report inside its one uncommitted
SQLite transaction. Each overlay supplies the next group's exact `db-before`;
no intermediate durable roots are required, and the whole group still commits
or rolls back atomically.

Historical roots are accelerators, not the fact history. A retained
`db-before`, `db-after`, or `db` owns its checkpoint descriptor and immutable
novelty tail. If its derived root is no longer available, VevDB reconstructs
that exact basis from canonical datoms. Reopened `as-of`, `since`, `history`,
and basis-coordinate values use the canonical log. No committed logical
transactions are combined or removed.

An opened storage-backed DB value pins an independent SQLite read snapshot
until that value is closed. This closes the race between a concurrent query
and reclamation: the reader either sees its old pages or, if it had not opened
yet, reconstructs its basis. A long-lived opened reader can consequently keep
WAL pages alive and make an optional `VACUUM` report busy; close unused native
DB values and retry physical reclamation when immediate truncation matters.

`compact-indexes` absorbs the current novelty into a shallow equivalent
checkpoint and reclaims obsolete derived rows, but does not truncate the file.
`reclaim-indexes` performs the same logical checkpoint/reachability work and
then runs `VACUUM` to return free pages to the filesystem. Neither operation
deletes datoms, transaction rows, or transaction metadata:

```sh
vevdb compact-indexes example.db
vevdb reclaim-indexes example.db
```

The retention marker `derived-index-retention=latest-checkpoint-v1` is written
after full reclamation (`latest-reachable-v1` after reachability pruning).
These markers do not make the canonical schema incompatible with older stores;
opening an existing store needs no eager rewrite. The first normal maintenance
cycle migrates its derived retention lazily. Explicit reclamation is useful
after upgrading a large existing file because only it guarantees immediate
file truncation rather than reuse through SQLite's freelist.

The synchronous canonical-row indexes are `vev_datoms_log_index`,
`vev_datoms_eavt`, `vev_datoms_eavt_entity_cover`, `vev_datoms_avet`, and
`vev_datoms_vaet_entity`. Schema version 2 removes the unused text-ordered
`vev_datoms_aevt` and `vev_datoms_vaet`; immutable AEVT and VAET checkpoints
already provide those public orders. This migration changes only derived SQL
indexes, not canonical rows or the Vev database model.

The ordinary retained `vev_datoms_*` indexes are SQLite B-trees. The chunk indexes are
VevDB's immutable B-tree-like structure: leaf chunks normally contain 128
entries (512 for broad builds) and internal nodes have fanout 64. The two
representations overlap in sort order but serve different access paths. Direct
source operators use SQLite `INDEXED BY` plans, while immutable cursors, index
APIs, and checkpoint descriptors use chunks. This version retains both and
budgets their combined bytes. Range rows remain a legacy manifest optimization;
ordinary checkpoint-plus-novelty operation creates none.

This resembles Datomic's broad index segments plus novelty model, but is not a
claim that VevDB implements Datomic's private storage format. Datomic separates
its transaction log, broad immutable index segments, and an in-memory novelty
layer. VevDB maps the same semantic boundary onto one SQLite file: canonical
rows are the durable log, a chunk root is the broad checkpoint, and the
canonical rows after its basis are the novelty. SQLite B-trees remain part of
the local execution engine.

Public database values are immutable root descriptors. Creating one does not
leave statements or a read transaction attached to the writable connection's
live SQLite handle. Its first storage-backed read opens an independent snapshot
at the descriptor's exact root row, so callers may retain `db-before`,
`db-after`, and `db` values across later writes without blocking the writer or
silently advancing the retained value.

Opening or promoting a connection to resident execution reads its checkpoint,
datom log, legacy manifest metadata, and validation metadata through one SQLite read
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
- The canonical next transaction ID is checked again while holding the writer
  lock; a stale source or no-op transaction cannot reuse a committed ID.
- Existing database values do not change.
- Call `db` again to observe newer commits.
- Concurrent open and resident promotion observe one coherent storage
  generation, never a root from one commit and a log from another.

SQLite WAL mode provides the file-level reader/writer coordination.

The store format is private to VevDB. Use VevDB APIs for reads, writes, and
inspection.
