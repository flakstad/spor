# Next Steps

This is the forward-looking VevDB work plan. Completed work belongs in release
notes, focused design documents, and Git history—not in this file.

The current product and architecture are described in the
[README](../README.md). Datomic Peer is the semantic and naming reference for
the primary API: embedded implementation details may differ, but public names,
argument order, result shapes, and documented semantics should not diverge
without an explicit recorded exception. Intentional DataScript-style helpers
such as `listen`/`unlisten`, and clearly documented VevDB conveniences, may
coexist with that core. Low-level row, result-handle, prepared-statement,
column-batch, profiling, parser, FFI, and storage-backend machinery is not part
of the ordinary public API unless explicitly approved.

## First Stable Release

`0.2.0-rc.3` is the current public prerelease. Before promoting it:

1. Exercise the public artifacts in real Clojure, Kvist, CLI, Java, C, and Odin
   projects, and fix release-blocking compatibility or packaging problems.
2. Run the complete five-platform release gate and public-coordinate acceptance
   after every release-candidate change.
3. Choose a new coordinated version for every changed release. Maven Central
   artifacts and Git tags are immutable; never reuse `0.2.0-rc.3`.
4. Promote to `0.2.0` only when the public prerelease has no known
   release-blocking issue, then repeat GitHub and Maven Central publication and
   clean-cache acceptance for the stable coordinates.

## Datomic API Direction

- Treat the lazy, associative Peer entity API—not the remote Client API—as the
  model for VevDB entities. Preserve lookup by entity id, ident, or lookup ref;
  keyword/map access; same-snapshot reference navigation; `entity-db`; and
  recursive component realization through `touch`.
- Keep `pull` and `pull-many` first-class beside entity access. Continue parity
  for wildcard/component expansion, forward and reverse refs, nesting,
  recursion, `:as`, `:default`, `:limit`, and named `:xform` behavior.
- Add the missing Datomic-shaped transaction report stream:
  `tx-report-queue` and `remove-tx-report-queue`. Keep the existing named
  `listen`/`unlisten` helpers as a documented DataScript-style convenience over
  post-commit reports. Do not describe them as Datomic Peer function names.
- Add the most useful remaining embedded Peer operations in this order:
  `attribute`, `db-stats`, `index-pull`, then `filter`/`is-filtered` and `qseq`
  where their lazy semantics can be preserved.
- Do not copy deployment- or transactor-specific Datomic operations that have
  no embedded equivalent.
- Keep entity values lazy and map-like, DB values immutable, and transaction
  coordinates consistent across Clojure, Java, Kvist, C, and Odin.
- Add parity tests before adding or changing a Datomic-shaped public API.
- Finish the client-surface audit described in
  [Client API Contract](client-api.md): one small ordinary API per host, with
  lower-level facilities moved behind internal/advanced namespaces or types.
- Do not expose process-local callback registration as Datomic stored
  functions.
- Do not persist or evaluate arbitrary host-language code. Stored functions
  remain out of scope until VevDB has a portable, deterministic execution and
  deployment model.
- Continue exact parser-diagnostic and DataScript edge-case work after release
  and scale gates, unless a gap exposes a correctness or safety problem.

## Scale Work

The active application-scale workload is Ro's 10,000-row outline benchmark.

1. Profile complete collection materialization across the item, parent, and
   status queries.
2. Reduce repeated query/result passes with a general multi-attribute
   projection or typed-column boundary. Do not add application-specific query
   fusion.
3. Carry typed columns through result projection and the application boundary
   where measurements show repeated scalar boxing or decoding.
4. Retain the durable transaction and optional-parent profiles as regression
   gates. Revisit root batching and append serialization only if measurements
   show those phases have become dominant.
5. Remove remaining runtime quasiquote/unquote construction from examples and
   adapters where contextual `Data` literals are sufficient. Compile-time
   macro construction is not part of this cleanup.

Run correctness and scale gates after every storage or query change:

```sh
kvist test src/vev_tests/vev_test.kvist

cd /Users/andreas/Projects/ro/ro-next
./scripts/benchmark-outline.sh --full
```

The performance constraints are:

- keep the 10,000-row durable transaction below 3.5 seconds on the development
  machine
- preserve near-linear optional-parent scaling through 10,000 rows
- reduce collection materialization from its current approximately 2.8-second
  baseline without regressing correctness, in-memory mode, or smaller
  workloads

## Client Distribution

- Keep standalone Clojure, Java, and Odin repositories synchronized with
  coordinated engine releases.
- Keep the C SDK and Odin vendor bundles self-contained and tested from
  extracted release artifacts.
- Decide registry publication separately for Python, Node.js, and Rust once
  their APIs and ownership models are ready. Keep Go importable from its
  canonical module path.
- Keep Windows supported by the release gate while improving its local
  developer ergonomics when concrete friction is reported.

## Later, Not Active

The following remain possible directions, not commitments for the next
release:

- a server or daemon deployment wrapper
- transaction-log export/import, backup, and replication primitives
- local-first synchronization
- a transactor/peer-style deployment

These must build on the existing immutable DB and transaction semantics rather
than reshaping the embedded API.

## Non-Negotiable Constraints

- In-memory mode remains first-class and independent of SQLite.
- SQLite remains an implementation detail behind normal VevDB APIs.
- Durable stores remain safely accessible from multiple connections and
  processes.
- Immutable retained DB values do not change as connections advance.
- Engine and storage improvements must be general mechanisms.
- The Clojure core remains Datomic-shaped. Additional helpers must be
  intentional, documented, and clearly distinguishable from low-level
  implementation machinery.
- The CLI, packaged clients, and library all operate on the same database
  semantics and durable format.
