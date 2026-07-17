# Next Steps

This document is the current Vev work plan. It is not a changelog.

## Current State

Vev is an embedded native database with in-memory and SQLite-backed durable
connections. Kvist and Clojure expose Datomic-shaped `q`, `pull`, `transact`,
`db`, and `db-with` APIs. Other hosts use the C ABI or language adapters.

- In-memory databases are first-class and require no SQLite.
- Durable databases use system SQLite behind Vev connection and DB-value APIs.
- Durable queries use Vev's persisted indexes and query engine; Datalog is not
  translated to SQL and opening a store does not rebuild a resident database.
- Kvist queries, rules, pull patterns, transaction data, and inputs are quoted
  immutable `Data`. Clojure uses the corresponding Datomic-style forms.
- EDN text remains the portable C ABI representation.
- The installed Kvist compiler passes all 379 Vev tests, including parser
  inputs and the resident/durable MusicBrainz mini suite.
- The macOS arm64 release build produces checksummed native, JVM, and source
  artifacts. Its release command enforces extracted-native and package-only
  smokes for C, Java/Clojure, Python, Node, Go, Rust, Odin, and Kvist.
- Release builds now reject missing host toolchains and an unexpected runner
  architecture instead of silently accepting skipped host smokes.
- The release workflow pins the Kvist compiler revision, builds on macOS arm64
  and Linux x86-64, uploads each verified platform release, and combines their
  manifests only when version, commit, and shared artifact hashes agree.
- The combined release assembles one `vev-java` jar containing all verified
  platform-native resources. Fresh Java and Clojure consumers are then tested
  with only `dev.vevdb:vev-java` or `dev.vevdb/vev-clj` coordinates; consumers
  resolve them from a temporary Maven HTTPS repository and do not select a
  native artifact or configure a library path.
- Native GitHub runners pass the complete package-only host suite on macOS
  arm64 and Linux x86-64, including Kvist. The combined JVM artifacts also pass
  fresh Java and Clojure coordinate resolution over HTTPS. This release proof
  is recorded by successful workflow run
  [29576948634](https://github.com/vevdb/vev/actions/runs/29576948634).
- Every pull request runs the release gate, and `combined release` is required
  before changes can land on `main`.
- Node package assembly has a focused native-addon builder. It no longer
  rebuilds the complete C ABI, CLI, and unrelated host adapters when the addon
  is the only missing artifact.
- The development native layout stages `include`, `lib`, and relocatable
  pkg-config metadata with the same structure as release bundles.
- The cross-platform release gate passes on macOS arm64, Linux x86-64, and
  Windows x86-64, including native and host-language package smokes. Windows is
  usable but not yet expected to have identical developer ergonomics to Unix.

Kvist runtime transactions and query inputs use ordinary contextual `Data`
literals. Static symbolic Datalog queries remain quoted:

```clojure
(vev.transact conn
  [[:db/add [:entity/id id] :entity/value value]])

(d.q
  '[:find ?name
    :where [?e :contact/name ?name]]
  db)
```

The 379-test Vev engine suite passes with the current Kvist compiler.

## Active Scale Work

Ro's outline benchmark is the current application-scale workload:

```sh
cd /Users/andreas/Projects/ro/ro-next
./scripts/benchmark-outline.sh --full
```

The benchmark separately measures fixture construction, durable transaction,
query materialization, and HTML rendering. Fixture construction and rendering
are not bottlenecks.

Current development measurements:

| Rows | Build | Durable transaction | Materialize | Render |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 0.3 ms | 0.03 s | 0.06 s | 1.7 ms |
| 1,000 | 3.0 ms | 0.29 s | 0.51 s | 15 ms |
| 10,000 | 30 ms | 3.15 s | 4.11 s | 154 ms |

The original 1,000-row durable transaction took about 17.2 seconds and the
10,000-row transaction did not finish within three minutes.

Bulk transaction preparation is now linear for the outline workload.
Transaction-local indexes resolve tempids and unique values, classify repeated
lookup refs once, and cache source resolutions. The post-resolution overlay
uses indexed unique-value and cardinality-one state rather than repeatedly
scanning prior operations.

Durable secondary fulltext data is now written only for attributes declared
`:db/fulltext true`, matching Datomic and Datalevin semantics. Prepared
statements are reused for fulltext and term writes.

At 10,000 rows, measured transaction phases are about 0.26 seconds resolving,
1.07 seconds validating/materializing the overlay, 0.34 seconds appending
datoms, and 0.90 seconds publishing persisted index roots. The transaction no
longer contains a quadratic planner scan.

The next visible bottleneck is query materialization. Ro currently performs
separate item, parent, and status queries; 10,000 rows take about 4.1 seconds
before HTML rendering.

## Hard Constraints

- In-memory mode remains first-class and independent of SQLite.
- SQLite remains an implementation detail behind normal Vev APIs.
- Engine and storage improvements must be general mechanisms, not
  benchmark-specific query handling.
- Immutable database values and Datomic-shaped host APIs remain intact.
- Runtime `Data` uses ordinary literals; quote is reserved for symbolic data
  and code.
- Performance issues should be compared with DataScript, Datomic, and
  Datalevin implementations before choosing an algorithm.

## Remaining Work

1. Publish the verified combined `vev-java` and `vev-clj` artifacts to the
   selected public Maven repository. The combined release already verifies
   clean consumer caches against a temporary Maven HTTPS repository, without
   repository-local classpaths, native paths, or `:mvn/local-repo`.
2. Cut the first tagged release from a successful gate run and publish its
   checksummed native bundles, combined JVM artifacts, source package, and
   adapter packages.
3. Add the exact optional-parent `get-else` outline query to the scale harness.
   Measure its physical plan and durable index reads at 100, 1,000, and 10,000
   rows.
4. Replace repeated per-row parent and status lookups with a general batched
   attribute operator or merge scan. The target is one bounded index pass per
   attribute, independent of result row count.
5. Carry typed columns through result projection and the application boundary
   so the engine does not repeatedly box and decode every scalar result.
6. Keep the durable transaction write profile as a regression gate.
   Revisit typed root batches and append serialization only when measurements
   show those phases dominate a real workload.
7. Keep contextual `Data` usage canonical.
   Remove remaining runtime quasiquote/unquote construction in Vev examples
   and adapters where an expected `Data` type can carry ordinary literals.
   Compile-time macro construction is not part of this cleanup.
8. Run correctness and scale gates after each storage or query change.
   Include Vev engine tests, durable reopen tests, Ro checks, and the full
   10,000-row benchmark.

Parser diagnostic exactness and additional DataScript edge cases continue
after the release and scale gates unless they expose correctness or safety
failures.

## Exit Criteria

This scale batch is complete when:

- the optional-parent `get-else` query is included and no longer performs
  repeated per-row durable lookups
- 100, 1,000, and 10,000 rows show explainable near-linear scaling for both
  transaction and materialization phases
- the 10,000-row durable transaction remains below the current 3.5-second
  regression ceiling on the development machine
- the 379-test engine suite and durable storage tests pass
- Ro's check, test, smoke, and `benchmark-outline.sh --full` commands pass

## Verification

```sh
kvist test src/vev_tests/vev_test.kvist

cd /Users/andreas/Projects/ro/ro-next
./scripts/benchmark-outline.sh --full
```
