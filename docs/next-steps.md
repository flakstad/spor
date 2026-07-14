# Next Steps

This is the current Vev execution plan, not a changelog.

## Active Gate

Make first-class Kvist `Data` and EDN text converge on one lifetime-safe Vev
semantic representation. Prepared queries, rules, pull patterns, and
transactions must remain valid after their source Data or text is released.
Once that boundary is sound, replace Vev's duplicate EDN reader with
`kvist:edn`, complete literal/text parity, and return to publishable packages.

## Current Status

`examples/python/contact_book.py` is now the shared application source for
parallel Clojure and Kvist implementations. Both host versions exercise:

- in-memory operation without SQLite
- schema and data transactions
- immutable DB values passed to query and pull
- `db-with` isolation from the original DB value
- durable create, close, reopen, transact, and second reopen

The combined source-tree check is:

```sh
scripts/contact_book.sh
```

`src/vev_app` is the normal Kvist application surface. It presents opaque
`Conn` and immutable `DB` values for both in-memory and durable operation.
Quoted Kvist forms are first-class `Data`, so named query, transaction, and
pull values pass directly to query-first `q`, `transact`, `pull`, and
`db-with`. Vev converts `Data` to its canonical EDN tree and then uses the same
semantic parsers as the EDN text API; this is not an EDN serialization and
reparse path. Embedded MusicBrainz queries, rules, and pull patterns now use
quoted data; only rules actually loaded from `rules.edn` use the text path.
The Kvist MusicBrainz, aggregate, query-decomposition, and contact-book
tutorials now follow their Clojure counterparts by defining reusable queries,
pull patterns, rules, and transaction data as top-level quoted values and
passing the DB after the query. Static pull patterns no longer fall through
the EDN text API. Serialized input text remains only in validation helpers
that deliberately exercise parser/error boundaries.
Runtime quasiquote also builds ordinary managed Data, and the Kvist contact
book now uses an interpolated transaction map through both in-memory `db-with`
and durable `transact`.
Runtime EDN and rule files use `q-text` and `q-rules`. Storage types and SQLite
remain internal. DB values can be passed through application code as ordinary
values until their owner closes them.

Kvist `main` at `e8f3f9c` includes the complete core bootstrap and builds the
facade, native ABI, and contact book without Vev source changes. The compiler
binary is rebuilt at `/Users/andreas/Projects/kvist/kvist`; the normal
`~/.local/bin/kvist` command points to it. A forced native rebuild and the
combined Clojure/Kvist contact-book check pass with this compiler.

Vev has been migrated to the current package model: set types use their
canonical map representation, source macros define their own literal/string
classifiers, and owned values passed into ABI storage helpers are transferred
explicitly. A fresh native-library build followed by `scripts/contact_book.sh`
passes for both Clojure and Kvist.

`VERSION` is the canonical release version for every package surface. Client
metadata and packaging scripts use `0.1.0`; `scripts/release_manifest.sh`
rejects Java, Python, Rust, or Node metadata that diverges. The complete local
release command is:

```sh
scripts/build_release.sh
```

It builds the native library and JVM artifacts, then writes a hashed,
machine-readable platform manifest to `build/release/manifest.json`. The
manifest also identifies the source-distributed Python, Rust, Node, Go, Odin,
and Kvist package surfaces. Native freshness checks include the Kvist compiler
binary and release version, preventing either change from leaving stale native
metadata or code.

Prepared transaction data now deep-owns every string and nested value. A
focused regression releases and overwrites the source EDN buffer before using
the prepared transaction. Stored transaction groups now state whether their
items are owned, so cloned durable groups receive deep cleanup without making
borrowed native groups invalid.

Data-backed prepared queries retain their immutable source tree. A focused
regression constructs a query with `edn.read` inside a helper, returns only the
prepared query, and executes it after the helper's managed Data binding has
been released. This establishes the shared-owner alternative to deep-copying
the full semantic query graph.

Text-backed prepared queries now parse through `kvist:edn` and retain that same
Data representation. Their source-buffer lifetime regression and the combined
Clojure/Kvist contact-book gate pass. Every one-shot query variant now creates
a prepared query and delegates to the same semantic representation, including
profiled, result, relation-source, named-source, rule, and query-with-input-text
entry points. Query and rule text therefore have one EDN parser path across
prepared, C ABI, Clojure, and direct Kvist calls.

Query inputs encoded as EDN text now use `kvist:edn` as well. The shared
semantic conversion covers scalar, collection, tuple, relation, pull-pattern,
and lookup-ref inputs without changing their owned runtime representation. A
focused persisted lookup-ref input test and the combined Clojure/Kvist contact
book pass through this path.

Standalone binding, `:in`, `:with`, and clause parser objects also parse from
first-class Data now. They retain their source tree because their semantic
objects contain borrowed symbol and keyword text, and explicit destructors
release both the parser containers and source owner. A focused regression
constructs each object from a temporary mutable text buffer, destroys that
buffer, and verifies the parsed object afterwards.

Prepared rules and pull patterns now use the same retained Data owner for both
Kvist values and EDN text. Prepared queries with attached rules retain both
source trees. Focused regressions release rule, pull, query, and attached-rule
source buffers before execution; all prepared lifetime cases pass.

All one-shot pull text entry points now delegate to prepared pull patterns.
This includes in-memory and durable pull, pull-many, entity-id and lookup-ref
variants. Pull text therefore has one `kvist:edn` parser and prepared execution
path across storage modes.

The shared EDN reader now preserves Datalog's `_` wildcard as a symbol. Its
numeric classifier requires an actual decimal digit instead of trusting the
host integer parser's acceptance of a bare underscore. The Kvist EDN
round-trip regression and all five Vev rule-engine tests pass with this fix.

Transaction text now parses through `kvist:edn` into the same deep-owned
`Prepared-Tx-Data` used by first-class Kvist Data. In-memory transact,
immutable `with`/`db-with`, shared connections, and transaction-function
variants all delegate to prepared execution. The prepared lifetime suite and
the combined Clojure/Kvist contact book pass across in-memory and durable use.
Shared and SQLite storage wrappers now use that prepared transaction boundary
too, including bulk logical text groups, source transaction functions, and
source-backed immutable `db-with`. The legacy raw transaction parser has no
runtime caller. Focused storage tests cover grouped commits, parse rollback,
and source-backed DB-value behavior.

Serialized in-memory DB values now read through `kvist:edn` before building
their fully owned datom/index representation. This removes another independent
reader path without coupling the resulting DB lifetime to the parsed Data.
Durable tx-metadata rows, datom-log rows, index-snapshot datoms, and complex
serialized values have moved to the same path. All storage-layer uses of the
duplicate reader are gone; metadata and retracted-datom source tests pass.

JVM jars use the source commit timestamp for archive entries and are verified
byte-for-byte by `scripts/verify_jvm_reproducibility.sh`. Repeated Kvist
compilation produces identical generated Odin, but Odin 2026-05 currently
emits different native binaries from that identical input even with a single
checker thread and reproducible Apple linker mode. Native byte reproducibility
therefore remains the blocker for completing the current item; runtime and
dependency-only package verification are already green on macOS arm64.

The Clojure contact book also passes from a temporary project with only this
dependency:

```clojure
dev.vevdb/vev-clj {:mvn/version "0.1.0"}
```

`scripts/contact_book_package_clojure.sh` builds the local Java, Clojure, and
platform-native artifacts and verifies that dependency-only path. The app does
not use repository source classpaths, `VEV_LIB`, or SQLite APIs.

## Hard Constraints

- In-memory mode remains first-class and must not require SQLite.
- Durable mode may require system SQLite, but application code only sees Vev
  store paths and Vev APIs.
- Clojure and Kvist APIs should remain Datomic-like, including query-first
  `q` calls with the DB value after the query.
- Reusable Kvist queries, pull patterns, and transaction data must be ordinary
  named data values, not strings or macro-only forms.
- Non-Kvist consumers are primary product surfaces.
- Published coordinates must not be documented as available until publication
  has actually succeeded.
- Performance changes must be generic engine/storage work, never
  application-specific benchmark handling.

## Remaining Work

1. Finish replacing the duplicate Vev EDN reader. Primary query, query-input,
   rule, pull, and transaction entry points are complete. Remaining call sites
   are raw query/rule/pull/transaction parser compatibility helpers and the
   return-map key compatibility helper. Storage has no remaining call site.
   Standalone binding, `:in`, `:with`, clause objects, serialized DB values,
   and all runtime transaction wrappers are complete. Redesign or deep-own the
   remaining raw return shapes, retain their current diagnostics, and remove
   `read-edn-text!` only when its runtime call-site count reaches zero and
   parser/storage integration tests pass.
2. Finish the remaining tutorial-level Clojure/Kvist alignment. The ordinary
   named `Data` path now covers `q`, `transact`, `db-with`, direct pull, and
   lookup-ref pull, including error-aware pull variants and native-function
   query registries. Remaining work is to
   replace serialized-input validation helpers with typed query inputs where
   error inspection is not the point, and to expose result values through a
   more data-oriented application surface so tutorial assertions need less
   manual `Value` inspection and cleanup.
3. Make release builds reproducible for each supported OS/architecture. At
   minimum, produce and smoke macOS arm64 first, then add Linux x86-64 before
   calling the release generally available.
4. Publish or stage the native platform artifact first, then Java and Clojure
   artifacts that depend on it. Verify fresh temporary Clojure and Maven
   projects using normal coordinates and no repository-local Maven path.
5. Define Kvist package installation explicitly. Until Kvist has a registry,
   document a stable source dependency/vendor workflow that does not require
   copying arbitrary internal files.
6. Extend the dependency-only application smoke to every packaged host before
   publishing that host as supported.

## Exit Criteria

The packaging gate is done when:

- the installed Kvist compiler builds the normal application API and contact
  book
- one version command builds a manifest of all artifacts for a release
- macOS arm64 and Linux x86-64 native artifacts are reproducible and tested
- Clojure users can add one real published dependency and run the contact book
- Java users can add one real Maven dependency and run the equivalent smoke
- Kvist users have a documented stable package/source dependency path
- package consumers never need repository build paths or SQLite application
  code

## Regression Commands

- `scripts/contact_book.sh`
- `scripts/build_release.sh`
- `scripts/verify_jvm_reproducibility.sh`
- `scripts/contact_book_package_clojure.sh`
- `scripts/smoke_jvm_package.sh`
- `scripts/musicbrainz_workshop_setup.sh --validate`
- `scripts/compare_musicbrainz_workshop.sh --skip-datomic`

Performance is not the active workstream. Resume it only for a measured real
application blocker or a regression in an already covered workload, and consult
Datalevin before changing durable query execution.
