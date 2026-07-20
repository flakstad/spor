# Transactions

## Goal

Define the first transaction model for Vev without overcommitting to a
separate event-sourcing subsystem too early.

The exact syntax compatibility target is summarized in
[docs/datomic-syntax.md](datomic-syntax.md).

The intended direction is Datomic-like:

- datoms remain the core state model
- transactions are reified
- transactions can carry metadata
- callers receive a transaction report
- transaction syntax should stay close to Datomic/DataScript transaction data

## Base transaction shape

The first transaction input should stay close to Datomic/DataScript:

```text
[:db/add e a v]
[:db/retract e a v]
[:db/retract e a]
[:db/retractEntity e]
[:db.fn/retractAttribute e a]
[:db.fn/retractEntity e]
```

This keeps the semantic core direct and easy to inspect.

It also preserves the value of existing Datomic/DataScript tutorials and tx-data
examples. Divergence here should be treated as costly and only justified by
real embedding constraints.

`[:db/retractEntity e]` and `[:db.fn/retractEntity e]` expand to retract
operations for the entity's current facts in the DB snapshot before the
transaction.

`[:db/retract e a]` and `[:db.fn/retractAttribute e a]` expand to retract
operations for current values of that entity+attribute in the DB snapshot before
the transaction.

## Reified transactions

Every successful transaction has a transaction identity and an automatic
wall-clock instant:

```clojure
[:find ?instant .
 :in $ ?tx
 :where [?tx :db/txInstant ?instant]]
```

The transaction entity, the datoms' `tx` field, and the transaction report's
`tx` field use the same entity id. Vev adds exactly one
`[tx :db/txInstant instant]` datom to every successful transaction, including
in-memory transactions, durable transactions, `with`, and transactions
produced by transaction functions. The fact remains available through normal
queries, immutable snapshots, history, and durable reopen.

Instants are millisecond UTC values and use EDN `#inst` syntax at text
boundaries. They are returned as native instant/date values by host bindings.
An import may explicitly set `:db/txInstant` on `"datomic.tx"` or
`:db/current-tx`. As in Datomic, an explicit value may not be newer than the
current wall clock or older than an existing transaction instant.

Transaction instants describe when facts were committed. Applications should
query them through transaction history instead of adding mechanically updated
`created-at` and `updated-at` attributes to every entity. Domain timestamps
remain appropriate when they describe a distinct business event.

## Historical database values

Vev exposes the three Datomic-shaped database filters:

- `as-of(db, tx)` includes facts in effect at transaction `tx`, inclusive.
- `since(db, tx)` includes current assertions made after `tx`, exclusive.
- `history(db)` exposes assertions and retractions across the database value's
  history. Five-position data clauses can bind transaction and added/retracted
  status.

The filters return immutable DB values and compose. For example, applying
`history` to an `as-of` DB exposes the fact history only through that inclusive
transaction boundary. Applying `db-with` to an `as-of` or `since` value keeps
the time filter; a history DB cannot be used as the point-in-time basis for an
entity view or transaction.

Time points may be a Vev basis `t`, transaction entity id (`u64`, or the host
language's corresponding integer), or native instant/date value. Instant
values resolve to the greatest transaction whose `:db/txInstant` is less than
or equal to the time point. For durable databases the view is backed by the
persisted append-only datom indexes, so it remains available after close and
reopen rather than depending on an old in-process handle. See
[Historical database values](history.md) for boundary cases, composition, and
the executable Datomic/Vev comparison.

Public spellings follow each host language:

- Kvist: `d.as-of`, `d.since`, `d.history`; `as-of` and `since` are overloaded
  for transaction coordinates and tagged `Data` read from `#inst` EDN
- C: `vev_db_as_of`, `vev_db_since`, `vev_db_history`, plus
  `vev_db_as_of_instant_millis` and `vev_db_since_instant_millis`
- Clojure: `d/as-of`, `d/since`, `d/history`
- Java and Node: `db.asOf`, `db.since`, `db.history`
- Python: `db.as_of`, `db.since`, `db.history`
- Rust: `db.as_of`, `db.since`, `db.history`
- Go: `db.AsOf`, `db.Since`, `db.History`

Clojure and Kvist also expose Datomic-shaped immutable DB metadata:
`basis-t`, `next-t`, `as-of-t`, and `since-t`. A filtered DB keeps the latest
basis reachable from its source while reporting its normalized filter bound
separately.

The transaction log range API is `(d/tx-range (d/log conn) start end)` in
Clojure and `d.tx-range` in Kvist. Its start is inclusive, its end is
exclusive, and bounds may be open, transaction coordinates, or native
instants. Each result has `{:t t :data datoms}` shape. See
[Historical database values](history.md#transaction-ranges) for exact boundary
semantics and the executable Datomic Peer comparison.

Conceptually, each datom is associated with:

- entity `e`
- attribute `a`
- value `v`
- transaction `tx`
- added flag `added`

That transaction identity is useful for:

- auditing
- debugging
- tracing state changes
- attaching transaction-level context

## Transaction metadata

Vev should support optional metadata on the transaction as a whole.

This is the preferred first mechanism for carrying domain context such as:

- actor id
- request id
- command source
- import source
- reason/cause
- correlation ids

Examples of the kind of meaning this can capture:

- "user 7 changed this"
- "this came from the nightly CRM import"
- "this transaction belongs to request req-123"
- "this was triggered by profile-edit UI flow"

The preferred direction is to mirror Datomic's transaction-context model as
closely as practical rather than inventing a new transaction-metadata syntax.

## Facts vs transaction metadata

These two things solve different problems.

Facts answer:

- what is true now?

Transaction metadata answers:

- under what context did this transaction happen?

Example:

```text
[:db/add 42 :user/name "Anna"]
```

This says the current name is `Anna`.

Transaction metadata can add:

- actor `7`
- reason `:profile-edit`
- request id `req-123`

That is usually enough for:

- provenance
- audit context
- operational tracing

without introducing a separate event stream yet.

## Why not a first-class event layer yet

A separate event model is only justified if the application truly needs to
distinguish:

- resulting state
- from domain happenings as first-class records

For many applications, transaction metadata plus tx reports is enough.

That is the default stance Vev should take first:

- prefer tx metadata
- let application code react to transaction results directly
- delay event-stream design until a real gap appears

## Transaction report

The transaction result should expose a shape close to:

- `ok`
- `error`
- `db-before`
- `db-after`
- `tx-data`
- `tempids`
- `tx-meta`

This gives callers:

- commit success/failure without exceptions
- immutable before/after snapshots
- the exact fact delta
- tempid resolution
- transaction context in one place
- the boundary where embedded applications react after commit

String tempids in list-form tx data are resolved during transact and returned
through `tempids`.

Successful transaction reports always include `:db/current-tx` in `tempids`,
mapped to the report `tx`, even when the transaction did not explicitly use
the reserved tempid. Explicit tempids keep their transaction-local names in
the same report map.

Lookup refs in list-form entity positions resolve through `:db/unique` attrs.
Missing lookup refs fail the report with `ok=false`.

The reserved tempids `:db/current-tx`, `"datomic.tx"`, and `"datascript.tx"`
name the current transaction entity and resolve to the report `tx` id, not to
a newly allocated entity id. Facts targeting that entity are written as datoms
and are also mirrored into `tx-meta` for convenient transaction report
inspection.

The automatic `:db/txInstant` value is also present in `tx-meta`, alongside
caller-supplied transaction metadata.

In the embedded single-process case, this is usually enough:

1. transact
2. receive `Tx_Report`
3. inspect `tx-data` and `tx-meta`
4. perform application work such as SSE push, cache updates, or projection refresh

That keeps reaction logic in application code rather than introducing a
subscription mechanism inside the database core.

## Transaction functions and stored functions

VevDB does not yet implement Datomic stored functions. It does not persist or
evaluate arbitrary host-language code, and the Datomic-shaped Clojure namespace
does not expose a separate callback registry API. This avoids presenting a
process-local callback mechanism as if it had Datomic's database-installed
semantics.

Through the C ABI, host-provided transaction functions currently return EDN
tx-data strings and receive borrowed typed argument values plus a borrowed DB
snapshot handle. Vev copies the returned tx-data before the callback frame is
released. This keeps the raw ABI simple while preserving normal transaction
rollback semantics: if the callback fails or its returned tx-data is invalid,
earlier segment operations are rolled back and listeners are not notified.

The Java wrapper exposes that low-level host extension as
`TxFunctionRegistry`. It remains useful for embedding and ABI validation, but
it is explicitly not Datomic stored-function compatibility. If stored
functions are added, they need a portable, deterministic execution and
deployment model rather than process-local callback registration.

## Listener and derivation extension point

Named report-sink listeners exist inside the engine. Raw C ABI transaction
report callbacks expose post-commit listeners to host code. Higher-level
wrappers can add more idiomatic listener helpers as needed.

If Vev later needs stronger same-transaction behavior than transaction
functions provide, the next step should be deterministic transaction-time
derivation configured as part of the connection or engine. That should be a
deliberate semantic feature, not an ad hoc callback shape.
