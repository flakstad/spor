# Resident transaction resolution and planning profile

Status: pre-optimization root-cause report, 2026-08-27. Measurements are from
`87a948c9` plus profiling-only instrumentation, on the same machine and power
state. The Ro rows use two freshly generated disposable Ro demo databases and
the exact `set-semantic-checkbox!` shape through the public Kvist package.

## Result

The dominant Ro cost is repeated schema materialization during resolution and
planning. It is not EDN conversion, SQLite commit, required transaction
validation, provenance itself, or construction of the rich transaction report.

`append-source-overlay-op!` asks for cardinality twice and value type and unique
metadata once for each assertion. Each of those calls reaches
`db-read-source-schema-entity-for-attr`, which obtains every current
`:db/ident` datom and linearly searches the materialized result. The exact Ro
transaction performs 10 general schema lookups and 19 cardinality lookups.
Those 29 lookups account for 5.651 ms of its 5.881 ms planning median.

Lookup-reference resolution repeats the same pattern. Seven lookup-ref probes
account for 1.675 ms of the 1.733 ms resolution median. The resident write state
already contains the immutable unique-attribute projection required to validate
these scalar lookup refs, but the general source lookup validates uniqueness by
materializing and scanning schema again. Eligibility probes and final resolution
also repeat some of the same pure lookups.

## Exact Ro phase budget before optimization

100 warm samples:

| Phase | Median | p95 | Operations |
| --- | ---: | ---: | ---: |
| Public Kvist `transact-data` | 8.924 ms | 9.913 ms | 1 transaction |
| EDN parse | 0.036 ms | 0.048 ms | 1 value |
| Resolution | 1.733 ms | 1.857 ms | 8 resolved operations |
| lookup refs (inclusive) | 1.675 ms | 1.797 ms | 7 probes |
| tempid preparation (inclusive) | 0.246 ms | 0.258 ms | 2 tempids |
| Planning | 5.881 ms | 6.211 ms | 5 effective owned ops |
| current-fact reads | 0.232 ms | 0.279 ms | 9 reads |
| schema/value-type/unique reads | 2.278 ms | 2.369 ms | 10 reads |
| cardinality reads | 3.373 ms | 3.599 ms | 19 reads |
| normalization | 0.001 ms | 0.002 ms | 5 ops |
| ownership | 0.001 ms | 0.004 ms | 5 ops |
| Incremental `db-after` | 1.153 ms | 1.302 ms | 5 effective ops |
| Canonical append | 0.178 ms | 0.246 ms | 5 datoms |
| SQLite commit | 0.134 ms | 0.221 ms | 1 commit |

The inclusive resolution timers can overlap: tempid/upsert preparation invokes
lookup-ref resolution. Planning timers are accumulated around the individual
leaf operations and sum to within measurement noise of the enclosing phase.

## Initial scaling observations

All rows below use 100 warm samples. The synthetic small and large databases
have the same two-attribute schema; only current application data and history
differ. This isolates current-data scaling from schema-width scaling.

| Database/workload | Public median | Planning | Schema + cardinality | Current reads | `db-after` |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 attrs, 50 entities, append | 0.424 ms | 0.095 ms | 0.084 ms | 0.009 ms | 0.167 ms |
| 2 attrs, 50 entities, replacement | 0.574 ms | 0.258 ms | 0.167 ms | 0.087 ms | 0.268 ms |
| 2 attrs, 2,000 entities, append | 0.818 ms | 0.156 ms | 0.139 ms | 0.015 ms | 0.128 ms |
| 2 attrs, 2,000 entities, replacement | 2.140 ms | 0.516 ms | 0.319 ms | 0.196 ms | 1.318 ms |
| 2 attrs, 2,000 entities, four-fact Ro-like | 2.468 ms | 0.733 ms | 0.492 ms | 0.237 ms | 1.610 ms |
| Ro schema (227 idents), exact transaction | 8.924 ms | 5.881 ms | 5.651 ms | 0.232 ms | 1.153 ms |

The 12x planning difference between the synthetic four-fact shape and the exact
Ro shape is explained by schema width, not by operation count. Application
database size affects current-datom and delta-root work, while the broad schema
scans dominate the exact Ro transaction. A follow-up matrix separates schema
history, current size, lookup-ref count, provenance count, replacements, and
unique-attribute count.

## Planned invariant-preserving change

The optimized planner will consume a transaction-local view of the immutable
schema projection already associated with the resident database generation.
Cardinality, value type, ref, and unique metadata become O(1) lookups. Scalar
lookup refs whose uniqueness is already proven by that projection can use the
AVET source directly. Schema-changing transactions, incomplete projections,
tuple lookup refs, and an explicit test switch retain the full reference path.

The projection is derived metadata, never canonical state. It must be rebuilt or
invalidated after schema changes, `with`, reopen, or a generation change. The
transaction still performs current-datom, uniqueness, CAS, component, and schema
validation, and still commits canonical datoms before acknowledgement.

Raw reproduction output is produced by:

```sh
kvist build bench/kvist_transaction_boundary.kvist \
  --out build/bench/kvist-transaction-boundary
VEV_LIB=$PWD/build/lib/libvev.dylib \
  build/bench/kvist-transaction-boundary --samples 100 \
  --ro-public-db <disposable-ro-demo-1> \
  --ro-native-db <disposable-ro-demo-2>
```
