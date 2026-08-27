# Resident transaction resolution and planning

Status: implemented and verified, 2026-08-27. The baseline is `87a948c9`
plus profiling-only commit `78f7f516`. All Ro measurements use independently
generated disposable demo databases and the exact
`set-semantic-checkbox!` transaction through the public Kvist package.

## Result

The final checked exact warm Ro transaction fell from 8.924 ms median /
9.913 ms p95 to 2.104 ms / 3.726 ms on freshly generated disposable
databases. Resolution fell from 1.733 ms to 0.160 ms, and planning from
5.881 ms to 0.467 ms. A separate deep 100-sample phase run measured
1.830 ms / 2.471 ms, 0.150 ms resolution, and 0.449 ms planning. Both runs
remain below the checked 4 ms / 6 ms public and 0.5 ms / 1 ms phase budgets.

No EDN, C, Odin, or Kvist transaction semantics changed. A successful return
still follows the synchronous SQLite commit, exposes the same rich report, and
retains exact immutable `db-before` and `db-after` values.

## Root cause

`append-source-overlay-op!` asked for cardinality twice and value type and
unique metadata once for each assertion. Each request reached
`db-read-source-schema-entity-for-attr`, materialized every current
`:db/ident` datom, and linearly searched the result. The exact Ro transaction
made 10 general schema lookups and 19 cardinality lookups. These 29 lookups
accounted for 5.651 ms of its 5.881 ms planning median.

Lookup-reference resolution repeated the same work. Seven lookup-ref probes
accounted for 1.675 ms of the 1.733 ms resolution median. The write state
already held unique/ref subsets, but source-created states marked that cache
incomplete and had no value-type projection. General scalar lookup-ref
resolution therefore rescanned schema to prove uniqueness before doing the
indexed AVET lookup. Existing transaction-local resolution maps avoided some
duplicate probes, but could not remove this repeated schema reconstruction.

This answers the difference from the earlier synthetic Ro-like benchmark: it
was schema width, not provenance or operation count. The synthetic schema had
two attributes; Ro had 227 current idents. Required current-value checks were
only 0.232 ms, validation was negligible, and SQLite commit was 0.134 ms.

## Exact before and after phase budget

Each column is the median of 100 warm samples. Count columns are identical
before and after; the change removes redundant work rather than checks.

| Phase | Before | After | Operations |
| --- | ---: | ---: | ---: |
| Public Kvist `transact-data` | 8.924 ms | 1.830 ms | 1 transaction |
| EDN parse | 0.036 ms | 0.039 ms | 1 value |
| Resolution | 1.733 ms | 0.150 ms | 8 generated operations |
| lookup refs, inclusive | 1.675 ms | 0.087 ms | 7 probes |
| tempid preparation, inclusive | 0.246 ms | about 0.02 ms | 2 tempids |
| Planning | 5.881 ms | 0.449 ms | 5 resolved additions |
| current-fact reads | 0.232 ms | 0.240 ms | 9 reads |
| schema/value-type/unique reads | 2.278 ms | 0.002 ms | 10 reads |
| cardinality/replacement work | 3.373 ms | 0.204 ms | 19 reads/checks |
| normalization | 0.001 ms | 0.001 ms | 5 operations |
| ownership | 0.001 ms | 0.001 ms | 5 operations |
| Incremental `db-after` | 1.153 ms | 1.256 ms | 6 `tx-data` datoms |
| Canonical append | 0.178 ms | 0.199 ms | 6 `tx-data` datoms |
| SQLite commit | 0.134 ms | 0.142 ms | 1 commit |

Inclusive resolution subphases overlap when tempid/upsert preparation invokes
lookup-ref resolution. Planning leaf timers are accumulated around the actual
operations and sum to within measurement noise of the enclosing phase.

Phase instrumentation remains opt-in. Disabled connections take only the
existing nil/enabled branches and do not call the clock. The public profile
value now reports lookup-ref, ident, tempid, current-tx, generated-op,
current-fact, schema, cardinality, unique, normalization, retraction, and
ownership times and counts.

## Scaling matrix

The following optimized rows use 100 warm samples. `wide-schema` adds 250
unrelated attributes. `schema-churn` preserves the same current schema but
adds 200 historical schema-document replacements. `large` has 2,000 entities;
the other synthetic databases have 50.

| Database/workload | Public median / p95 | Resolution | Planning | Current | Schema | `db-after` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| small/append | 0.333 / 0.376 ms | 0.001 ms | 0.019 ms | minimal | about 0 | 0.165 ms |
| small/replacement | 0.469 / 0.578 ms | 0.001 ms | 0.166 ms | about 0.08 ms | about 0 | about 0.28 ms |
| small/CAS | 0.496 / 0.607 ms | 0.080 ms | 0.167 ms | indexed | about 0 | about 0.27 ms |
| small/explicit retract | 0.422 / 0.563 ms | 0.001 ms | 0.048 ms | indexed | about 0 | about 0.23 ms |
| small/retractEntity | 0.544 / 0.795 ms | 0.018 ms | 0.026 ms | indexed graph walk | about 0 | about 0.43 ms |
| small/Ro-like | 0.810 / 1.034 ms | 0.011 ms | 0.279 ms | indexed | about 0 | about 0.53 ms |
| large/replacement | 1.842 / 2.069 ms | 0.001 ms | 0.383 ms | 0.198 ms | about 0 | about 1.30 ms |
| wide-schema/replacement | 0.785 / 1.048 ms | 0.001 ms | 0.209 ms | 0.108 ms | 0.001 ms | about 0.51 ms |
| schema-churn/replacement | 0.573 / 0.714 ms | 0.001 ms | 0.187 ms | 0.092 ms | about 0 | about 0.31 ms |
| exact Ro/no provenance | 1.554 / 1.753 ms | 0.099 ms | 0.365 ms | indexed | 0.002 ms | 0.843 ms |
| exact Ro/provenance | 2.104 / 3.726 ms | 0.160 ms | 0.467 ms | 0.240 ms | 0.002 ms | 1.256 ms |
| exact Ro/resolved entity ids | 1.905 / 2.154 ms | 0.024 ms | 0.457 ms | indexed | 0.002 ms | 1.212 ms |

The resolved-id row is diagnostic only. It shows that lookup refs now cost
roughly 0.1 ms, so changing Ro's public transaction shape would provide little
benefit. Provenance is handled as ordinary transaction-entity facts: removing
it saves the normal resolution, planning, append, and immutable-index cost of
three facts, but there is no provenance-specific branch.

The deterministic registered transaction-function benchmark uses a separate
source-backed durable store for timed and profiled passes so the 128-transaction
checkpoint threshold cannot change execution mode mid-pass. One function
expands to a cardinality-one replacement plus `:db/txInstant` and measures
6.154 ms / 8.186 ms end to end, 0.062 ms resolution/expansion, 0.191 ms
planning, and three effective datoms. Its remaining cost is source snapshot
publication, not the resolution/planning change.

The matrix demonstrates the complexity split:

- schema width and historical schema churn no longer multiply per-operation
  planning cost;
- scalar unique lookup refs use one indexed AVET probe after O(1) metadata
  proof;
- current entity/attribute checks remain indexed, but immutable index/root
  copying grows with current application data and novelty depth;
- retractEntity still scales with the entity/component graph it must inspect;
- transaction functions pay their required callback and expansion work before
  the same general planner.

Per-phase allocation counts were not added to the timed profile because the
tracking allocator materially changes these sub-millisecond measurements.
Ownership is instead checked in dedicated `--track-memory` runs and the
compiler ownership audit.

## Architecture

`Shared-Write-State` now owns one complete immutable planning projection for
its database generation:

- attribute to value type;
- cardinality-many attributes;
- ref attributes;
- unique attributes and unique-identity attributes.

The projection is built from the snapshot's current schema facts when a source
write state is created. Planning cardinality, value type, and uniqueness are
then O(1) map/set reads. A scalar lookup ref can go directly to AVET when the
complete projection has already proven its attribute unique. Tuple values,
schema-changing transactions, incomplete metadata, and an internal forced
reference switch use the original general resolver/planner.

Candidate resident transactions borrow the live generation's immutable schema
projection. On a failed candidate they release only their own listener and
snapshot retains. After a successful SQLite commit, ownership of the projection
is transferred once to the installed candidate before the old connection is
deleted. Schema transactions detach with copy-on-write before the first schema
mutation and own that new projection even if later persistence rolls back.
This removes a deep schema clone per small transaction without introducing a
borrowed-lifetime or failure-atomicity window.

The existing transaction-local resolution index remains responsible for pure
same-call memoization. The new projection does not memoize transaction results
across generations and is not a second schema source of truth.

## Invariants and fallback

- Canonical datoms and SQLite tables remain authoritative. The projection is
  rebuildable derived metadata and changes no storage format.
- A successful transaction commits canonical rows before installing the new
  live candidate and before returning.
- A schema mutation rebuilds metadata from the new immutable snapshot.
- Reopen, `with`, source snapshots, and multiwriter generation reloads create
  metadata from their own basis; no cache survives into a different basis.
- Current-fact, cardinality, uniqueness, CAS, component, tuple, and schema
  validation still run. Only their metadata source changes.
- Exact no-ops, retractions, transaction provenance, tempids, tx metadata, and
  report construction are unchanged.
- `db-before` and `db-after` retain independent immutable snapshot roots and
  remain valid through later transactions.
- `force-reference-planner` preserves the complete original path for
  deterministic differential tests.

There is no public API or storage-format consequence. The profile map gains
diagnostic keys only; clients that do not request profiling do no additional
timing work.

## Differential and system verification

The planner differential creates two independent shared source connections at
the same basis, forces the reference planner on one, and runs 120 deterministic
mixed transactions. It covers replacements, no-ops, cardinality-many
add/retract, lookup refs, refs, CAS success/failure, retractAttribute, and
retractEntity. It compares success/error, tx, exact tx-data, tx-meta, tempids,
bases, current datoms, EAVT/AEVT/AVET/VAET, and schema caches.

The full PBT run passed 46 properties and 9,200 checks. It includes durable and
resident differentials, identity/value uniqueness, tuples, components, schema
evolution, `with`, concurrent writers, reopen, history, and backup. The full
17-program Vev suite passed 781 tests. C ABI, Odin, Kvist package, multiwriter,
cross-process visibility, history, backup, and SQLite application smokes also
passed.

Ro commit `51d239d` was then verified in an isolated worktree with its Vev lock
temporarily pinned to `e6d5ce3b`. The complete `scripts/test.sh` passed,
including 67 store tests with memory tracking, both Ro PBT suites, reopen,
history/restore, checkbox semantics, and native engine/input tests. A freshly
built Ro passed `native-steady-latency-smoke.sh` at 8.018 ms average across
seven steady committed commands against a disposable database.

Focused planner, source-connection, retained-snapshot, reopen, and index tests
pass with memory tracking. A full `DurableApp` tracking experiment reports an
existing 45-allocation/618-byte test-harness baseline at both `78f7f516` and
this change; the optimization adds no delta. The ownership audit reports only
the project's existing conservative warnings plus expected warnings where it
cannot model the explicit conditional schema-cache transfer.

## Reproduction and budgets

Run the public synthetic matrix and checked boundary budget:

```sh
python3 bench/check_kvist_transaction_boundary.py --samples 100
```

Run the registered transaction-function row:

```sh
kvist build bench/durable_transaction_function.kvist \
  --out build/bench/durable-transaction-function
build/bench/durable-transaction-function --samples 100 --warmup 20
```

For exact Ro, generate two independent disposable demo stores, then run:

```sh
python3 bench/check_kvist_transaction_boundary.py \
  --no-build --ro-only --samples 100 \
  --ro-public-db <disposable-ro-demo-1> \
  --ro-native-db <disposable-ro-demo-2>
```

The exact checked budgets are 4,000 us median / 6,000 us p95 publicly,
500 us resolution median, and 1,000 us planning median. The benchmark also
reports effective `tx-data` datoms and every detailed phase time/count.
