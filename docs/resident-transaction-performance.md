# Resident durable transaction performance

This change optimizes small transactions on a long-lived resident durable
connection without changing VevDB's Datomic-shaped transaction model.

## Root cause

`apply-resolved-ops-to-datoms` already had a specialized append-only path.
Cardinality-one replacement, explicit retraction, and `retractEntity` instead
called `build-db` on the complete datom log. That re-sorted current, EAVT,
AEVT, AVET, and VAET, rebuilt entity ranges, and reconstructed schema caches.
The cost therefore scaled with resident history even when the transaction
changed only one fact.

The durable raw-resident path also serialized a complete derived immutable root
for every transaction, even though the root format supports small immutable
delta runs. This was substantially more derived work than the transaction
changed.

## Incremental DB construction

Transactions with at most 64 effective datoms use the incremental path when
they do not modify schema. Schema attributes include `:db/ident`,
`:db/valueType`, `:db/cardinality`, `:db/unique`, `:db/tupleAttrs`, `:db/index`,
`:db/fulltext`, and `:db/isComponent`; any such datom retains the full rebuild
reference path.

The path preserves these invariants:

- The datom log is immutable and append-only.
- EAVT, AEVT, AVET, and VAET are history indexes. They merge only the new log
  positions and never remove a retraction's historical position.
- `current` removes the prior same fact and appends only effective assertions.
- EAVT entity ranges are rebuilt from the exact merged EAVT order.
- Non-schema transactions clone the unchanged schema caches.
- Every array and cache in `db-after` is independently owned. Later
  transactions cannot mutate a retained `db-before` or `db-after`.
- `with`, direct datom application, and live `transact` use the same selector
  and transaction semantics.

The full path remains available internally for deterministic differential
testing and benchmark comparison.

## Durability and derived roots

The SQLite transaction still synchronously inserts the transaction row,
canonical datoms, transaction metadata, and any full-text rows, then commits
before returning. A separate connection can immediately reconstruct the new
basis from the last immutable checkpoint plus the committed novelty tail.

Raw resident persistence now publishes four small immutable delta runs against
the prior root instead of serializing the complete DB indexes. Its public root
basis therefore still advances on every raw transaction. StoreReport resident
transactions retain their existing checkpoint-plus-novelty behavior. Both
representations read the same canonical log and total index orders. Compaction
and automatic checkpoint policy remain derived maintenance; no user
transactions are batched and acknowledgement is not asynchronous.

Resident connections cache the canonical-write and index-write prepared
statement sets and finalize them when the connection closes.

## Opt-in phase profile

Profiling is disabled by default. A disabled connection holds a zeroed profile;
phase boundaries perform only a nil/enabled branch and do not call the clock.

```clojure
(reset-store-tx-phase-profile! store)
(let [report (transact-store-report-text store tx-text)
      profile (store-tx-phase-profile store)]
  ...)
(disable-store-tx-phase-profile! store)
```

The corresponding SQLite-connection functions are
`reset-sqlite-tx-phase-profile!`, `sqlite-tx-phase-profile`, and
`disable-sqlite-tx-phase-profile!`. The profile reports parsing, resolution,
validation, cardinality/retraction planning, `db-after`, TxReport
construction/ownership,
canonical append, derived bookkeeping, and SQLite commit. It also records
effective `tx-data` datoms and append/incremental/full DB-path counts.

## Same-machine profile

The following result used the deterministic `ro-like` workload, 30 measured
transactions, and a 2,000-entity/4,000-application-fact resident database.
Both modes used the same binary, storage schema, prepared-statement behavior,
durability policy, and bootstrap-root/novelty persistence. `full` changes only
the `db-after` selector. Latency is measured with profiling disabled; phase
values come from a second identical pass, so they need not sum exactly to the
reported median. This workload submits structured `Tx-Data`, making parsing
inapplicable (zero); the text transaction entry points profile parsing too.

| mode | median | p95 | effective datoms | resolution | validation | planning | db-after | TxReport/ownership | canonical append | derived | commit |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| full rebuild | 17.44 ms | 21.39 ms | 6 | 0.012 ms | 0.178 ms | 0.661 ms | 16.51 ms | 0.002 ms | 0.194 ms | 0.422 ms | 0.837 ms |
| incremental | 3.24 ms | 6.42 ms | 6 | 0.006 ms | 0.160 ms | 0.623 ms | 1.25 ms | 0.002 ms | 0.094 ms | 0.262 ms | 0.933 ms |

The original Ro observation of roughly 8.5–9.9 ms was made on a different
database shape, so it is context rather than an apples-to-apples baseline. The
same-binary differential above isolates the eliminated full rebuild.

The existing committed `storage_amplification.py` benchmark also improved after
removing the two unused canonical-log indexes. This comparison uses the supplied
same-machine baseline and one final run of the unchanged workload shapes:

| shape | before/transaction | after/transaction | change |
| --- | ---: | ---: | ---: |
| 1000×1 assertion | 3.07 ms | 2.81 ms | -8.4% |
| 200×5 assertions | 5.96 ms | 5.64 ms | -5.4% |
| 167×6 assertions | 7.80 ms | 6.84 ms | -12.3% |
| 125×8 assertions | 10.84 ms | 10.19 ms | -6.0% |

## Remaining costs

Incremental merge still copies the flat native index arrays needed by a raw
resident `DB`; it is linear in resident index size, but substantially cheaper
than sorting and reconstructing the whole database. StoreReport's chunked
snapshots share untouched chunks and avoid that flat-copy model.

`retractEntity` resolution can dominate on a larger graph because it must
discover all entity facts and recursively plan component retractions. SQLite
commit latency remains dependent on the filesystem and WAL state. Neither cost
is hidden by relaxed durability.

The follow-up [resolution and planning
work](transaction-resolution-planning-profile.md) removes repeated full-schema
materialization from source-backed resident transactions. On the exact Ro
schema the final checked run reduces resolution from 1.733 ms to 0.160 ms and
planning from 5.881 ms to 0.467 ms. At that point immutable current-index and novelty-root
work, rather than schema lookup or SQLite commit, is the main size-dependent
cost.

## Storage consequences

Canonical tables and serialized datom values are unchanged. SQLite schema
metadata advances from version 1 to version 2 and drops two rebuildable,
unreferenced SQL indexes: `vev_datoms_aevt` and text-valued `vev_datoms_vaet`.
The retained direct indexes cover log position, EAVT point/covering access,
AVET, and ref-entity VAET access. Existing stores migrate in place; reopen,
history, as-of, queries, and public index order continue to derive from the
same canonical log and immutable roots.
