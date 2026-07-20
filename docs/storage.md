# Storage

Vev has completed the first durable SQLite proof phase. Durable storage is not
production-complete, but the basic semantic loop is now real and measured:
open, write, close, reopen, query, transaction metadata, host connection
handles, and Datalevin-style write-bench scaffolding all exist. The active
storage phase is now the shared immutable/chunked index architecture described
in `docs/storage-architecture.md`.

The storage layer must preserve the existing semantic model:

- DB values are immutable snapshots.
- Transactions append facts and retractions with stable tx ids.
- Query, pull, entity, and index semantics are owned by the engine, not by SQL.
- Host APIs should keep using opaque connection and DB snapshot handles.

## Public Shape

The public durable API should be storage-neutral. Applications should open a
Vev store/connection, transact EDN or prepared tx-data, obtain immutable DB
values, and query/pull those DB values without programming SQLite directly.

Current preferred entry points:

- Kvist/internal: `open-store`, `store-db`, `transact-store-report-text`,
  `transact-store-report-tx-data`, `transact-store-report-tx-data-groups`,
  `q-result-store-*`, `q-result-store-db-*`
- C ABI: `vev_connect`, `vev_connection_db`,
  `vev_connection_transact_edn_report`, `vev_tx_report_db_before`,
  `vev_tx_report_db_after`
- Host wrappers: `connect`, `db`, `transact`, `q`, `pull`, `with`, and
  `db-with` in the language-specific API

The current durable backend is SQLite. A plain filesystem path and
`sqlite://...` URI both select that backend. Release builds include a pinned
SQLite amalgamation with FTS5 in the native library. Application code does not
install SQLite, create SQLite tables, run migrations, issue SQL, or configure
SQLite schemas.

## Concurrent Access

Several connections, including connections in separate processes, can open the
same durable VevDB store. Readers and one active writer can proceed
concurrently through SQLite's WAL mode. Multiple writers are serialized at the
transaction boundary; after acquiring the writer lock, VevDB refreshes its
transaction basis and durable index roots before assigning the next tx id.

A DB value remains an immutable snapshot. A long-running program, REPL, or
VevDB CLI process therefore calls `db` again on its connection to observe
commits made through another connection. Existing DB values continue to show
the basis they captured. This is the same rule after a local transaction: keep
an old DB value for a stable view, or obtain a new one for current facts.

Opening a new durable store also yields a valid empty DB value before its first
transaction. Querying that value returns empty results; callers do not need a
bootstrap transaction merely to obtain a database snapshot.

Durable stores can be configured with `configure-store-durability!`:

- `:strict`: asks the backend for stricter commit synchronization
- `:normal`: default durable mode
- `:relaxed`: faster local/testing mode with weaker synchronization guarantees

This is a Vev store-level setting, not an application-facing SQLite schema
hook. It exists because the current write profile shows per-transaction durable
commit cost dominates one-datom SQLite writes once Vev root publication is
small.

Prepared query reuse is available at both immutable DB-value and connection
boundaries. `q-result-store-db-prepared-with-input-text` runs a prepared query
against a retained immutable `Store-DB`; `q-result-store-prepared-with-input-text`
runs the same shape directly against a `Store-Conn`, including durable
SQLite-backed and shared in-memory stores. The connection-level wrapper still
returns an owned result when it closes a temporary durable DB handle internally.
Retained `Store-DB` query APIs may use shallow result rows when the DB handle
stays alive, while connection-level durable query APIs use explicit owned
source-query variants before closing their temporary snapshot. This keeps
host-facing cleanup simple without forcing every immutable DB-value read to
deep-copy plain datom-backed result rows.

Prepared tx-data can also be grouped explicitly with
`store-tx-data-group` and committed through
`transact-store-report-tx-data-groups`. This is a bulk ingestion API, not a
transparent change to `transact`: Vev flattens the groups into one ordinary
transaction/report and therefore one durable commit. It is useful when the
caller wants bulk throughput and does not need a separate tx id for each input
group. The C ABI exposes the same low-level shape for typed transaction
builders as `vev_connection_tx_commit_many_report`; Java, Clojure, Python, and
Rust wrap that as durable bulk builder APIs.

Vev also has a lower-level logical group commit entry point,
`transact-store-report-logical-tx-data-groups`, for source-backed SQLite
stores, including first use on an empty durable store. This keeps each group as
its own logical transaction, advances tx ids per group, returns one
`Store-Tx-Report` per group, and wraps the whole batch in one SQLite
transaction/commit. It is not the same as flattened bulk ingestion. The C ABI
exposes this as
`vev_connection_tx_commit_logical_many_reports`, returning a report-array handle
with one borrowed report per logical transaction. Java exposes
`DurableConnection.transactLogicalReports`, Clojure exposes
`transact-logical-bulk`, Python exposes
`DurableConnection.transact_logical_bulk`, and Rust exposes
`DurableConn::transact_logical_bulk_reports`. Ordinary EDN tx-data logical
groups are also exposed as Java `transactLogicalEdnReports`, Clojure
`transact-logical`, Python `transact_logical`, and Rust
`transact_logical_edn_reports`. Empty-store bootstrap,
empty group lists, no-op/cancelling logical transactions, and sequential CAS
basis changes have source-backed storage regressions. A later CAS failure also
proves the whole logical group rolls back, including earlier successful logical
writes in the same SQLite transaction. Read-only durable stores and
shared/in-memory stores reject this durable-only logical group path with
explicit errors instead of silently rebuilding a resident compatibility DB.
Empty logical groups return empty report arrays through the host APIs, matching
the store-level no-op behavior. Malformed non-empty C builder arrays in this
path return a one-report failed report array instead of a null handle, so host
adapters can surface normal `:ok false` / `:error` data.
The group path does not require a pre-existing durable index root; empty stores
bootstrap through the same source-direct first-write path as ordinary durable
transactions.
Grouped source transaction functions now use the same logical group commit
machinery: later source-fn calls can read prior logical writes inside the same
SQLite transaction, and durable roots are published per logical tx basis. The
important implementation boundary is that carried group snapshots must stay on
the same SQLite handle while the outer transaction is open; reopening by file
path cannot see uncommitted roots. Malformed text/parser input behavior and
retained DB-value benchmarking also remain next work.

SQLite-specific names such as `open-sqlite-conn`, `transact-sqlite-*`,
`vev_sqlite_conn_*`, `open-sqlite`, and `openSqlite` remain compatibility,
debug, or raw C ABI entry points. Application code should use `connect`.
Older resident-shaped `Tx-Report` paths are resident compatibility only;
reopened durable stores should either use
`Store-Tx-Report`/`Store-DB` or fail loudly instead of silently rebuilding a
resident DB.
Likewise, `vev_conn_from_db` is a resident/in-memory compatibility escape hatch.
Durable code should pass immutable DB handles as values and query/pull/with
against those handles directly.

## Implemented Storage Slices

The first implemented storage slice was snapshot-file persistence:

- `save-db-snapshot-text`
- `load-db-snapshot-text`
- `open-conn-snapshot-text`
- `persist-conn-snapshot-text`

These functions write and read the existing EDN-ish serializable datom snapshot.
This is deliberately a scaffold, not the final SQLite backend. Its job is to
make the durable open/write/close/reopen/query loop real while the storage
boundary is still small.

The first SQLite-backed compatibility slice persisted datoms as rows:

- `save-db-sqlite`
- `load-db-sqlite-resident`
- `open-conn-sqlite-resident`
- `persist-conn-sqlite-resident`

It creates Vev metadata, transaction, datom, and forward-compatible index
root/chunk tables, writes one row per datom through a SQLite transaction,
and can rebuild a resident `DB` from those rows for compatibility and
validation. The older `load-db-sqlite`, `open-conn-sqlite`, and
`persist-conn-sqlite` names remain wrappers around the explicit resident
entry points. Normal durable application code should use `open-store`,
`store-db`, `transact-store-report-*`, and `q-result-store-db-*` so reopened DB
values stay root/source-backed instead of rebuilding resident arrays.

The older snapshot table remains as a compatibility fallback for databases
created by the first SQLite snapshot slice. Vev now writes stable
`vev_datoms.log_index` values and bounded logical-index chunks after
successful SQLite transactions and explicit SQLite persists: small
indexes use a single payload chunk, larger indexes use bounded leaf chunks plus
a parent root chunk, and a root row records the visible chunk root for each
logical index at the committed basis tx. Resident compatibility reload can
validate persisted index entries back through root/chunk edges against rebuilt
indexes, but the normal durable DB-value path opens root metadata and cursor
state directly. Vev can now also load bounded persisted index-entry pages by
offset and limit, reading only the leaf chunks covering that page. A read-only
SQLite index cursor wraps that page loader with
cached-page `count`/`at` access over persisted logical index entries. The
runtime `DB-Index-View` abstraction can now wrap either resident arrays or a
SQLite cursor, and tests exercise view `count`/`at`/bound helpers over a
persisted cursor. SQLite can also fetch an individual datom by durable log
index, which is needed for resolving persisted index entries without full
datom-log materialization. `SQLite-Index-Snapshot` now packages the four
persisted index cursors and datom lookup behind one path/open handle, and
`SQLite-DB-Snapshot` adds basis tx plus datom count metadata, so Vev can open
storage root/cursor state without `load-db-sqlite`. It can also read a single
entity by binary-searching persisted EAVT and resolving only that entity's
datoms, plus attribute and entity+attribute reads by binary-searching persisted
AEVT/EAVT and resolving matching durable log indexes. The DB snapshot keeps a
prepared datom-by-log-index statement open for repeated materialization.
Persisted index roots can now be recursive: direct SQLite append writes for
new entities publish EAVT as a parent root that references the previous EAVT
root plus newly appended chunks. This avoids rewriting the full EAVT payload
for the common append-only entity case and keeps retained basis roots valid.
SQLite commits produced by source transaction functions use the same path when
the expanded transaction appends only new entities. Source-backed transaction
reports carry this append-publication metadata into SQLite commit, so the commit
publisher does not reread write-state metadata just to recompute append-root
eligibility. Reports also carry the per-index append-mode proofs for EAVT,
AEVT, AVET, and VAET. SQLite commit uses those proofs directly when building
the persisted roots. Publication chooses append-root sharing independently by
checking the appended segment against each index's own key order; if ranges
overlap, that index falls back to a merged root while other indexes can still
share.
The durable schema now also has explicit run-manifest tables for non-append
publication. `vev_index_run_manifests` records a base index root, total logical
row count, total run count, and optional parent manifest. `vev_index_run_manifest_runs`
records the manifest's local pending run roots. Normal source-backed SQLite
writes now use these manifests for non-append logical indexes: each tiny commit
publishes one small run plus a manifest pointer instead of copying or rebuilding
a generic merge-root tree for AEVT/AVET/VAET. Source cursors read manifest-backed
roots by expanding the parent chain and merging the base root plus pending runs
through Vev's normal index/order logic. Generic merge-root publication remains
for compatibility and for older root shapes, but it is no longer the normal
non-append tiny-commit path.
Lazy page reads over recursive roots select only overlapping leaf chunks and
return the selected leaf base offset to the in-memory windowing layer. Full
index-entry reads still concatenate the full recursive root for diagnostics and
tests. Explicit index compaction can collapse latest manifest-backed roots into
ordinary persisted roots. Automatic foreground maintenance now also recognizes
manifest-backed latest roots even when the old maintenance queue is empty, and
compacts one bounded run range at a time before republishing a replacement
manifest. Long parent chains are therefore bounded by policy instead of left to
grow unchecked. Broad-read cost over bounded manifest roots is now much closer
to compacted-root cost for the current gate benchmark: a 1000 batch-1
manifest-chain read benchmark with automatic maintenance keeps
`max_merge_runs=5` and reads broad source queries in about 19.5ms, versus about
18.7ms after explicit compaction. Resumable merge/manifest cursor state removed
the worst repeated-page replay cost, read snapshots now use a larger cursor
window than write leaf chunks, append-only SQLite snapshots skip redundant
currentness materialization, merge/manifest pages retain the datoms they
already materialize for k-way ordering, and broad prefix source scans over
manifest roots now scan child runs directly instead of binary-searching random
positions in a merged cursor. Selective manifest prefix scans now persist
attr-segment value bounds for AEVT/AVET runs, including direct tiny runs and
compacted child roots, and now also stores first/last segment ordinals so attr
scans can avoid rediscovering segment bounds with per-run binary searches. The
source planner also drives literal attr/value anchor joins through the filtered
entity+attr operator instead of the broad two-attr scan. The current
bounded-manifest selective row is about 3.3ms on the 1000-row gate, down from
the previous 80-93ms row. The 5000-row gate now keeps selective reads around
10.3-11.5ms before explicit compaction and 16.7-17.0ms after compaction.
Broad reads are now about 36ms before explicit compaction and 55ms after
compaction. Lazy manifest run-range streams avoid materializing an intermediate
datom array and skip redundant prefix checks when run bounds are already exact.
Non-manifest merge roots now use the same lazy run-range stream instead of
building a full owned datom array before returning rows.
Single-column source projections also dedupe through a keyed set instead of
linearly scanning already-emitted rows, removing an O(n^2) broad-result cost.
The remaining storage work is to reduce per-returned-value materialization with
page/chunk-level result streaming or typed column batches and keep range
metadata compact as manifests age. The run-range stream still triggers a Kvist
ownership warning for owned arrays transferred into the returned stream struct;
cleanup is centralized in
`delete-source-index-datom-stream`.
`SQLite-DB-Snapshot` now also records
whether the snapshot has persisted retractions; append-only snapshots can skip
the expensive per-candidate EAVT currentness proof and treat added datoms as
current, while snapshots with retractions keep the conservative proof path.
Writable SQLite connections cache this durable-log metadata directly: current
datom count and whether any retractions have been persisted. Direct source
writes advance the cache after successful appends and rollback/legacy paths
invalidate it. This keeps the current-source open path from re-counting the
whole durable log or re-scanning for retractions before every tiny commit,
without reusing a stale DB snapshot for transaction validation. The same source
open path can now reuse the connection's cached current basis after
source-direct writes, avoiding a redundant latest-root lookup. This is a
metadata cleanup only; logical group commit still needs group-local root/source
state to avoid opening a source snapshot for each logical transaction.
Direct source writes also reuse a prepared root-row insert in the existing
index write-statement bundle, so root publication no longer prepares/finalizes
the `vev_index_roots` insert per commit.
The same write-statement bundle now also prepares run-manifest row, run-entry,
and attr-range inserts. Direct source writes build manifest attr ranges from
the commit's appended datoms when those datoms are already available, avoiding
a reload of just-written log indexes while publishing non-append manifest roots.
Live SQLite connections now have internal text and prepared query wrappers
(`q-result-sqlite-conn-text` and `q-result-sqlite-conn-prepared`) that open a
short-lived `SQLite-DB-Snapshot`, query through `DB-Read-Source`, close the
storage snapshot, and return an owned `Query-Result`. Normal public
`connect`/`db` access now uses those cursor-backed `Store-DB` values for reads.
Writable SQLite connections open lazily: they keep only the live SQLite handle
plus a small resident shell until the first transaction, so opening a durable
connection for metadata, `db`, query, or pull no longer rebuilds the resident
datom log. Storage-neutral transaction reports can publish supported
source-resolvable writes directly: Vev resolves tx-data against a
`DB-Read-Source`, publishes the source-overlay add/retract datom log, writes
new persisted index roots, and returns SQLite-backed `db-before` / `db-after`
handles without loading a resident `DB`. Covered direct shapes include add,
cardinality-one replacement, explicit retract, retract-attribute,
retract-entity, same-transaction lookup refs, reverse ref lookup vectors,
nested maps through ref attrs, tempids in ref values, duplicate add
suppression, unique-identity upserts, same-transaction identity upsert
convergence, unique ref-value tempid upserts, tuple-identity upserts with
tempid/lookup components, transaction metadata, current-tx aliases, registered
source transaction functions, and CAS. Shared-store source-function transaction
reports also return retained shared `Store-DB` snapshots for `db-before` and
`db-after`, including failure reports. SQLite store-report parse failures,
read-only write failures, and source-direct validation failures return
root-backed `db-before`/`db-after` handles for initialized stores without
loading the resident DB or opening report snapshots eagerly. If root metadata is
not available they fall back to the older path/basis lazy handle shape. No-root
parse failures still return empty storage-neutral handles.
SQLite source transaction-function commits now use the same direct source
append helper, append-mode metadata, write-state cache advance, and lazy report
`Store-DB` handles as ordinary durable `Store-Tx-Report` writes. Their
pre-call, generated, and tail tx-data segments resolve through the source-only
resolver, so a durable/source-backed report never falls back to resident
transaction resolution for unsupported function output. Initial
SQLite store-report commits now also publish lazy durable `db-after` handles
instead of opening a report snapshot immediately after writing the first index
roots. No-op/cancelling source-direct commits, including source transaction
functions that expand to empty tx-data, still advance transaction/root
metadata, but they now copy the latest persisted index root ids/manifests for
the new basis instead of rebuilding unchanged index chunks. The remaining
write-publication work is mostly reducing tiny-commit root/chunk publication
cost and migrating the older resident-shaped compatibility report path. The
older resident-shaped `Tx-Report` transaction API still upgrades by loading the
resident connection before running the existing compatibility path. There is
also an internal source-only SQLite connection opener with the same no-rebuild
read shape that rejects transactions
explicitly.
The storage-neutral aliases (`open-store-read-only`, `q-result-store-text`, and
`q-result-store-prepared`) now expose this mode inside Vev without making
query-facing code mention SQLite. `store-read-only?` and
`store-resident-db-available?` make the current compatibility boundary explicit:
source-backed stores can query persisted index chunks before a resident rebuilt
`DB` exists.
`Store-DB` is the internal storage-neutral immutable DB snapshot handle for
this path. It currently wraps a retained `SQLite-DB-Snapshot`, exposes the
same `DB-Read-Source` boundary as resident DBs, and can run text/prepared
queries without rebuilding resident arrays. SQLite-backed retained `Store-DB`
handles now reopen an independent read snapshot for the same durable path,
at the original basis tx, and remain queryable after the original read-only
store/snapshot is closed. SQLite index cursors are basis-pinned, so a durable
DB value taken at tx N keeps reading the tx N index root even if the writer
later advances to tx N+1. It also has a shared-snapshot variant for the shared
in-memory publish path.
The C ABI `vev_db_t` wrapper now stores this shape internally. The previous ABI
compile blocker is gone: `scripts/build_c_abi.sh` now builds `libvev` and
passes the C, Python, Rust, Go, Node, Java, and Clojure smoke coverage,
including in-memory direct nested pull through `vev_pull_edn`,
storage-neutral DB-handle prepared queries, and host-wrapper nested pull
traversal. Shared `Store-DB` direct nested pull is covered through the
source-backed renderer, and the storage architecture test now covers the same
nested direct pull shape through a retained read-only SQLite `Store-DB`, plus
querying a retained durable handle after closing its original store. Immutable
host `with`/`db-with` also routes through `Store-DB` now. For non-resident
snapshots the report path first resolves transactions through source-backed
write-state overlays. Supported shapes return retained shared/SQLite overlay DB
values; unsupported source-backed shapes fail explicitly instead of silently
rebuilding a resident compatibility DB.
Durable host transaction reports now use the same storage-neutral report shape:
the C ABI transact report path returns retained `Store-DB` handles, and for
supported source-direct SQLite writes those handles are backed directly by the
new persisted index roots instead of resident clones. Direct durable reports
now publish lazy SQLite-backed `Store-DB` values for `db-before` and
`db-after`: the report carries the durable path and basis tx, and Vev opens the
basis-pinned SQLite snapshot only when the caller actually queries, pulls, or
otherwise reads that DB value. This preserves the Datomic-like DB-as-value API
without paying report snapshot-open cost on every commit. The direct durable
root builder also reuses prepared SQLite statements for index chunk and edge
inserts across all four index roots in a commit, so the remaining write cost is
the persisted root/run representation itself rather than repeated SQL prepare
work for each tiny chunk row. Persisted index chunk rows now also record
`child_count`; new parent roots can carry append/flatten metadata directly, and
migrated older parent rows fall back to counting `vev_index_chunk_edges` only
when the stored count is absent. Small repeated append roots now fill the
rightmost level-0 leaf chunk before appending a new leaf sibling. A small
append from a level-0 root rewrites a new leaf chunk containing the previous
leaf payload plus the appended entries until the configured leaf chunk size is
reached. Once a leaf is full, Vev appends a new leaf through the segmented
right-spine parent shape: it fills the last child subtree before adding a
sibling, and only increases the root level when the whole root is full. That
keeps retained roots valid, avoids a long one-child parent chain, and fixes
the earlier one-leaf-per-visible-datom shape. The write benchmark reports root
level, root child count, tree node count, and leaf count so this shape is
observable. The latest batch-1 smoke keeps EAVT at 16 leaves / 17 total nodes
after 1000 writes and 79 leaves / 82 total nodes after 5000 writes.
Merge roots persist flattened run-count metadata in chunk metadata during
parent chunk insertion, so normal maintenance scheduling and non-inline append
publication can decide from local metadata instead of recursively flattening
retained merge roots or doing a second metadata update. Actual compaction still
loads child roots because the merge operation needs them.
Appending an empty per-index delta to an existing persisted root now returns
that existing root directly. This is a small but important invariant for the
next storage representation: a transaction that leaves an index unchanged
should copy the root id/manifest metadata, not publish empty chunks. Vev does
this at the root-set boundary for empty-delta source commits: the new basis row
points at the previous root ids/manifests through the same helper for
mode-discovery and known-mode append publication, and root-only durable tests
assert that no datoms, chunks, or maintenance queue entries are added. Vev does not yet
prune VAET for scalar-looking attrs, because current semantics and tests still
allow reverse/pull behavior over attrs without explicit ref schema. Schema-aware
VAET pruning should be treated as a compatibility decision, not a local storage
optimization.
Root publication now has explicit `SQLite-Index-Root-Publish` values carrying
each index root id, manifest id, and append/manifest mode, and those feed one
`SQLite-Index-Root-Set` carrying the four logical root ids and four manifest
ids. Append modes are also grouped as `SQLite-Index-Append-Modes` at this
boundary and flow through source append, source-direct write publication, and
the older full-index compatibility append helper as one value instead of four
loose booleans. Source-direct appends and maintenance republish paths
build/publish these values instead of passing loose parallel root arguments.
Durable root publication now persists this page-shaped boundary in
`vev_index_root_pages`: every published root row has four normalized page rows
with index name, root chunk id, manifest id, and ordinal. The existing wide
`vev_index_roots` columns remain for compatibility and migration. Root-set
reads now prefer `vev_index_root_pages` and fall back to the wide row for older
or partially migrated files. The main lower-level latest/basis metadata reads
for row counts, root chunk ids, manifest ids, run counts, first keys, levels,
and child counts also prefer root-page rows. Debug and entry-page helpers now
also discover current root chunks through the same root-page metadata path.
The wide row is still written and read as compatibility fallback, but it is no
longer the preferred durable read boundary.
Append-mode source-backed writes now use this boundary to publish SQLite cursor
views as run-manifest deltas too, so the normal small durable write shape is
old root plus a small persisted run rather than a newly grown append-tree root.
Both append root publication paths build the four ordered appended delta views
once at the root-set publication boundary and pass those slices to per-index
publication, rather than letting each index helper rediscover its ordered
append slice. Small manifest delta runs now use an entry-backed chunk
representation: `vev_index_chunks.payload_text` stores the `:entries` marker
and the ordered durable log indexes are stored in `vev_index_chunk_entries`.
Larger delta runs build ordinary parent chunks over entry-backed leaves. Leaf
page readers support both this representation and older serialized payload
chunks, so current files remain readable while new deltas become explicit
persisted segments.
Vev still has a
rollover path for migrated/intermediate one-child parent roots with local
payload: that path promotes the local payload into child chunks at the same
parent level before adding the new appended leaf. The next storage layout work
is reducing the remaining repeated root/chunk-row publication cost with a
clearer B-tree/LSM node update strategy or page-level delta representation.

There are now two internal write modes:

- explicit resident full persist: `persist-conn-sqlite-resident` replaces the
  durable datom rows with the connection's current full datom log
- SQLite-backed store writes: `transact-store-report-*` and the lower-level
  `transact-sqlite-store-report-*` source-backed paths append successful
  report tx-data plus tx metadata rows to SQLite before returning retained
  `Store-DB` values

If the SQLite append fails after the in-memory transaction succeeds, the
wrapper restores the previous DB snapshot and reports a failed transaction.
That keeps the wrapper-level connection consistent with the durable store.
The wrapper now owns a live SQLite handle for its lifetime, so repeated
transactions do not reopen the file or rerun schema setup on every commit.

The public host API now exposes this durable connection shape through
storage-neutral connection handles:

- C ABI: `vev_connect`, `vev_connection_*`
- Python: `vev.connect(...)`
- Java: `vev.connect(...)`
- Clojure: `vev/connect`
- Rust example: `DurableConn::open`

The current durable backend is SQLite. A plain filesystem path and
`sqlite://...` URI both select the SQLite backend. The older
`vev_sqlite_conn_*`, `open-sqlite`, and `openSqlite` names remain for
compatibility and debugging; normal host-client code uses the neutral
`connect` shape.

Durable connection metadata is available through the same neutral boundary:
`vev_connection_backend` reports `"sqlite"` today, `vev_connection_path`
reports the concrete storage path, and `vev_connection_basis_t` reports the
last committed transaction visible to the connection. `vev_connection_tx_count`
reports the number of persisted transaction-log rows, and
`vev_connection_tx_ids` returns the persisted transaction ids in order. Basis,
transaction count, and transaction ids are recomputed when opening a durable
store, so close/reopen preserves both rows and observable transaction-log
metadata. Higher-level wrappers expose the same diagnostic shape as
`backend`/`path`/`basis_t`/`tx_count`/`tx_ids` methods or Clojure
`connection-info`. `vev_connection_info_edn` is the C-friendly
convenience form for logging or simple tooling that wants the same metadata as
one EDN map string.

Live connection transactions return reports whose `db-after` is the
connection's current DB value. Cleanup code for those reports should use
`delete-live-tx-report-shallow`, which deletes the report-owned `db-before`
and report collections without freeing the live connection DB. The generic
`delete-tx-report-shallow` remains appropriate for immutable `with-*` reports
and failed reports that do not alias a live connection.

Explicit full DB persist cannot reconstruct report-only tx metadata from a
bare DB value; metadata rows are written by the SQLite-backed transaction
wrapper when it has the successful transaction report in hand.

`bench/sqlite_storage.kvist` now measures the first durable storage baseline:

- `single-append`: one SQLite-backed transaction per entity
- `batch-append`: one SQLite-backed transaction for a configurable entity batch
- `store-report-single-append`: one production durable `Store-Tx-Report`
  transaction per entity through `open-store`
- `store-report-batch-append`: one production durable `Store-Tx-Report`
  transaction for a configurable entity batch through `open-store`
- `store-append`: runs both `store-report-*` append workloads
- `batch-transact-memory`: the in-memory transaction part of the same batch
- `batch-append-sqlite`: the SQLite append part of the same batch
- `batch-before-snapshot`: reportable DB-before snapshot creation
- `batch-resolve-tx`: tx-data resolution into concrete tx ops
- `batch-apply-resolved`: applying already-resolved ops to the connection
- `append-log-copy`: direct copy/append cost for the current datom log
- `append-index-build`: direct incremental index build cost for the copied log
- `persisted-index-load`: load persisted logical indexes through SQLite
  root/chunk rows without building a full `DB`
- `persisted-index-page-load`: walk persisted logical indexes through bounded
  SQLite root/chunk pages without building a full `DB`
- `persisted-index-cursor-scan`: scan persisted logical indexes through the
  cached SQLite index cursor abstraction
- `persisted-index-snapshot-open`: open all persisted index cursors as a
  `SQLite-Index-Snapshot` and resolve a representative datom by durable log
  index without rebuilding a full resident `DB`
- `persisted-db-snapshot-open`: open basis/datom-count metadata plus all
  persisted index cursors as a `SQLite-DB-Snapshot`, then resolve a
  representative datom by durable log index
- `persisted-db-snapshot-entity-read`: keep a `SQLite-DB-Snapshot` open,
  binary-search persisted EAVT for one entity, and materialize only that
  entity's datoms by durable log index
- `persisted-db-snapshot-entity-attr-read`: read one entity+attribute from a
  persisted DB snapshot without reopening resident arrays
- `persisted-db-snapshot-attr-read`: scan one attribute through persisted AEVT
  and materialize matching datoms; sampled lightly because it intentionally
  materializes many rows through the snapshot's prepared log-index reader
- `persisted-db-snapshot-source-query`: parse and execute a one-clause EDN
  query against `SQLite-DB-Snapshot` through the new source-backed query path,
  without reopening resident arrays
- `persisted-db-snapshot-source-join-query`: parse and execute a multi-clause
  EDN join query against `SQLite-DB-Snapshot` through the source-backed query
  path, without reopening resident arrays
- live store source queries: internal text/prepared wrappers query the latest
  persisted snapshot through source-backed reads, then close the snapshot before
  returning owned result rows
- read-only store open/query: skips resident datom-log replay and uses the live
  handle only for short-lived persisted snapshot reads
- `store-conn-source-prepared-query`: open a normal live durable store and
  measure the prepared-query wrapper that opens/closes a short-lived persisted
  snapshot for each read
- `store-read-only-open`: open a read-only durable store without resident
  datom-log replay
- `store-read-only-prepared-query`: query through a read-only durable store,
  opening short-lived persisted snapshots for each read
- `store-db-prepared-query`: retain a chunk-backed immutable `Store-DB`
  snapshot once and run prepared queries against that DB value
- `reopen-rebuild`: reopen SQLite datom rows and rebuild in-memory indexes
- `reopened-query`: run a prepared query against the reopened DB snapshot

`bench/sqlite_storage.kvist` accepts `--workload <name>` to run one workload.
The group names `append`, `durable`, and `source` run related subsets; `all`
remains the default.

The `store-report-*` append workloads also print `engine=vev-store-profile`
rows with average direct-write phase costs. Use those rows to decide storage
work: source-open/read overhead, tx resolution, overlay construction, append
root build/persist, SQLite commit, maintenance, and listener notification are
reported separately.

The current `source` subset exercises the persisted source query path, the
store-level prepared query wrapper, read-only store open/query, and retained
`Store-DB` DB-value queries without resident datom-log replay. While adding
this selector, the source-backed clause matcher was tightened to treat scanned
datom values as borrowed and copy only when a value is stored in an output
binding. That keeps source snapshot query cleanup valid for larger scans.

The first benchmark pass found and fixed a serializer ownership bug: storage
callers delete `value-serializable-text` results, so that function must return
heap-owned text for literals, formatted scalars, keywords, symbols, vectors,
and maps.

`bench/write_bench.kvist` now starts mapping Datalevin `write-bench` concepts
onto Vev's durable API:

- pure SQLite-backed writes at batch sizes 1, 10, 100, and 1000
- mixed read/write behavior using prepared EDN queries against the live DB
  snapshot
- end-to-end call latency and commit-path latency reporting

This harness is intentionally smaller than the final external benchmark. It is
for regular development runs and accepts `--total`, `--report-every`,
`--mixed-operations`, `--batch`, and `--seed-batch` so larger runs can be
launched without source edits. It also has
`--workload pure|pure-store-report|pure-store-report-deferred|manifest-chain-read|sqlite-store-db-heavy|mixed|snapshot-heavy|shared-snapshot-heavy|shared-snapshot-heavy-direct|shared-store-db-heavy|both`
and `--path`, which allows the Datalevin-style sequence of writing a durable
store first and then running mixed read/write against the same store.
`sqlite-store-db-heavy` also accepts `--durability :strict|:normal|:relaxed`
to make the commit-synchronization tradeoff explicit. It uses a plain long
`:item/key`, matching Datalevin's write-bench schema.
The legacy `snapshot-heavy` workload keeps the resident SQLite compatibility
write path and retains ordinary `DB` snapshots. It remains useful as a
comparison harness, but it is no longer the durable DB-value gate.
The `shared-store-db-heavy` workload measures the storage-neutral host-facing
shape over the shared in-memory publish path. It commits typed tx-data through
`Store-Conn`, retains every `Store-DB`, and closes those retained handles at the
end. A local batch-1, 200-write run on June 30, 2026 matched raw
`shared-snapshot-heavy` almost exactly: both ended near 0.172 ms commit latency
and 0.012 ms snapshot-retain latency at 200 writes. That means the
storage-neutral `Store-DB` wrapper is not adding visible cost at this scale;
the remaining work is still the shared publication adapter and resident-index
boundary.
The `sqlite-store-db-heavy` workload is the durable equivalent over SQLite. It
writes through `open-store` / `transact-store-report`, retains a public
`Store-DB` from each report after deleting the report, and closes those retained
handles at the end. That workload is the current acceptance harness for
Datomic-style code that passes durable DB values around while a connection
continues to transact.
The first profiled 5000-write run shows retained `Store-DB` handles are already
cheap (`snapshot_latency_ms` stays around 0.001 ms), but direct writes still pay
growing `open_before_ms` to reopen the current SQLite snapshot/root metadata
before every append. The next storage architecture target is therefore a safe
current-source/root metadata cache for direct writes, not a retained-handle
wrapper shortcut. The cache must include the previous committed datoms in
transaction semantics; simply reusing the old pre-commit snapshot would break
uniqueness, cardinality, lookup refs, and transaction functions.
That metadata cache is now in place for direct writes, and logical group commit
also carries the current basis forward through same-handle SQLite snapshots.
The current group-commit bottleneck is no longer source/root reopen work:
batch-50 group commit measures about `0.002ms/write` in `open_before_ms`, and
the loop avoids opening a carried source snapshot after the final logical
transaction. The remaining group-commit storage target is root/write-state
publication: avoid redoing per-index root append/persist setup for every
logical transaction while still producing distinct durable tx ids, root rows,
reports, and retained `Store-DB` values.
The `shared-snapshot-heavy-direct` workload routes successful append-only
transactions through the direct shared-log comparison path. A local batch-1,
300-write comparison with chunk size 1024 ended around 0.248 ms commit latency
for default shared publication, 0.458 ms for direct shared-log comparison, and
0.246 ms for storage-neutral `Store-DB`. The direct path is useful to keep
measured, but it is not the current hot path.

A 10k-row local run on June 26, 2026 shows the current durable shape clearly:

- batch-100 pure write: about 13k writes/second by 10k rows
- batch-1 pure write: about 544 writes/second by 10k rows
- mixed read/write over a 10k-row store: about 184 writes/second

An initial `snapshot-heavy --total 500 --batch 1` local run on June 30, 2026
kept 500 old DB snapshots alive. Commit latency grew from about 0.33 ms near
100 writes to about 2.07 ms near 500 writes. The explicit post-commit `db`
clone was still only about 0.003-0.008 ms per snapshot at that scale, so the
visible problem is the commit/publish path copying and rebuilding resident
arrays, not the additional retained handle container by itself.

The batch-1 and mixed curves point at the same bottleneck: each successful
connection transaction produces a new immutable `DB` value by copying the datom
log plus `current`, `eavt`, `aevt`, `avet`, and `vaet` index arrays. That is
semantically correct and keeps DB values immutable, but it is not the final
durable write representation. The next storage implementation work should move
`DB` internals toward shared immutable index storage or chunked index pages so a
new DB value can share old index pages and only add/replace the affected tail
or page set. Special reportless fast paths are not the desired fix; transaction
reports, listeners, and `db` snapshots still need correct immutable values.

## Active Storage Architecture Work

The current SQLite path is correct, but the known follow-up is architectural
rather than a small local optimization:

1. Replace whole-array DB/index ownership copies with shared immutable DB/index
   storage or chunked index pages.
2. Preserve ordinary immutable DB snapshot semantics: reports, listeners, host
   handles, and `db` values must still see stable values after later writes.
3. Keep SQLite as the durable log, metadata, and page/chunk store.
4. Add chunk-backed read cursors over the persisted page loader for `eavt`,
   then extend to `aevt`, `avet`, and `vaet`. The first cursor exists for all
   four persisted indexes, and the index-view boundary can wrap those cursors.
   The next step is to make reopened DB snapshots choose those cursor-backed
   views instead of rebuilding resident arrays for normal access.
5. Broaden direct durable write publication from add/retract/retract-entity/CAS
   source-overlay commits to the full ordinary source-resolvable transaction
   surface, appending datom rows and persisted index roots from
   source/write-state metadata without building a resident post-commit `DB`.
6. Scale `bench/write_bench.kvist`, MusicBrainz reopen/query, and
   snapshot-heavy loops against this representation.

Special reportless fast paths are not the desired fix. They would make the
benchmark look better while dodging the core requirement that Vev DB values are
immutable values applications can pass around.

The first resumed storage-copy cleanup removed an unnecessary full `DB` clone
from registered/native transaction-function paths. Those paths now follow the
ordinary live transaction ownership shape: the pre-transaction DB becomes the
successful report's `db-before`, and the connection moves to the newly
published `db-after`. This is not the shared-index representation yet, but it
keeps all transaction entrypoints on the same publish boundary before the DB
layout changes.

The first shared-index building block is now present as `Shared-Int-Index`.
It stores index entries in retained immutable chunks, can append new chunks
while sharing old chunks, and has tests for releasing old and new handles
independently. It is not yet wired into `DB.eavt`, `DB.aevt`, `DB.avet`, or
`DB.vaet`; the next storage step is to add a DB-index wrapper around this
chunked representation and move resident index publication to that boundary.
That wrapper now exists as `Shared-DB-Int-Indexes`, and the existing
`DB-Index-View` abstraction can read from it. The remaining step is changing
transaction publication to store or retain these shared indexes as part of DB
snapshots, rather than only materializing owned resident arrays.
`DB-Read-Source` can also wrap a resident datom log with shared chunked index
views, and a source-backed query test now runs EDN text over that source. This
is the first executable query path over the new in-memory shared-index
representation. Currentness for that path now also reads the shared chunked
`current` index, so add/retract history is filtered without reaching back to
the resident `DB.current` side table.
Datoms can now also be stored in `Shared-Datom-Log` retained chunks. The
source-backed query path has a variant that reads both datoms and indexes from
shared chunks, so simple data-clause queries can execute without a resident
`DB` pointer for materialization. `Shared-DB-Snapshot` packages those shared
datom and index chunks into one retained immutable DB-value handle; tests retain
one snapshot, release the original handle, and continue querying through the
retained value.
Appended shared snapshots can now share the old datom-log chunks and append
only new datom chunks. Shared int indexes also retain old chunks when the
post-transaction index keeps the old index as an exact prefix; merged or
reordered indexes still rebuild for correctness. Replacing that fallback with
range/page sharing is the next Batch 4 implementation step.
`Shared-Conn` now provides the first connection-shaped publish path over those
shared snapshots. It still applies transactions through the existing resident
connection, then publishes a new retained `Shared-DB-Snapshot` from the previous
snapshot and the post-transaction DB. That is an intermediate architecture
step, not the final storage model: the next version should build shared chunks
directly at the commit boundary instead of adapting from resident arrays after
the fact. `bench/write_bench.kvist --workload shared-snapshot-heavy` measures
that path separately from SQLite-backed `snapshot-heavy`; a local batch-1,
100-write sample showed the shared path faster. Shared publication now also
uses append-only/new-entity facts from the transaction report to retain
`current` and `eavt` directly when those indexes are known prefixes.
`eavt-entity-starts` is a resident DB build/index maintenance side table, not
part of shared immutable snapshots. A local batch-1, 500-write sample with chunk
size 64 ended at
about 0.323 ms commit latency. The remaining increase comes from indexes that
still rebuild or scan merged/reordered resident arrays.
`Shared-Int-Index` also has a tested same-offset page-sharing constructor for
retaining unchanged chunks while replacing changed pages. It is currently a
building block, not the default publish fallback: comparing every old page in
the append-heavy workload cost more than exact-prefix-or-rebuild. The durable
storage direction is therefore merge-aware page publication, where the merge
knows which pages are unchanged instead of rediscovering it by scanning.
Append-only shared publication now has that first merge-aware path for the
logical int indexes. It streams sorted new datom indexes together with old
shared chunks and retains any old chunk copied contiguously by the merge. This
is a memory/copy architecture step, not a finished latency win: the current path
still builds resident indexes first, and the shared merge builder has per-value
overhead that should be reduced when publication moves fully to shared chunks.
The first overhead reduction batches the tail of added indexes instead of
pushing every remaining added value individually.
The merge builder also emits full chunk-sized appended slices directly when the
pending buffer is empty, avoiding per-value pending-buffer pushes for those
runs.
`Shared-Tx-Report` now preserves transaction report DB values as retained shared
snapshots. That lets a report's `db-before` and `db-after` be queried after the
connection has advanced, without cloning resident DB arrays for those report
values.
`Store-DB` can now also wrap a retained shared in-memory snapshot, not only a
SQLite snapshot. That keeps the host-facing immutable DB handle direction
storage-neutral: the same `q-result-store-db-*` wrappers can query persisted
snapshots and shared in-memory snapshots through `DB-Read-Source`.
`q-result-store-db-prepared-with-input-text` is the prepared-query-with-inputs
variant used by the ABI direction, so durable host DB handles can execute
ordinary prepared queries without resident DB rebuild once the ABI wrapper
build is unblocked.
`Store-Conn` is also now storage-neutral at the connection boundary. The
default `open-store` functions still create SQLite-backed stores, while
`create-shared-store` creates the in-memory shared-index publish path. Both use
the same `store-db`, `q-result-store-*`, `transact-store-report-text`, and
`close-store` entry points, so host bindings can move toward one DB-handle shape
instead of separate resident, SQLite, and shared APIs.
`Store-DB` can also render query and pull values through `DB-Read-Source`.
This lets storage-neutral callers, including the CLI, print parsed query results
from retained SQLite/shared snapshots without reopening or reaching through a
resident `DB` field just for value rendering.
Retained SQLite `Store-DB` handles also own their reopened snapshot handle, so
host-facing DB values can be closed independently from the store that produced
them while still reading the original durable basis.
`db-with-store-db-text` provides the current immutable transaction bridge for
storage-neutral DB handles. For source-resolvable shared and SQLite snapshots,
it now returns another source/overlay `Store-DB` value and leaves the original
durable/shared snapshot untouched. Unsupported or compatibility-only shapes can
return a public failed report or, for the legacy no-error helper, retain the
original DB value; they do not silently publish a resident clone. Common
nested-map, cardinality-many, lookup-ref, upsert, CAS, retract, and source
transaction-function DB-value paths stay source-backed.
The write benchmark now has a `shared-store-db-heavy` workload over this same
storage-neutral connection/snapshot API. It provides the current host-handle
acceptance check for the shared publish path, and early numbers match the raw
shared snapshot workload closely, so the next optimization should target direct
shared chunk publication rather than another host wrapper bypass.
It also has `shared-snapshot-heavy-direct`, which keeps the direct shared-log
merge experiment measured. That experiment is still slower than the default
resident-comparison adapter, so the next storage step remains a real transaction
publish plan that produces per-index merge/tail inputs directly.
Append-only transaction reports now carry the first version of that boundary as
a `Tx-Publish-Plan`. It owns the ordered appended EAVT/AEVT/AVET/VAET tails
consumed by shared index publication, so shared storage consumes
transaction-owned publication metadata instead of deriving a storage-side plan
after the fact. A local batch-1, 300-write retained-snapshot run ended near
0.268 ms commit latency for the default shared path and 0.267 ms for
storage-neutral `Store-DB`. The remaining storage work is to avoid duplicate
sorting/materialization while building both resident indexes and the publish
plan.
Resident append-only DB construction now consumes the same `Tx-Publish-Plan`
tails used by shared publication, so appended EAVT/AEVT/AVET/VAET tails are not
sorted again just to build the resident post-commit DB. A local batch-1,
300-write retained-snapshot run improved to about 0.155 ms commit latency for
the default shared path and 0.154 ms for storage-neutral `Store-DB`; direct
shared-log comparison remains slower at about 0.259 ms. The next storage
architecture target is therefore not more duplicate-tail sorting cleanup, but
removing the remaining resident post-commit DB dependency from append-only
shared publication.
Append-only shared index merges now compare old index entries through
`db-before.datoms` plus new entries through `report.tx-data`, rather than
comparing through the resident post-commit `after.datoms` array. The merge is
still the same generic chunk-retaining shared-index algorithm, but it no longer
depends on the post-commit resident datom log as its comparison source. A local
batch-1, 300-write retained-snapshot run ended near 0.151 ms commit latency for
the default shared path and 0.145 ms for storage-neutral `Store-DB`; direct
shared-log comparison remains slower at about 0.261 ms. The next storage
architecture target is to keep shrinking the resident transaction application
path so shared publication can eventually be driven directly from resolved tx
ops and report metadata.
Append-only shared snapshot publication now has a report-only helper:
`shared-db-snapshot-with-append-tx-report`. The outer compatibility helper still
accepts a post-commit resident `DB` for non-append fallback publishing, but
successful append-only commits no longer pass that `DB` into the shared
publication helper. `Shared-Conn` now branches at the call site too, so
append-only reports go directly to the report-only helper and do not pass the
post-commit resident `DB` into shared publication at all. A local batch-1,
300-write retained-snapshot run stayed in the same range: about 0.146 ms commit
latency for the default shared path and 0.145 ms for storage-neutral
`Store-DB`; direct shared-log comparison remains slower at about 0.267 ms.
Transaction application now has an explicit `Tx-Apply-Result` boundary.
`apply-resolved-ops-to-datoms` packages the emitted post-transaction datom
array, `tx-data`, tx id, append start index, append-only facts, and
`Tx-Publish-Plan` before the resident `db-after` indexes are built.
Append-only `Shared-Conn` transactions now resolve and apply tx data directly,
publish the next shared snapshot from `Tx-Apply-Result`, and only then build
the resident `db-after` needed for report/listener compatibility. Non-append
shared transactions still use the resident fallback snapshot adapter. A fresh
local batch-1, 300-write retained-snapshot run ended near 0.144 ms commit
latency for the default shared path, 0.140 ms for storage-neutral `Store-DB`,
and 0.261 ms for direct shared-log comparison.
`shared-conn-transact-report`, the retained shared report path used by
host-facing DB-value APIs, now follows the same direct apply-result publish
path instead of wrapping `shared-conn-transact` and then converting its resident
`Tx-Report` into a `Shared-Tx-Report`. It still builds the resident connection
DB after publishing because the current transaction resolver needs a resident
current DB for later tempid, unique, schema, lookup-ref, and transaction
function semantics. The remaining architecture work is therefore a
source-backed write resolver/current-state layer, not just another report
wrapper. A local rerun put both `shared-snapshot-heavy` and
`shared-store-db-heavy` near 0.146 ms commit latency, with the benchmark-only
direct shared-log path around 0.268 ms.
`Shared-Conn` now names that remaining dependency explicitly as
`Shared-Write-State`. Today it wraps the resident `Conn`, and shared writes
advance it through `shared-write-state-*` helpers instead of reaching through a
generic `.conn.db` field. This is intentionally a boundary refactor rather than
a performance shortcut: the next implementation can replace
`Shared-Write-State` internals with source-backed current/schema/unique state
while leaving shared snapshot publication and host DB handles alone. A local
batch-1, 300-write retained-snapshot sample stayed in the same range: about
0.150 ms commit latency for both `shared-snapshot-heavy` and
`shared-store-db-heavy`, with the benchmark-only direct shared-log path around
0.274 ms.
The first write resolver read has moved behind that boundary. Simple direct
shared tx-data now checks direct eligibility using cached `Shared-Write-State`
schema facts (`has-tuple-schema` and ref attrs), and only consults
`DB-Read-Source` when a ref value actually needs source-backed resolution.
Complex tx shapes still fall back to the existing resident resolver. This is
deliberately not a full source-backed transaction resolver yet, but it puts the
hot direct add/retract path on the new write-state API without forcing
per-commit source schema scans. A local rerun ended near 0.151 ms commit
latency for `shared-snapshot-heavy`, 0.146 ms for `shared-store-db-heavy`, and
0.259 ms for the benchmark-only direct shared-log path.
Source-stable lookup-ref writes also resolve through that boundary now. Simple
add/retract tx-data can resolve a lookup-ref entity or a ref-valued lookup-ref
value against `DB-Read-Source`. Same-transaction lookup attrs also resolve
through the write-state overlay when the lookup attr's unique schema fact has
already been emitted and the lookup target fact is an explicit entity add or
tempid entity add anywhere in the same transaction. If that tempid resolves
through a source-backed identity upsert, lookup refs see the upserted entity
without a resident intermediate DB, so common out-of-order lookup-ref writes no
longer need a resident fallback.
Tempid upserts through already-installed unique tuple attrs are also
source-backed for simple component facts and source-backed lookup-ref component
facts, plus value-tempid component facts whose target tempids resolve through
source-backed identity upserts: the shared write resolver reads tuple schemas
through `DB-Read-Source`, builds the same-tx tuple value, and resolves the
upsert target without rebuilding a resident intermediate DB.
Same-transaction tuple lookup refs use the same overlay for tuple component
facts, including component values written through lookup refs and tuple lookup
values that contain nested lookup-ref components, so a ref-valued lookup ref can
target a tuple identity introduced by the same transaction.
Scalar identity-upsert conflicts and conflicting unique tuple tempid upserts are
also detected on the source-backed write-state path when one tempid would
resolve to multiple existing entities.
Source-stable ident entity writes also use the same path: `:db/ident` entity
terms resolve through source-backed schema reads, while idents created in the
same transaction still fall back to the resident intermediate-tx-db resolver.
Simple `:db/current-tx` value writes resolve from `Shared-Write-State` as well,
so shared append-only commits can record the current transaction entity and
still render the expected tempid mapping in transaction reports.
Ordinary non-upsert tempid entity writes also resolve from `Shared-Write-State`
now. The shared resolver caches the next entity id, assigns repeated tempid
names consistently within the transaction, accounts for explicit entity ids in
the same tx, and falls back for unique attrs so upsert semantics stay on the
resident resolver until the general overlay exists. Simple value-tempid ref
writes now share that same assignment state, with current-tx value-tempids
resolved through the transaction report tempid mapping. Literal ref tempids
written as same-transaction string or negative-int ref values also resolve
through that shared assignment state, while missing value-only tempids stay on
resident fallback/error paths. Tempid upserts for
`:db.unique/identity` attrs now resolve through source-backed lookup-ref reads
before op emission; `:db.unique/value` stays on normal validation rather than
the upsert path. Source-backed `:db/retractAttr` and `:db/retractEntity`
expansion now reads current facts through `DB-Read-Source`, including component
recursion and incoming-ref cleanup, so those current-state reads no longer
force the resident resolver. Explicit-ID schema-only transactions also resolve
through the shared write-state path for common non-tuple schema installation;
mixed schema/data transactions and tuple schema changes still stay on resident
fallback. Registered transaction functions can now transact through a shared
connection and publish through the shared snapshot path. The DB-callback API is
kept for compatibility, and a source-callback API now passes `DB-Read-Source`
to callbacks so they can read transaction-local facts without receiving a
resident `DB`. This works for typed tx-data plus EDN text and prepared tx-data.
The source-callback path now uses a transaction-local `DB-Read-Source` overlay
at callback boundaries, so common current-fact callback reads do not build a
temporary shared snapshot. Host-visible immutable `with`/`db-with` over base
source-backed DB handles also publishes overlay DB values for the common
transaction shapes. The remaining source-callback DB-value work is exact
overlay-on-overlay chaining without flattening away per-transaction tx identity.
Transaction reports now include the transaction engine's datom append start
index plus append-only and ordered-new-entity publication facts. The shared
connection publish path uses those fields directly, instead of recomputing
append position and eligibility from the resident DB and emitted `tx-data`
after the resident transaction completes. This keeps the storage adapter
aligned with the transaction engine and is the first small boundary change
toward a real shared publish plan.
That path now goes through `shared-db-snapshot-with-tx-report`, which is the
explicit report-to-shared-snapshot boundary future direct shared publication
should replace internally.
Retained `Shared-Tx-Report` values preserve that append start and append-mode
metadata too, alongside their shared `db-before`/`db-after` snapshots.
The resident entity-range helper now uses the same `DB-Index-View` binary-search
shape as the source boundary instead of reading the `eavt-entities` /
`eavt-entity-starts` side table directly. The side table still exists as a
resident DB build/index maintenance detail, but ordinary entity range/existence
checks no longer require it.
The unused position-indexed resident helpers have also been removed, so
query-facing code no longer exposes `eavt-entity-starts` positions as an API
shape.

The direct datom append paths now also share the transaction engine's guarded
append-only index builder when the appended datoms are simple additions that do
not touch validation schema and do not repeat current or in-batch facts.
Retractions, schema datoms, repeated facts, and unkeyable values still fall back
to full DB/index rebuilds. This keeps `db-with-datoms`, `with-datoms`, and
`transact-datoms` on the same incremental-index path used by ordinary
append-only transactions without changing their correctness model.
In the shared publication path, append-only `current` indexes are now extended
directly from the committed datom range instead of copied from the resident
post-commit `current` array. This is still an intermediate architecture because
the transaction engine builds a resident DB first, but it removes one index from
the resident-index adaptation step.
Ordered new-entity `eavt` publication follows the same direction: it builds the
appended tail by sorting only the new datom indexes in EAVT order and appending
that tail to the retained shared base, instead of slicing the resident
post-commit `eavt` array.
For general append-only shared publication, the shared datom log is now extended
from `report.tx-data` instead of slicing the resident post-commit datom array.
The ordered new-entity `eavt` tail now also uses the appended `report.tx-data`
slice plus the report start index as its datom source, so that path no longer
needs the resident post-commit datom log for EAVT publication.
The shared `eavt`, `aevt`, `avet`, and `vaet` merge builders now compare old
entries through `db-before.datoms` and new entries through `report.tx-data`.
That removes the post-commit resident datom log as their comparison source, but
shared publication still starts from a resident transaction report today. The
next structural step is to publish shared datom/index chunks directly from the
transaction application result, instead of adapting after a resident `db-after`
has already been built.
`Shared-Datom-Log` now carries per-chunk start offsets and uses binary search
to find the chunk for a datom position. This keeps retained/appended partial
chunks addressable without scanning through all previous chunks and gives the
next direct shared-index merge attempt the right lookup primitive.
That direct merge was retried after adding chunk starts and an estimated-chunk
fast path. It was still slower than the current resident-comparison merge in
the small retained-snapshot benchmark, so it is not the default hot path. The
useful retained result is indexed shared datom lookup; the next production
storage step is to publish shared datom/index chunks directly from the
transaction application path, instead of adapting from a fully built resident
`DB` and trying to make that adapter ever more clever.

SQLite rollback cleanup now also follows the live-report ownership rule. When
an in-memory transaction succeeds but SQLite append fails, the wrapper restores
the previous DB and cleans the successful report as a live connection report so
`db-after` is not freed twice.

## SQLite Backend Shape

SQLite is the first production durable backend.

Initial schema direction:

- database metadata table with format version and current basis tx
- append-only transaction table
- append-only datom table storing `e`, `a`, typed value payload, `tx`, and
  `added`
- persisted logical index root/chunk tables for Vev-owned index segments
- optional materialized current-datom table once commit/read costs need it

Current implementation status and later order:

1. Keep storage-level metadata inspection/replay APIs focused on concrete tools
   and benchmarks.
2. Treat persisted logical index roots/chunks as the normal durable read shape.
   Opening a durable store should load root metadata and expose source-backed
   `Store-DB` handles, not rebuild a resident DB from the datom log.
3. Continue reducing durable write publication cost. Normal direct
   `Store-Tx-Report` writes now publish lazy SQLite-backed `Store-DB` values,
   reuse existing persisted chunks where the index order allows it, and publish
   manifest-backed non-append roots for tiny source-backed commits. Current
   profiling shows the first chained-manifest slice moved the batch-1
   publication bottleneck substantially, and the SQLite store-report path now
   keeps current durable-log metadata cached, reuses prepared root/manifest
   statements, and builds manifest attr ranges from appended datoms when
   available. Small manifest delta runs now use entry-backed leaf chunks, and
   larger delta runs use parent chunks over entry-backed leaves. The current
   `sqlite-store-db-heavy --batch 1 --total 5000` gate is about
   `2135 writes/s`, with flat `open_before_ms` around `0.08ms/write` and
   `append_root_persist_ms` about `0.067ms/write` at 5000 writes.
4. Move repeated tiny commits toward a clearer page-delta/LSM-style index
   representation. The current packed-leaf/right-spine tree keeps append roots
   shallow, and chained manifests make non-append tiny commits cheap.
   Automatic foreground maintenance now performs bounded manifest compaction
   steps, so visible run count can stay small. The next representation work is
   making those bounded manifest roots broad-scan cheaply enough without
   requiring manual full compaction, not another local merge-root shortcut.
5. Keep `bench/write_bench.kvist` focused on public durable API shapes:
   `pure-store-report`, `pure-store-report-deferred`, snapshot-heavy, mixed,
   and MusicBrainz/Datomic-style durable query/reopen checks.

Non-goals for the first SQLite backend:

- making SQL rows the public data model
- query execution by translating Vev Datalog to SQL
- multi-backend abstraction before SQLite works well
- distributed client/transactor semantics

## Validation Workloads

MusicBrainz/Datomic workshop data is now the next validation workload. See
`docs/musicbrainz.md` for the active plan. It should validate that the current
in-memory and SQLite-backed paths preserve the same Datomic-shaped semantics
under realistic query, pull, schema, ident, and import pressure. Datalevin
`write-bench` remains the later durable-write comparison once the shared
immutable index-storage work resumes.
