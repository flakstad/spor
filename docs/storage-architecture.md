# Storage Architecture

Vev uses SQLite as the durable backing store, but SQLite is not the Datalog
executor. Query, pull, rules, entity navigation, and index semantics run in Vev
over Vev-owned logical indexes.

In-memory Vev remains a first-class mode. None of the durable storage work
should make SQLite required for tests, temporary databases, embedded in-memory
use, or Kvist applications that want a pure in-memory database.

## Current Shape

SQLite stores:

- the append-only datom log and transaction metadata
- durable `log_index` values for datom lookup
- persisted logical index chunks for EAVT, AEVT, AVET, and VAET
- root rows that identify the visible chunk root for each index at a basis tx

New stores also record `entity-partition-layout=separated-v1`. This is a
compatibility boundary, not decorative metadata: ordinary entity allocation
must remain below `tx-partition-base`, while transaction ids occupy that base
and above. A non-empty store without the marker is refused because datoms alone
cannot reliably prove that an allocator-era entity/transaction collision never
occurred. After preserving a backup and auditing or migrating such a store, an
operator may make the explicit assertion with:

```sh
vevdb confirm-entity-partitions app.vev
```

Empty legacy stores are marked automatically. Vev never silently stamps a
non-empty legacy store during normal open.

Normal durable store APIs now return `Store-DB` and `Store-Tx-Report` values.
Those values are source/root-backed handles where possible, not rebuilt resident
`DB` values. Reopened durable reads can open persisted root metadata, use
chunk-backed index cursors, and resolve datoms by durable log index.
Root-backed DB handles, opened SQLite snapshots, and durable overlay DB values
track the SQLite root row id separately from the basis tx: the row id selects
normalized root pages, while the basis tx is the logical database value.
Opened snapshots and durable overlays also preserve their shared SQLite page
cache when converted back to root-backed handles. Opening a durable overlay for
query keeps the root metadata/cache in place alongside the opened SQLite
snapshot, so read access does not erase the cheap immutable handle shape.

Durable connection reads reuse a current-root page cache across repeated
read-only queries. Public write wrappers invalidate that cache after successful
ordinary writes, source-function writes, and logical grouped commits. The same
wrappers also run auto-maintenance and listener notification through the shared
profiling path. Committed durable transaction reports retain the before handle
and page cache that the write path already opened when possible, instead of
doing a second basis lookup just to manufacture `db-before`. Direct durable
writes and source transaction-function writes acquire `db-before` through the
current root-backed cache when available. Durable failure reports use the
already-opened or current root-backed handle when available, so
parse/read-only/direct-append failures remain storage-neutral and can keep
warmed page cache state.

Legacy resident APIs still exist for compatibility and recovery:

- `load-db-sqlite`
- `open-conn-sqlite`
- old `Tx-Report`-returning SQLite wrappers
- resident-only connection conversion helpers such as `vev_conn_from_db`

Those APIs may rebuild a resident DB. They should stay explicit and should not
be used silently by the production-shaped durable API.

## Query Boundary

The query engine should keep targeting Vev logical indexes and physical query
operators. It should not compile Datalog to SQL for normal execution.

The storage-facing abstraction is `DB-Index-View`, which can represent resident
arrays or chunk-backed SQLite cursors. Query, pull, validation, transaction, and
entity helper paths should move through this boundary instead of depending on
raw resident index slices.

## Remaining Storage Work

1. Finish cheap durable DB values.
   Retained `db-before`, `db-after`, reopened DB values, and source-backed DB
   values should be cheap immutable handles over shared persisted chunks plus
   small overlays.

2. Remove hidden resident rebuilds from normal durable paths.
   Resident rebuilds should be limited to compatibility, recovery, migration,
   and explicit diagnostics.

3. Continue shared chunk ownership.
   DB snapshots should share unchanged EAVT, AEVT, AVET, and VAET chunks and own
   only new chunks or small deltas introduced by a transaction.

4. Keep source-backed query operators complete.
   Remaining row/binding materialization fallbacks should move onto reusable
   physical operators or typed materialization boundaries.

5. Tighten compaction and maintenance policy.
   Explicit and automatic compaction should preserve immutable snapshot
   semantics and should not make ordinary small commits do surprising foreground
   merge work.

6. Extend historical database values.
   Transaction-id `as-of`, `since`, and `history` views now use the append-only
   log and immutable indexes. Add instant-to-transaction resolution and retain
   the same semantics through future storage-layout changes.

## Non-Goals

- exposing SQLite tables as Vev's public data model
- making application callers configure SQLite schemas directly
- making SQLite execute Datalog queries
- special reportless transaction paths that violate immutable DB snapshot
  semantics
- distributed Datomic client/transactor semantics before embedded durable
  storage is solid
