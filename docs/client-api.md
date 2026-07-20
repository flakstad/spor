# Client API Contract

VevDB clients follow Datomic semantics at their primary public boundary.
Host-language conventions may affect capitalization, error handling, and
resource management, but not the database model or query result shape.

## Reference model

Datomic Peer is the reference for an embedded VevDB process:

- a connection yields immutable DB values
- `transact` advances the connection and returns a report
- `q`, `pull`, `pull-many`, entities, and index APIs read DB values
- entities are lazy associative views tied to a single DB value
- `as-of`, `since`, and `history` derive immutable time views
- `sync` coordinates readers with a known basis
- `log` and `tx-range` expose transactions
- `tx-report-queue` exposes post-commit transaction reports

The remote Datomic Client API is useful corroboration, but it deliberately does
not provide the Peer entity interface. VevDB is embedded, so absence from the
Client API is not a reason to omit lazy entities.

VevDB also keeps intentional, documented conveniences. In particular,
DataScript-style named `listen`/`unlisten` helpers may coexist with the
Datomic-shaped transaction report queue. They are not aliases for Datomic
Peer's `add-listener`, which registers a one-shot completion callback on a
future.

## Public surface levels

Every exported operation belongs to one of these levels:

1. **Core** — the Datomic-shaped database API and necessary host-language
   lifecycle operations.
2. **Convenience** — a deliberate, documented helper such as
   `listen`/`unlisten` or a connection-accepting `q`.
3. **Advanced** — an explicitly named and separately documented performance or
   embedding API.
4. **Internal** — FFI handles, row/result machinery, prepared statements,
   column batches, parser representations, profiling counters, storage backend
   entry points, and native loading.

Internal machinery must not become public merely because the raw C ABI needs
it or because one wrapper uses it to implement the core API. The C ABI itself
is the portability layer and therefore intentionally remains broad. Safe host
clients should place advanced facilities in an `advanced`/`internal` namespace
or an unmistakably low-level type rather than mixing them into the ordinary DB
API.

The supported constructors are `create-conn`/`createConn`/`CreateConn` (or the
idiomatic equivalent) for in-memory use and `connect` for durable use. The
redundant `open_memory` family and public SQLite-specific constructors are not
part of host-client APIs. SQLite remains an implementation detail.

## Core operation set

Host-language spelling aside, the ordinary client should converge on:

| Area | Operations |
| --- | --- |
| Connections | `create-conn`, `connect`, `db`, `transact`, `sync`, lifecycle |
| Query | `q`, `query` request-map form where appropriate |
| Entities | `entity`, `entity-db`, `touch`, map/key lookup, `entid`, `ident` |
| Pull | `pull`, `pull-many` |
| Indexes | `datoms`, `seek-datoms`, `rseek-datoms`, `index-range`, later `index-pull` |
| Immutable writes | `with`, `db-with` |
| Time | `as-of`, `since`, `history`, `basis-t`, `next-t`, coordinate accessors |
| Log | `log`, `tx-range` |
| Reports | `tx-report-queue`, `remove-tx-report-queue` |

`listen`/`unlisten` are approved convenience operations. Prepared queries are
an approved advanced facility: callers may explicitly compile a query once and
pass that value to the normal `q` operation for repeated execution. Prepared
execution must preserve exactly the same inputs and Datomic `:find` result
shape as ad hoc `q`; it must not force callers into row handles, statements, or
column batches. Bulk ingest may also remain advanced, but should not crowd the
core namespace or type.

## Current cleanup work

The following is remaining work, not a statement that every listed symbol will
be deleted:

| Client | Core gaps | Surface cleanup |
| --- | --- | --- |
| Clojure | transaction report queue; later `attribute`, `db-stats`, `index-pull`, filters, `qseq` | retain `prepare` as advanced input to `q`; move row/column/result, profiling, parser, builder, raw-text, and storage diagnostics out of `vev.core`; retain approved helpers |
| Java | Datomic-shaped report queue and a tighter entity/map experience | retain prepared queries as advanced inputs to shaped query execution; separate the small ordinary API from FFM loading, statements, result sets, columns, builders, parser and profiling machinery |
| Kvist | high-level entity, identity/index access, pull-many, sync, report stream | retain prepared queries with shaped results; keep generated/runtime and typed performance helpers outside the small `vev_app` facade |
| Python | identity/index access, sync/log/report stream | retain prepared queries with shaped results; hide `Library`, handles, statements, result/column types, parser and builders from the ordinary import surface |
| Node | entity, identity/index access, pull-many, immutable writes, sync/log/report stream | retain prepared queries with shaped results; keep native-addon handles, prepared-row execution, and text/raw result paths internal |
| Go | identity/index access, sync/log/report stream | retain prepared queries with shaped results; split the safe core/advanced API from statements, row/column batches, parser and builders |
| Rust | identity/index access, sync/log/report stream | retain prepared queries with shaped results; complete the planned `vevdb` safe crate / `vevdb-sys` raw split and keep row/column and statement types out of the core prelude |
| Odin | entity, pull/pull-many, indexes, immutable writes, sync/report stream | add prepared queries as inputs to shaped `query`; expose only overload sets and high-level values from the normal package, making overload implementation and raw ABI details private where Odin permits |
| C | none as a portability boundary | retain the broad ABI, but distinguish stable core functions from advanced/raw functions in documentation |

## Primary query

- The primary operation is named `q` or `query`.
- It accepts an immutable DB value; accepting a connection as a convenience is
  allowed when the client takes a fresh snapshot for the call.
- In-memory and durable storage use the same operation.
- Query inputs are values, or an EDN encoding where the host wrapper has not
  yet exposed typed inputs.
- The result follows `:find`:

| Find form | Result |
| --- | --- |
| `:find ?x ?y` | set of tuple values |
| `:find [?x ...]` | collection |
| `:find [?x ?y]` | tuple or nil |
| `:find ?x .` | scalar or nil |

Return maps produce maps inside the relation or collection selected by the
find form.

The host representations are the natural equivalents: Clojure sets/vectors,
Java `Set`/`List`, JavaScript `Set`/arrays, Python sets/tuples/lists, and the
corresponding tagged value variants in Go, Rust, and Odin.

## Advanced query APIs

Prepared statements, row handles, column batches, visitors, streaming, and
profiling are valid lower-level facilities. Their names must make that
distinction explicit; their row-oriented implementation must not leak into the
primary `q`/`query` API.

The C ABI intentionally retains these primitives because it is the portability
and performance layer. Host clients should use the owned shaped-query value
functions for their primary API and the result-handle functions for advanced
prepared or streaming work.
