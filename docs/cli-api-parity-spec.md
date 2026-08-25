# CLI API parity specification

Status: proposed

This document specifies the work required to make `vevdb` a complete textual
frontend to VevDB's mature Kvist and Clojure APIs. It describes the target
surface; it does not describe the CLI that ships today.

## Goal

Anything a caller can do with VevDB's semantic database API from Kvist or
Clojure must also be expressible through the CLI when its inputs and observable
results can cross a process boundary as data.

In particular, the CLI must expose more than connection-level transact, query,
and pull. It must preserve VevDB's model of immutable database values so that a
caller can:

- select current, historical, and filtered database values;
- apply speculative transactions without changing the store;
- compose database-value transformations with query, pull, entity, schema, and
  index operations;
- inspect transaction reports and transaction history;
- perform the durable bulk and maintenance operations exposed by the primary
  APIs; and
- compose several operations in one process when an intermediate value cannot
  be serialized, such as a DB, prepared query, or transaction report handle.

The CLI is intended for humans, scripts, and agents. Its default interface must
remain shell-friendly, but parity must not depend on scraping human-readable
text.

## Normative language

The words **must**, **should**, and **may** describe requirements, recommended
behavior, and optional behavior respectively.

## Sources of truth

Parity is measured against the union of the public VevDB operations in:

- `clients/kvist/vev.kvist`;
- `clients/clojure/src/vev/core.clj`;
- `compat/datomic-peer-api.edn`; and
- the portable semantic operations in `include/vev.h`.

`compat/datomic-peer-api.edn` remains the authority for intentional differences
from Datomic. A new `compat/cli-api.edn` manifest must be added with the
implementation. It must name every operation in the two primary APIs and give
it one of these dispositions:

- `:command`: directly exposed as a CLI command;
- `:db-pipeline`: exposed as a database-value transformation;
- `:exec`: exposed through the compositional request interface;
- `:implicit`: performed by CLI process or resource lifecycle;
- `:representation`: an alternate native delivery representation with the same
  EDN result;
- `:host-extension`: requires caller-provided executable code and is outside
  data-only parity; or
- `:separate-api`: belongs to a different module, such as direct SQLite.

CI must reject an unknown or missing disposition when a primary frontend adds
a public operation.

## Parity boundary

### Included

The target includes all VevDB operations whose behavior is an immutable value,
a serializable result, a durable store effect, or an observable stream of
transaction reports. This includes:

- connection and DB metadata;
- transactions, speculative transactions, and logical bulk transactions;
- current, `as-of`, `since`, and history DB values;
- transaction log ranges;
- Datalog queries, rules, inputs, result shapes, and query profiling;
- pull, pull-many, and index-pull;
- entity, ident, lookup-ref, attribute, and touch behavior;
- datoms, seek-datoms, reverse seek-datoms, and index-range;
- prepared queries and pull patterns within a multi-operation invocation;
- semi-sequential UUID utilities; and
- durable residency, index compaction, and index maintenance.

### Process-bound facilities

Native handles, retain/release calls, and close operations are lifecycle
mechanisms rather than distinct CLI behavior. The CLI must manage them
correctly and expose the values they enable through composition, but it must
not expose pointer-like identifiers across process invocations.

Prepared queries, prepared pull patterns, native transaction builders, and
typed/columnar query results are primarily performance and representation APIs.
The CLI must preserve their semantic outcomes. Reuse of prepared values in one
process is provided by `vevdb exec`; native column batches do not require a
separate output format because canonical EDN preserves the same logical result.

### Host-language extensions

Query predicates, aggregates, transaction functions, and listeners that invoke
caller-provided Kvist, Clojure, or C callbacks cannot be represented by EDN
alone.

Built-in query functions, aggregates, transaction operations, and rules remain
in scope. Only registration of new executable host callbacks is excluded.

Transaction listening still has a CLI equivalent, `vevdb watch`, because its
observable result is a stream of reports. Loading arbitrary caller code is not
part of this specification. If plugin loading is added later, it must be a
separate explicitly trusted extension mechanism and must not be required for
core parity.

### Separate APIs

The direct SQLite API is not part of VevDB CLI parity. It is a separate API for
application data and is not part of `vev.core` or `clients/kvist/vev.kvist`.

## Compatibility requirements

The following existing forms must continue to work unchanged:

```text
vevdb --version
vevdb info <store>
vevdb confirm-entity-partitions <store>
vevdb transact <store> <transaction>
vevdb query <store> <query> [inputs]
vevdb pull <store> <pattern> <numeric-entity-id>
```

Existing successful output remains EDN. Existing scripts must not need to add a
format flag. Existing nonzero-on-failure behavior must remain intact.

New forms may generalize an existing positional argument. For example, `pull`
will accept an EDN ident or lookup ref in addition to a numeric entity ID.

## Common argument and output rules

### EDN arguments

Every transaction, query, query input, rule set, pull pattern, entity selector,
index component vector, time point, option map, pipeline, and exec request is an
EDN argument.

An EDN argument must support:

- inline EDN;
- `@path`, which reads the entire file at `path`;
- `-`, which reads the entire standard input; and
- the existing `*.edn` file-name convention for backward compatibility.

At most one argument in an invocation may consume standard input. `@path` is
the preferred unambiguous file syntax in new documentation. File content is
parsed exactly as inline content; files do not get operation-specific wrapper
semantics.

Store paths are never parsed as EDN.

### Entity selectors

Commands accepting an entity must accept the portable entity domain supported
by the primary APIs:

```clojure
123
:person/ada
[:person/email "ada@example.com"]
[:item/id #uuid "d6f9fe80-b2bd-4c6d-b650-3c43c03f9156"]
```

Numeric entity IDs, idents, and lookup refs must have the same resolution and
not-found behavior as Clojure and Kvist.

### Time points

Time points must accept:

- a non-negative basis `t`;
- a transaction entity ID; or
- an EDN `#inst` value.

Integer normalization and inclusive/exclusive boundaries must match `as-of`,
`since`, and `tx-range` in the primary APIs. Open transaction-log bounds are
represented by `nil`.

### Standard output

Except for `watch`, every successful invocation prints exactly one complete
EDN value to standard output followed by a newline. No diagnostics or progress
messages may be written to standard output.

The default is compact, single-line EDN. A global `--pretty` option may produce
indented EDN without changing the value. JSON is not required: JSON cannot
faithfully preserve VevDB keywords, symbols, sets, UUIDs, instants, and entity
values without a second type protocol.

Datoms must use the portable five-position vector form:

```clojure
[entity attribute value transaction added?]
```

Commands returning a possibly missing scalar print `nil` when the corresponding
primary API returns no value.

### Errors and exit status

Success exits zero. Usage, input, store, query, pull, and transaction failures
exit nonzero. Version 1 of this work may continue using exit status `1` for all
failures; additional exit-status categories are reserved.

Errors that occur before an operation produces a domain result print no value
to standard output. They print one EDN error map to standard error:

```clojure
{:ok false
 :vev/error :vev.error/invalid-input
 :message "..."
 :operation :query}
```

A rejected `transact` or `with` continues the existing transaction-report
contract: it prints the report to standard output and exits nonzero. Its report
contains `:ok false` and the Vev error information.

Error text need not be byte-for-byte stable. Error keywords, success/failure,
output placement, and exit status are part of the compatibility contract.

## Immutable DB selection and composition

Every read operation must accept the same optional database pipeline:

```text
--db <pipeline-edn>
```

The value is a vector of operations applied from left to right to the current
immutable database value. An omitted option and `--db '[]'` both mean the
current DB.

The initial pipeline operations are:

```clojure
[[:as-of 42]
 [:since #inst "2026-08-01T00:00:00.000-00:00"]
 [:history]
 [:with [{:db/id 1 :person/name "Hypothetical Ada"}]]]
```

Their meanings are:

- `[:as-of time-point]`: call `as-of`;
- `[:since time-point]`: call `since`;
- `[:history]`: call `history`; and
- `[:with tx-data]`: call `db-with`, retaining only the resulting DB value.

The exact order is significant. Repeated operations are permitted when the
underlying API permits them. Invalid compositions fail rather than being
silently reordered. A pipeline never mutates the durable store.

For example:

```sh
vevdb query project.db query.edn \
  --db '[[:as-of 100] [:with [{:db/id 7 :task/status :done}]]]'

vevdb datoms project.db :eavt '[]' --db '[[:history]]'
```

The pipeline is a required architectural primitive, not query-only syntax.
`query`, `pull`, entity operations, index operations, DB metadata, and
speculative transactions must all consume the DB it produces.

The CLI opens one source snapshot before applying a pipeline. All work in that
invocation therefore observes a coherent basis even if another process commits
concurrently.

## Direct command surface

The following command names and semantics are required. Exact help formatting
is not normative, but every command must have command-specific `--help`.

### Connection and database metadata

```text
vevdb info <store>
vevdb sync <store> [target-t]
vevdb db-info <store> [--db <pipeline>]
vevdb index-info <store> [index]
```

`info` expands its current result to the durable connection information
available through the primary APIs:

```clojure
{:backend :sqlite
 :path "/absolute/or/canonical/path"
 :basis-t 42
 :tx-count 42
 :tx-ids [...]}
```

Existing keys retain their meanings. Additional storage metadata may be added
under namespaced keys.

`sync` captures a DB containing every transaction complete when the command
begins. With `target-t`, it waits using the same semantics as the primary API.
Because a DB handle cannot outlive the process, it returns the DB descriptor
defined below.

`db-info` returns:

```clojure
{:basis-t 42
 :next-t 43
 :as-of-t nil
 :since-t nil
 :history? false
 :stats {:datoms 100 :attrs {...}}}
```

The descriptor for any DB value is the same map without `:stats`. It describes
the value but is not a token that can be passed to another CLI invocation.

`index-info` exposes public durable-index metadata from the primary frontends,
including Kvist's latest merge-run count. It must not expose unpublished
internal storage diagnostics by default.

### Time and transaction log

```text
vevdb tx-range <store> [start [end]]
vevdb t-to-tx <t>
vevdb tx-to-t <tx>
```

`tx-range` uses an inclusive start and exclusive end. Missing arguments are
open bounds. It returns the same transaction-map shape and ordering as the
primary APIs.

The two coordinate conversion utilities do not open a store. Hyphenated CLI
names correspond to Clojure `t->tx` and `tx->t` and Kvist `t-to-tx` and
`tx-to-t`.

### Query

```text
vevdb query <store> <query> [inputs]
  [--rules <rules>]
  [--db <pipeline>]
  [--result envelope|q|rows|scalar]
  [--profile]
  [--timeout <milliseconds>]
```

Requirements:

- `envelope` is the default for backward compatibility and preserves the
  current `{:ok ... :error ... :rows ...}` CLI result.
- `q` preserves the query's Datomic-style find shape.
- `rows` always returns a vector of row vectors, corresponding to Clojure
  `rows`.
- `scalar` requires a scalar-compatible result and corresponds to Clojure
  `scalar`.
- `--rules` supplies the `%` rule input without requiring the caller to embed
  it in the positional input vector.
- Rules supplied in the positional input vector remain supported.
- `--profile` returns `{:ret selected-result :query-stats stats}` using the
  native query profiler.
- `--timeout` matches the primary API's elapsed-time timeout semantics. It must
  not claim that native execution can be interrupted if the engine cannot do
  so.

Named additional DB sources and relation DB sources are provided through
`vevdb exec`, because a positional EDN input cannot carry a native DB value.

### Pull

```text
vevdb pull <store> <pattern> <entity> [--db <pipeline>]
vevdb pull-many <store> <pattern> <entities> [--db <pipeline>]
vevdb index-pull <store> <options> [--db <pipeline>]
```

`entities` is an EDN vector of numeric IDs, idents, or lookup refs. Input order
and missing-entity behavior must match `pull-many` in the primary APIs.

`index-pull` accepts the same option map as the primary APIs, including
`:index`, `:selector`, `:start`, `:reverse`, `:offset`, and `:limit`.

### Entity and schema

```text
vevdb entity <store> <entity> [--db <pipeline>]
vevdb entity-get <store> <entity> <attribute> [--db <pipeline>]
vevdb entity-contains <store> <entity> <attribute> [--db <pipeline>]
vevdb entid <store> <entity> [--db <pipeline>]
vevdb ident <store> <entity> [--db <pipeline>]
vevdb attribute <store> <attribute> [--db <pipeline>]
```

`entity` eagerly touches and serializes the entity as an EDN map, including
`:db/id`. This is the serializable equivalent of obtaining and realizing an
entity view. Component recursion and reference representation must match
`touch` in the primary APIs.

`entity-get` preserves cardinality-one versus cardinality-many result shapes
and reference semantics. `entity-contains` prints a boolean. Unresolved idents
and lookup refs follow primary-API behavior rather than fabricating an empty
entity.

### Index access

```text
vevdb datoms <store> <index> [components] [--db <pipeline>]
vevdb seek-datoms <store> <index> [components] [--db <pipeline>]
vevdb rseek-datoms <store> <index> [components] [--db <pipeline>]
vevdb index-range <store> <attribute> <start> <end> [--db <pipeline>]
```

`components` is one EDN vector and defaults to `[]`. This avoids shell
ambiguity while retaining arbitrary typed index components. `start` or `end`
may be `nil` where the underlying operation permits an open bound.

All commands return vectors of five-position datoms in native index order.

### Transactions and hypothetical transactions

```text
vevdb transact <store> <transaction>
vevdb transact-many <store> <transactions> --mode logical|flatten
vevdb with <store> <transaction> [--db <pipeline>]
```

`transact` preserves its current report and atomicity semantics.

`transact-many --mode logical` accepts a vector of transaction-data values,
preserves one logical transaction and report per input, and performs them under
one durable commit. It corresponds to Clojure `transact-logical` and the native
many-report API.

`transact-many --mode flatten` treats each element as a transaction-data group,
flattens the groups, and commits one logical transaction. It corresponds to the
semantic outcome of `transact-bulk`; EDN replaces the host-only typed builder.
Empty-input behavior must match the relevant primary API.

`with` applies the transaction to the selected immutable DB without changing
the store and prints a serializable transaction report. Its DB-after value is
available for further work only inside a DB pipeline or `vevdb exec`.

Successful transaction reports use the existing portable value and add DB
descriptors without exposing handles:

```clojure
{:ok true
 :error ""
 :vev/error nil
 :tx 4611686018427387945
 :tx-data [[...]]
 :tempids {...}
 :tx-meta [...]
 :db-before {:basis-t 41 ...}
 :db-after {:basis-t 42 ...}}
```

Adding descriptors must not remove or rename existing report keys.

### Utilities

```text
vevdb squuid
vevdb squuid-time-millis <uuid>
```

The first prints a tagged EDN UUID. The second accepts a tagged EDN UUID and
prints its encoded Unix time in milliseconds.

Kvist's `instant-text`, `instant-from-text`, and `value-instant` are portable
value-conversion helpers rather than database operations. The CLI provides
their semantic outcome through parsing and printing EDN `#inst` values. The
parity manifest records them as `:representation`; no separate instant-string
command is required.

### Durable maintenance

```text
vevdb ensure-resident <store>
vevdb compact-indexes <store>
vevdb reclaim-indexes <store>
vevdb maintain-indexes <store> [--max-steps <n>]
```

These commands expose the corresponding primary-API operations. Results must
be data rather than prose, for example:

```clojure
{:ok true :resident? true}
{:ok true :compacted? true}
{:ok true :reclaimed? true :physical? true}
{:ok true :steps 3 :compacted? true}
```

Backend-specific diagnostic operations that are not public in either primary
frontend are not added merely because an internal function exists.

### Transaction report stream

```text
vevdb watch <store> [--after <time-point>]
```

`watch` is the stream-oriented equivalent of a transaction listener. It emits
one compact EDN transaction report per line and flushes after every report. It
continues until interrupted and exits cleanly on `SIGINT`/Ctrl-C.

The implementation must close the race between reading the initial basis and
registering the listener. `--after` emits every transaction strictly after the
given point, including transactions committed during startup. Reconnect and
polling behavior, if supported, must not duplicate transaction IDs.

## Compositional execution

Direct commands cover common one-operation invocations. They cannot alone
provide parity for workflows in which an intermediate DB, report, entity,
prepared query, or prepared pull pattern must remain alive. The CLI therefore
must provide:

```text
vevdb exec <store> <request-edn>
```

`exec` opens one connection, evaluates an ordered operation plan, retains named
intermediate values for the duration of the process, prints one EDN return
value, and releases all resources before exit.

The positional store is the default store for every step. A `:db`,
`:transact`, or maintenance step may provide `:store "other.db"` to open an
additional store in the same invocation. There is no cross-store transaction:
durable effects remain atomic only within each store operation.

Source-less queries and in-memory workflows use:

```text
vevdb exec --memory <request-edn>
```

`:empty-db` creates an empty immutable value. `:init-db` accepts the same datom
input as the primary frontend and creates an immutable in-memory DB; neither
operation creates a durable store.

### Request shape

```clojure
{:steps [{:id :current :op :db}
         {:id :old :op :as-of
          :db [:ref :current]
          :time 100}
         {:id :hypothetical :op :with
          :db [:ref :old]
          :tx [{:db/id 7 :task/status :done}]}
         {:id :answer :op :query
          :db [:ref :hypothetical :db-after]
          :query [:find ?status .
                  :where [7 :task/status ?status]]}]
 :return [:ref :answer]}
```

Each step has a unique keyword `:id` and an operation keyword `:op`. A
reference has the form `[:ref step-id & path]`. Paths address structured
results such as a transaction report's `:db-before`, `:db-after`, or
`:tempids`. References may point to native intermediate values that cannot be
printed.

Steps execute in vector order. A reference may only refer to an earlier step.
The default return value is the last step's result. `:return` may be a reference
or an EDN structure containing references, which are resolved recursively.

Returning a DB serializes its DB descriptor. Returning an entity serializes its
touched map. Returning an opaque prepared value directly is an error.

### Required exec operations

The executor must support these operation families:

| Family | `:op` values |
| --- | --- |
| DB creation | `:db`, `:empty-db`, `:init-db` |
| DB transformation | `:as-of`, `:since`, `:history`, `:with`, `:db-with` |
| DB metadata | `:db-info`, `:basis-t`, `:next-t`, `:as-of-t`, `:since-t`, `:history?`, `:db-stats` |
| Entity/schema | `:entity`, `:entity-get`, `:entity-contains?`, `:entid`, `:ident`, `:attribute`, `:touch` |
| Index | `:datoms`, `:seek-datoms`, `:rseek-datoms`, `:index-range` |
| Query | `:prepare-query`, `:query`, `:rows`, `:scalar`, `:profile` |
| Pull | `:prepare-pull`, `:pull`, `:pull-many`, `:index-pull` |
| Transactions | `:transact`, `:transact-many`, `:resolve-tempid` |
| Log | `:log`, `:tx-range` |
| Utilities | `:squuid`, `:squuid-time-millis`, `:t-to-tx`, `:tx-to-t` |
| Maintenance | `:ensure-resident`, `:compact-indexes`, `:reclaim-indexes`, `:maintain-indexes`, `:index-info` |

Operation maps use the same EDN values and result shapes as the corresponding
direct commands. The implementation should route direct commands through the
same operation layer to prevent semantic drift.

### Multiple query sources

An exec query step may bind additional named DB sources:

```clojure
{:id :joined
 :op :query
 :db [:ref :current]
 :sources {$old [:ref :old]
           $proposed [:ref :hypothetical]}
 :query [:find ?e
         :in $ $old $proposed
         :where ...]
 :inputs []}
```

Source symbols and ordering must be validated against the prepared query.
Relation DB sources accepted by the primary APIs may be supplied as EDN datom
relations in `:sources` or `:inputs`, as appropriate to the query form.

### Prepared values

`:prepare-query` and `:prepare-pull` return process-local values that later
steps may reference. Reusing them must compile or parse only once. Their
canonical EDN may be inspected through an explicit metadata operation if the
primary frontend exposes that result, but opaque handles are never printed.

Native transaction builders need not be exposed as opaque CLI objects. Every
typed builder operation has an equivalent EDN transaction form, and
`transact-many --mode flatten` supplies the bulk semantic outcome.

### Error handling and atomicity

Exec is fail-fast by default. A failed step aborts evaluation, prints a
structured error containing `:step` and `:operation`, and exits nonzero.

A step may request `:on-error :capture` to obtain an explicit error result,
providing the behavior of Clojure `try-transact` and `try-with`. Later steps may
reference that result.

An exec plan is not an implicit store transaction. Successful committed
transaction steps remain committed if a later step fails. Callers requiring
one durable commit must use one `:transact-many` step.

## API parity matrix

The implementation manifest must contain the detailed machine-readable
mapping. The minimum human-readable mapping is:

| Primary API area | CLI exposure |
| --- | --- |
| `connect`, `db`, close/retain | implicit invocation lifecycle; `:db` in exec |
| `sync`, connection info | `sync`, `info` |
| `basis-t`, `next-t`, filtered metadata, `db-stats` | `db-info`; individual exec operations |
| `as-of`, `since`, `history` | `--db` pipeline; exec operations |
| `log`, `tx-range` | `tx-range`; exec operations |
| `t->tx`, `tx->t` | `t-to-tx`, `tx-to-t` |
| `entity`, `touch`, entity lookup | entity command family; exec operations |
| `entid`, `ident`, `attribute` | commands of the same name |
| `datoms`, `seek-datoms`, `rseek-datoms`, `index-range` | commands of the same name |
| `q`, `rows`, `scalar`, query request stats | `query` modes and options |
| prepared queries and multiple DB sources | `exec` |
| `pull`, `pull-many`, `index-pull` | commands of the same name |
| prepared pull patterns | `exec` |
| `transact`, `with`, `db-with` | `transact`, `with`, DB pipeline, and exec |
| `resolve-tempid` | report data and exec |
| logical/bulk transactions | `transact-many` |
| typed transaction builders | equivalent EDN transaction data; `transact-many` |
| query result/column APIs | canonical EDN representation |
| `squuid`, `squuid-time-millis` | commands of the same name |
| index residency and maintenance | maintenance commands |
| latest index merge-run information | `index-info`; exec operation |
| transaction listeners | `watch` report stream |
| custom host callbacks | `:host-extension`, outside data-only parity |
| direct SQLite | `:separate-api` |

### Frontend adapters and aliases

The parity manifest must also account for public helpers that do not require a
new command:

- `open`, `open-sqlite`, `try-connect`, `transact!`, `transact-text`,
  `with-text`, `with-report`, `history?`, `listen!`, and `unlisten!` are aliases,
  compatibility entry points, raw-text adapters, or explicit-error variants of
  operations already listed.
- `retain-db`, close functions, `entity-db`, and entity-found/id helpers are
  resource or object adapters. Exec retains the owning DB with an entity and
  exposes found/id behavior through `entity`, `entid`, and references.
- `prepared-edn`, `parse-clause`, `prepare`, and `prepare-pull-pattern` are
  parsing/preparation helpers. Exec provides preparation and may expose
  canonical prepared EDN metadata, but it does not serialize native handles.
- `query-result`, `column-batch`, `columns`, `q-text`, and legacy row adapters
  are delivery representations. `query --result ...` and canonical EDN carry
  the same logical values.
- `tx-builder`, `tx-add!`, and `bulk-add!` construct transaction data more
  efficiently in a host process. EDN transaction data and `transact-many`
  preserve their database effects.
- `log-tx-ids` is included in `info`; lookup-ref existence is expressible via
  `entid` or `entity`.
- Kvist instant constructors/parsers are represented by EDN `#inst` parsing
  and serialization.

Aliases do not require duplicate commands, but they do require a manifest
entry and an equivalence test or a documented representation disposition.

## Concurrency and store access

- Read-only commands must open the store read-only and take one immutable
  snapshot before evaluating their DB pipeline.
- Mutating and maintenance commands must use a writable connection.
- `exec` must infer whether a writable connection is required from its steps;
  it should use read-only access when the complete plan is read-only.
- A transaction must retain the engine's existing multi-writer refresh and
  serialization semantics.
- A read command must never observe a mixture of bases within one invocation.
- Speculative `with` and `db-with` must never write to the durable store.
- The CLI must not implement historical or hypothetical behavior by copying or
  modifying store files.

## Implementation architecture

The implementation should introduce three internal layers:

1. A common EDN/file/stdin argument reader and structured error writer.
2. An operation layer over `Store-Conn`, `Store-DB`, reports, entities, prepared
   values, and serializable `Value` results.
3. Thin command adapters plus the exec plan evaluator.

The operation layer should use VevDB's public/internal `Store-DB` semantic
functions rather than reconstructing behavior with Datalog. For example,
`datoms` must call the index API, `history` must construct a history DB, and
`with` must use the transaction planner. This keeps CLI behavior on the same
code paths as the C ABI and primary frontends.

All owned resources created while evaluating a command or plan must be tracked
and released on success and every error path. Exec references must retain a
resource when its producer would otherwise release it.

## Delivery plan

### Phase 1: contract and common infrastructure

- Add `compat/cli-api.edn` covering the current Kvist and Clojure APIs.
- Add shared EDN input handling for inline, `@file`, stdin, and legacy `.edn`.
- Add structured EDN errors without changing successful legacy output.
- Introduce DB descriptors and a reusable database-pipeline evaluator.
- Add command-level help and parser tests.

### Phase 2: read parity

- Add `db-info`, history/time selection, and `tx-range`.
- Add entity/schema commands.
- Add all index commands.
- Generalize pull and add pull-many/index-pull.
- Add query modes, rules, profiling, and timeout.

### Phase 3: transaction and maintenance parity

- Add `with` and report DB descriptors.
- Add `transact-many` logical and flatten modes.
- Add UUID/time utilities.
- Add residency, compaction, and maintenance commands.

### Phase 4: composition

- Add the exec evaluator, resource registry, references, and return resolution.
- Add prepared query and pull reuse.
- Add multiple DB and relation sources.
- Add captured-error behavior and intermediate report access.

### Phase 5: streaming and hardening

- Add race-free `watch` behavior.
- Complete cross-process, multi-writer, interruption, and resource-leak tests.
- Update `docs/cli.md`, release documentation, and CLI examples.
- Make the parity manifest check mandatory in CI.

Phases may be combined, but DB composition must not be postponed indefinitely:
without it, commands may exist by name while the CLI still cannot express the
primary APIs' immutable-value workflows.

## Acceptance criteria

The work is complete when all of the following are true:

1. Every public operation in the primary Kvist and Clojure VevDB namespaces has
   an accurate disposition in `compat/cli-api.edn`.
2. Every operation marked `:command`, `:db-pipeline`, or `:exec` has a CLI test
   that compares its normalized EDN result or durable effect with at least one
   primary frontend on the same fixture.
3. Current, as-of, since, history, and hypothetical versions of the same DB can
   each feed query, pull, entity, and index operations.
4. An exec test composes `as-of`, `with`, query, pull, and transaction-report
   access without mutating the store.
5. Multiple DB query sources work inside one exec request.
6. Logical bulk transactions preserve distinct transaction IDs while sharing
   one durable commit; flatten mode produces one transaction ID.
7. Transaction rejection, invalid EDN, missing files, invalid lookup refs, and
   invalid DB pipelines have stable output placement and nonzero exit status.
8. Existing CLI smoke tests and the six legacy command forms continue to pass.
9. Read-only commands do not open a writable connection.
10. Resource-leak tests cover success, parse failure, engine failure, captured
    exec failure, and interrupted watch execution.
11. `docs/cli.md` documents every shipped command and contains no command that
    is only planned.
12. The release artifact's `vevdb --help` and command-specific help agree with
    the documentation.

## Non-goals

This work does not require:

- an interactive REPL;
- persistence of native handles between separate CLI processes;
- JSON output;
- arbitrary Clojure, Kvist, or native plugin execution;
- exposing VevDB's internal SQLite schema;
- exposing every internal storage diagnostic;
- reproducing host-language-only lazy or collection types; or
- changing VevDB's query, transaction, pull, index, or history semantics.

The CLI is a complete data-oriented frontend to those semantics, not a shell
encoding of memory management or host-language implementation details.
