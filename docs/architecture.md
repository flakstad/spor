# Architecture

## Core principle

The semantic engine should own the database model.
Storage and foreign-language integration should sit at the edges.

The semantic boundary should be functional in character even if the internal
implementation uses local mutation.

Vev is Kvist-first at the implementation level. Kvist is used as the primary
source language because Vev's transaction, query, pull, and tooling surfaces are
data-shaped and application-like. Generated Odin should remain readable, but it
is output, not a second engine prototype.

The execution model should remain embedded-first without making a future server
packaging mode unnecessarily difficult.

That means the architecture should separate:

1. semantic core
2. query frontend
3. storage adapter
4. host/interop layer

## Proposed layers

### 1. Semantic core

This layer owns:

- datoms
- schema
- immutable DB snapshots
- transactions
- transaction metadata
- indexes
- query planning/execution
- pull/entity behavior

This is the most important layer to stabilize.

The preferred semantic shape of this layer is:

- input data in
- output data out
- immutable DB values for reads
- explicit transaction results for writes

This does not forbid local mutation inside the implementation. In fact, local
mutation is expected in places such as:

- parsers
- temporary buffers
- index construction
- scratch query evaluation structures

The rule is to keep mutation local and implementation-oriented rather than
making it part of the public semantic model.

### 2. Query frontend

This layer owns:

- EDN-like reader for query data
- Datalog parser
- query AST
- validation and normalized query forms

The canonical external query syntax should stay close to Datomic/DataScript.
Inside the engine, queries should be compiled to typed data structures.

### 3. Storage adapter

This layer owns:

- opening and closing durable stores
- physical index persistence
- transaction durability
- crash recovery semantics
- compaction/migration concerns

The semantic core should not become SQLite-shaped.

### 4. Interop layer

This layer owns:

- native Kvist public API
- C ABI for non-Kvist consumers
- native library packaging
- CLI binary for tooling and inspection
- Java and Datomic-shaped Clojure wrappers
- possible later server wrapper or daemon mode
- possible later transactor/peer packaging model

The C ABI should be a packaging boundary, not the internal architecture.

The CLI binary should be a thin application over the same engine and native
library path, not a separate database architecture.

## Embedded-first, server-possible

Vev should optimize for embedded use first:

- direct in-process calls
- simple local deployment
- explicit ownership of the connection by the application

At the same time, the architecture should avoid choices that would make a
future server mode unusually hard.

The main rule is:

- semantic boundaries should remain explicit and transportable as plain data

That especially applies to:

- tx input
- tx report
- query input
- query result
- pull input
- pull result
- tx metadata

This does not require designing network protocols now.
It only requires avoiding unnecessary dependence on in-process-only behavior in
the public semantic model.

## Possible future out-of-process models

If Vev later runs out of process, there are at least two plausible shapes:

### 1. Simple daemon/server wrapper

This is the lighter option:

- one process owns the engine
- clients talk to it over an API
- the semantic core remains essentially the same

This is the most straightforward "server mode" interpretation.

### 2. Transactor/peer-style split

This is the stronger Datomic-like option:

- a write authority/transactor process
- application-side libraries or peers
- some local read/query behavior outside the write authority

This is explicitly a possible future direction, but not a current
architectural commitment.

It would require additional design around:

- snapshot identity/versioning
- cache and sync strategy
- index or segment distribution
- trust and failure boundaries

The current project should only preserve the option, not optimize for it yet.

## In-memory model

The in-memory engine should start with Datomic/DataScript-style index families:

- EAVT
- AEVT
- AVET
- optional VAET when refs/backrefs require it

The initial rule should be:

- optimize for clarity first
- use sorted indexes
- preserve immutable snapshot semantics

## Connection model

The public model should distinguish:

- connection: mutable handle used for writes
- DB snapshot: immutable value used for reads

That is one of the most valuable pieces of the DataScript/Datomic mental model
and should remain central.

## Transaction context and reactions

The first extension beyond plain fact transactions should be transaction
metadata, not a mandatory event/projection/outbox subsystem.

Recommended order:

1. fact transactions
2. tx report with tx metadata
3. application-owned post-commit work based on `Tx_Report`
4. only later, if justified, first-class event streams

This keeps the core small while still supporting application concerns such as:

- provenance
- auditing
- request correlation
- UI or SSE updates after commit

In the embedded case, the simplest model is:

1. call `transact`
2. receive `Tx_Report`
3. perform follow-up work in the application

That avoids introducing callback registration or observer semantics into the
database core before they are clearly needed.

This also keeps the reaction boundary easy to preserve if Vev later runs
behind a server process. The same `Tx_Report`-style semantics can remain the
commit boundary even if the delivery mechanism changes.

If same-transaction derivation is ever added later, it should be deterministic
engine behavior or registered transaction logic, not ad hoc per-call callbacks.

## Backend strategy

### Phase 1

- in-memory only

### Phase 2

- SQLite-backed persistence

Recommended initial posture:

- prove the storage boundary with a simple snapshot-file implementation
- store engine-owned index pages or normalized records through a narrow storage API
- do not leak SQL row concepts into the semantic layer

### Later

- optional LMDB backend

LMDB may fit the index model better, but should not complicate the first
durable proof.
