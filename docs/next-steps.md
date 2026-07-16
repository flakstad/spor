# Next Steps

This is the current Vev execution plan, not a changelog.

## Active Gate

Package the canonical Kvist application API and existing engine for
dependency-based use. The complete main regression gate passes 377 of 377
tests, the shared resident/durable MusicBrainz mini gate passes 2 of 2, and the
complete Kvist MusicBrainz workshop is green.
The canonical Kvist `q` and `pull` operations now return ordinary immutable
`Data`; callers do not inspect or close engine-owned result rows and values.
The macOS arm64 release command now produces repeatable checksummed artifacts
and passes extracted native C plus staged Java/Clojure package smoke tests. The
active product gate is the equivalent Linux build plus published-coordinate
consumption.

Parser convergence is complete. Quoted Kvist `Data` and EDN text use the same
`kvist:edn` reader, semantic parsers, and lifetime-safe prepared objects for
queries, rules, pull patterns, transaction data, and query inputs. The old Vev
reader and raw borrowed-result parser wrappers are gone.

## Current Product Surface

- `src/vev_app` provides Datomic-shaped `q`, `transact`, `db`, `pull`, and
  `db-with` operations over opaque connections and immutable DB values.
- Kvist applications can define reusable queries, rules, pull patterns, and
  transactions as ordinary quoted `Data`; no serialization round trip is
  involved.
- Canonical Kvist `q` results have Datomic-shaped immutable data: relation
  sets, collection vectors, tuple vectors, scalars, and keyed maps. Canonical
  `pull` returns an immutable map.
- The same EDN text surface serves C, Java, Clojure, Python, Rust, Node, Go,
  Odin, and other native-ABI consumers.
- In-memory operation requires no SQLite. Durable operation uses system SQLite
  behind Vev store paths and Vev APIs.
- Prepared objects retain their immutable source tree. Canonical Kvist query
  and pull data, transaction data, ABI values, pull patterns, and keyed return
  maps remain valid after parser input and prepared owners are released.
- Clojure and Kvist contact-book examples cover in-memory transactions,
  immutable DB values, `db-with`, pull, durable reopen, and subsequent writes.
- MusicBrainz workshop queries, rules, aggregates, and pull examples use named
  data in Kvist and Datomic-style forms in Clojure.
- The complete upstream Day-of-Datomic aggregate lesson uses canonical Kvist
  `q` data, including scalar and vector aggregates, relation results, and a
  host-registered custom aggregate. Its portable results match Datomic.
- The opening bindings and find-specification sequence from
  `day-of-datomic-conj/src/music_brainz.clj` and
  `day-of-datomic/tutorial/query.clj` uses canonical `q` values in both
  Clojure and Kvist. Pull tuples, collection inputs, relation inputs, relation
  finds, collection finds, tuple finds, and scalar finds have Datomic-shaped
  results. Raw result access remains only for the intentional missing-`$`
  diagnostic.
- The five negation and disjunction examples from
  `day-of-datomic/tutorial/query.clj` use canonical scalar `Data` in Kvist.
  Their `not`, `not-join`, `or`, and `or-join` results match the Clojure
  workshop path across the durable MusicBrainz store.
- The immediately following predicate and function-expression examples use
  canonical query data in both hosts. Artists starting before 1600 and John
  Lennon track durations match at 2 and 71 rows. Source-less canonical `q`
  accepts a scalar input, so the upstream Fahrenheit conversion reads
  `(d.q fahrenheit-to-celsius-query 212)` in Kvist and returns `100.0`, as it
  does through Clojure and Datomic.
- The `get-else`, `get-some`, `fulltext`, and `missing?` sequence uses
  canonical query data in both hosts. Kvist validates the same returned tuples,
  keyword values, fulltext names and scores, and missing-attribute count as the
  Clojure workshop over the durable MusicBrainz sample.
- Durable connections expose a Datomic-shaped transaction-log value in both
  hosts. The upstream `tx-ids` and `tx-data` queries run through ordinary
  query-first `q` calls; the local fixture returns the same 9 transaction IDs
  and 214 entity values for transaction 1 in Clojure and Kvist.
- The portable collection-function example runs unchanged in meaning in both
  hosts: `subs` maps the collection input to `["hello" "antid"]`. Clojure
  collection finds now match Datomic by returning distinct vectors rather than
  sets; relation finds remain sets.
- Numeric entity IDs in attribute position resolve through `:db/ident` in the
  literal, EDN, resident, and lazy durable query paths. The exact upstream
  `[?attr 42 _]` query returns keyword values through typed native columns;
  Datomic returns the same eight MusicBrainz attributes. The following dynamic
  attribute query accepts `[:db/unique]` through `:in $ [?property ...]` and
  returns keyword data through resident and reopened durable regressions. The
  Clojure and Kvist workshop validators require Datomic's same eight keywords.
  MusicBrainz exports preserve source schema entity IDs and include schema for
  the bounded data-attribute subset plus every source `:db/unique` attribute
  exercised by these workshop queries.
- Lookup refs, idents, and raw entity IDs are equivalent query inputs across
  Clojure and canonical Kvist `Data`. MusicBrainz exports preserve every
  referenced ident entity's source ID, so the raw-ID example executes against
  the same identity in Datomic and Vev. The installed sample assigns Belgium
  `17592186045669`; the older upstream tutorial snapshot used
  `17592186045516`.
- Dynamic reference attributes follow Datomic's distinction between values and
  entity identifiers. A keyword ident supplied through `:in` is not implicitly
  resolved when the attribute position is dynamic; `datomic.api/entid` performs
  the explicit conversion. Explicit lookup-ref inputs continue to resolve.
  The paired Clojure and Kvist workshop forms return 0 unresolved rows and the
  same 10 Belgian artists after conversion, matching the local Datomic sample.
- The artist UUID/type/gender enum query from
  `day-of-datomic-conj/src/music_brainz.clj` uses ordinary canonical `q` data
  in both hosts. This completes the portable query sequence currently present
  in that upstream file and in `day-of-datomic/tutorial/query.clj`.
- Set-backed canonical relation results can be passed directly back into `q`
  as relation inputs. The upstream Diana Ross collaboration-network query now
  composes two ordinary Kvist `d.q` calls exactly like the Datomic example,
  without converting an internal result through EDN text.
- Source-less relation aggregates run through Datomic-shaped `d.q query data`
  calls without constructing an empty database. The typed engine handles flat
  relation bindings, and nested or wildcard relation bindings fall back to the
  semantics-complete binder; the upstream monster-head examples return `4`
  without `:with` and `6` with it.
- Transaction-log queries retain the upstream `tx-ids` and `tx-data` forms in
  Clojure and Kvist. The restored Datomic sample starts at `t=1000`; its first
  transaction projects 59 distinct entities. The Vev subset importer creates
  new Vev transactions while separating schema and chunking selected values,
  so Vev transaction 1 is a 318-datom schema batch projecting 214 entities.
  Both Vev hosts match that persisted transaction; source Datomic transaction
  IDs and counts are intentionally not claimed to survive subset migration.
- Transactions accept Datomic-scale entity IDs through literal vectors, maps,
  ref values, and EDN text up to SQLite's signed 64-bit storage limit. The
  MusicBrainz exporter emits UUIDs as standard tagged EDN and retains compact
  remapped IDs for ordinary graph entities.
- `VERSION` is the shared package version. `scripts/build_release.sh` builds
  the native library and relocatable native bundle, deterministic JVM jars, and
  deterministic source archives; runs extracted C and staged Java/Clojure
  package smoke tests; and writes a manifest in which every artifact is a
  regular file with a SHA-256 checksum.

## Current Regression Status

- Main engine suite: 377/377 passing.
- SQLite reopen coverage now exercises the intended lazy durable model: open
  metadata, acquire immutable store snapshots for queries, and append through
  the durable transaction path. It no longer requires eager reconstruction of
  the resident in-memory cache.
- Logical clause profiling now remains accurate when the physical engine fuses
  bound clauses into fewer operators. Typed, materialized, and indexed
  relation-source hash joins preserve source row order within equal-key
  buckets without giving up indexed joins.
- The shared Kvist EDN reader rejects duplicate map keys without collapsing
  them, and Vev reports DataScript-compatible duplicate query-map section
  diagnostics for `:find`, `:with`, `:in`, `:where`, and `:rules`.
- EDN `#uuid` values retain their UUID type through the shared `Data` bridge,
  transactions, indexed queries, lookup refs, and serialization round trips.
- Typed scalar pushdown now applies string `contains?`, `includes?`,
  `starts-with?`, and `ends-with?` predicates with the same semantics as the
  normal predicate evaluator across resident and durable operator paths.
- Function expressions use one shared numeric evaluator in typed and binding
  execution. Mixed integer and floating-point arithmetic promotes to a float,
  while integer-only `quot`, `rem`, and `mod` retain integer semantics.
- Canonical Kvist `q` dispatches over immutable DB values, source-less inputs,
  and durable log values without exposing the underlying SQLite transaction
  helpers. Existing scalar, collection, relation, and rules inputs continue to
  use the shared query-input conversion path.
- Lookup refs supplied through scalar and collection query inputs resolve in
  both entity and ref-value positions while remaining lookup-ref values in the
  result, matching DataScript input semantics.
- Variable attribute terms now use the bound runtime attribute's schema.
  Dynamic ref attributes resolve lookup-ref inputs in both resident and lazy
  durable index scans, while ordinary keyword inputs retain raw value equality.
  Source-dependent query functions use the shared read-source operator path for
  resident and durable DB values rather than the source-blind resident executor.
- Pull rendering now matches the upstream DataScript result model for absent
  attributes and lookup-ref `pull-many`. The direct and nested absent-only pull
  examples return `nil`, matching the local Datomic sample. Resident typed
  aggregate queries group on both scalar find vars and pull entity vars, so
  aggregate values and pull maps remain associated without imposing row order
  on set results.
- Parser-input suite: 5/5 passing. Flat inputs stay on typed columns; nested
  tuple and collection input patterns use the recursive binding engine.
- Source-qualified rule calls now follow DataScript call-site source semantics
  through Kvist literals, EDN vectors, EDN maps, resident DBs, and relation
  sources. Direct source scans retain the typed path; compound source rules,
  `not`, and `or` use the semantics-complete binding path.
- Relation-value sources support DataScript's one- through five-position
  patterns, including transaction and operation terms. Source validation uses
  actual bound sources, and source `or` results retain set semantics without
  imposing an artificial row order.
- MusicBrainz mini suite: 2/2 passing across resident and SQLite-reopened
  snapshots. Its input forms now match upstream Day-of-Datomic by declaring
  the `$` source explicitly whenever `:in` is present.
- The complete Kvist workshop is green. It covers the canonical artist UUID/type/gender,
  nested collaboration, source-less relation aggregate, transaction-log, and
  direct pull sections. Datomic and Vev return the same nested artist-country
  map and the same `nil` values for the two absent-only pull examples. The full
  application-level run passes before release packaging.
- Native ABI build and both Clojure/Kvist contact-book applications pass.
- The macOS arm64 release gate passes from one command using the pinned Kvist
  branch compiler. Consecutive JVM package builds and source archive builds are
  byte-identical. Temporary Java and Clojure projects consume the staged Maven
  artifacts successfully, and the release manifest has no missing or unhashed
  entries.
- The versioned native bundle contains `vev.h`, the platform library, license,
  and relocatable pkg-config metadata. Its archive is byte-identical when
  repackaging the same library. The full existing C ABI smoke compiles and runs
  using only paths inside an extracted temporary bundle.
- Typed native result columns preserve keyword, symbol, and UUID kinds instead
  of collapsing them to strings. Java, Clojure, and Python reconstruct the
  corresponding host values while sharing the compact text-column storage.
- The Kvist contact book validates relation, collection, tuple, scalar, and
  keyed-map find shapes plus pull through the canonical immutable-`Data` API.
- Canonical result rendering derives find shape and keyed-map metadata directly
  from immutable query data. It does not reparse queries after execution, so
  host-registered aggregate functions and prepared semantics remain intact.
- The focused Kvist runtime-Data example passes. The broader compiler suite has
  eight failures in editor-symbol path discovery and now-accepted untyped block
  expression expectations; those are outside this Vev API change and must be
  reconciled before claiming a fully green compiler gate.
- The rebuilt 763,299-datom MusicBrainz store returns the same ten Belgian
  artists for lookup-ref, ident, and raw-ID inputs through Clojure and canonical
  Kvist `q`. The importer's optional post-persist reopened smoke currently
  stalls after persistence; process samples point at canonical `Data`
  append/release work. That smoke must be separated or fixed so
  `musicbrainz_workshop_setup.sh --validate` completes unattended.

Vev's regression gate currently uses the compiler built from Kvist's
`codex-runtime-def` worktree. Kvist commit `3336e8e3` supplies
`data.from-nil` and `data.append-retained!`, but is not yet on Kvist `main`.
That commit and the remaining runtime `def` and quoted-`Data` changes must land
and the installed compiler must be rebuilt before this Vev branch lands.

## Hard Constraints

- In-memory mode remains first-class and must not require SQLite.
- Durable storage details must not leak into normal application code.
- Clojure and Kvist APIs remain Datomic-like, including query-first `q` calls
  with the DB value after the query.
- Reusable Kvist database forms are named data values, not strings or
  macro-only forms.
- Non-Kvist consumers are primary product surfaces.
- Performance work must improve general engine or storage behavior, never one
  benchmark query.
- Published coordinates are documented as available only after publication
  succeeds.

## Remaining Work

1. Land the required Kvist runtime `def`, quoted-`Data`, and ownership-helper
   commits on Kvist `main`, rebuild the installed compiler, and rerun the full
   Vev and MusicBrainz gates with that installed binary.
2. Run the same release gate on Linux x86-64. Identical generated Odin is
   required; byte-identical native output is desirable but is not a release
   blocker with the current Odin toolchain.
3. Stage or publish the platform-native artifact, then Java and Clojure
   artifacts that depend on it. Verify fresh Clojure and Maven projects using
   normal coordinates and no repository-local paths.
4. Define a stable Kvist source dependency/vendor workflow until Kvist has a
   package registry.
5. Add dependency-only smoke tests for each host before advertising that host
   as supported.

## Exit Criteria

The current gate is done when:

- the installed Kvist compiler passes the complete Vev regression suite
- the Clojure and Kvist contact books run through the canonical application API
- canonical Kvist query tests cover relation, collection, tuple, scalar, keyed
  map, rules, inputs, and pull result shapes without manual result cleanup
- a single versioned command produces a checksummed artifact manifest
- macOS arm64 and Linux x86-64 native artifacts pass package smoke tests
- fresh Clojure and Java projects run using published or staged coordinates
- Kvist has a documented stable source dependency path
- package consumers need neither repository build paths nor SQLite application
  code

## Regression Commands

- `kvist test src/vev_tests/vev_test.kvist`
- `kvist test src/vev_tests/parser_input_test.kvist`
- `kvist test src/vev_tests/musicbrainz_test.kvist`
- `kvist build src/vev_abi/vev_abi.kvist`
- `scripts/contact_book.sh`
- `scripts/build_release.sh`
- `scripts/smoke_native_bundle.sh`
- `scripts/verify_jvm_reproducibility.sh`
- `scripts/contact_book_package_clojure.sh`
- `scripts/smoke_jvm_package.sh`
- `scripts/musicbrainz_workshop_setup.sh --validate`
