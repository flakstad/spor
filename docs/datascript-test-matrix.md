# DataScript Test Matrix

This is the working matrix for reaching DataScript compatibility without
turning every Clojure runtime detail into an engine blocker.

Vev's primary long-term consumers are non-Kvist native callers. A feature is
therefore not considered compatibility-complete until it is available through
the EDN/text or prepared-query/transaction surface. Kvist literal macros are
valuable convenience coverage and macro-system exercise, but they are secondary
frontends over the same typed query/tx/pull representations.

Status:

- `passing`: comparable Vev tests exist and pass
- `partial`: a useful subset is ported, more semantic cases remain
- `planned`: not ported yet, should become Vev tests
- `interop`: requires EDN/text APIs, parser frontend, or C ABI-facing shape
- `host`: Clojure/JVM/runtime behavior, not core engine semantics

Current local baseline: `kvist test src/vev_tests/vev_test.kvist` runs 370
tests successfully. The new MusicBrainz mini workload is separate and runs with
`kvist test src/vev_tests/musicbrainz_test.kvist`. The most important
remaining gaps are no longer basic
Datalog syntax or transaction shape coverage; they are exact parser validation,
host wrapper ergonomics, query planner/operator maturity, and generic
semi-naive rule optimization.

## Semantic Core

These are the main in-memory parity target. Durable storage is now active, but
these rows still track DataScript namespace coverage rather than backend
implementation status.

| Namespace | Upstream tests | Status | Next batch |
| --- | ---: | --- | --- |
| `query.cljc` | 11 | passing | DB-backed tx/op data pattern terms, primary/named collection datom sources including 1-wide scalar rows, 2-wide tuple rows, primary map relation sources, typed relation/collection/map input values, prepared primary collection queries, portable text/prepared result `Value` rendering including rules and named DB sources, portable profiled text/prepared result values with candidate/rule counters, map-form text queries, direct map-as-relation inputs, nested `:in` binding patterns, ignored `_` input placeholders in literal and text queries, nested map values, DataScript namespaced reverse attrs, checked scalar/collection/tuple/relation input shape errors, issue-425 symbol constants, and issue-385-style zero-arg/native function input behavior covered through EDN text/prepared-compatible registered functions; exact Clojure diagnostic text is host-shaped |
| `query_find_specs.cljc` | 1 | passing | keep covered |
| `query_fns.cljc` | 7 | passing | built-in predicates/functions including boolean/nil predicates, string contains/prefix/suffix helpers, integer arithmetic helpers, `name`, `str`, `keyword`, `subs`, `range`, regex predicate and match-return `re-pattern`/`re-find`, scalar/collection/tuple/relation `ground`, `get-else`, `get-some`, `missing?`, lookup-ref entity inputs, text/prepared tuple/relation/collection output destructuring, named predicate/function operator inputs, registered native-op aliases, typed native predicate/value callbacks including rule bodies and primary collection DB queries, DB-aware native predicates, unresolved data-bound predicate values producing no rows, and checked query errors covered; exact Clojure diagnostics are host-shaped |
| `query_not.cljc` | 5 | passing | nested `not`, `not-join`, default and explicit source semantics, anti-join implementation edge cases, checked unbound-group errors, query text plus Kvist literal macro source-order validation, and supported ordered rule bodies covered; exact diagnostics are Vev-shaped |
| `query_or.cljc` | 5 | passing | `or`, `or-join`, scalar input substitution, default and explicit source semantics, relation-source holes/mixed width, nested `or-join` binding forms, constant substitution regressions, branch var validation, and projection validation covered; exact diagnostics are Vev-shaped |
| `query_pull.cljc` | 8 | passing | pull query basics, wildcard pulls, pull interleaved with scalar find vars, input pattern variables including bare pattern names, multi-source pulls with `$` default source behavior, scalar/collection/tuple pull find specs, pull with aggregates, and lookup-ref pull inputs covered; DataScript's disabled multi-pattern test remains unsupported upstream too |
| `query_return_map.cljc` | 1 | passing | keep covered with Vev keyed-row shape |
| `query_rules.cljc` | 3 | partial | source args, recursion, repeated calls, ordered body execution for literal/text rules, wildcard rule-call arguments, inline map-query `:rules`, reusable prepared query plus prepared rules APIs for DB and relation DB queries, primary collection DB rule queries, native predicate/function inputs including DB-aware predicates inside rule bodies, intermediate rule-binding dedup and direct leaf-rule larger-dataset coverage for DataScript issue-456-style duplicate propagation, query profile counters for rule calls/fixpoint iterations, dependency-closure planning, cached linear/alternating transitive operators, conservative delta-driven positive recursive components that evaluate each recursive rule-call position against the current delta, and unknown/arity/param validation covered; relation-native semi-naive execution for richer rule bodies remains |
| `query_aggregates.cljc` | 1 | passing | built-in aggregates including `:with` duplicate preservation, grouped aggregate rows, numeric sum/avg, top-n min/max, parameterized top-n, median, variance, stddev, multi-argument aggregate tuple distinctness, DataScript comparator ordering for keywords, DataScript-shaped named custom aggregates, and typed aggregate callbacks through text/prepared APIs covered; exact diagnostic text is Vev-shaped |
| `transact.cljc` | 19 | partial | DataScript-style report `:db/current-tx` tempids, current-tx value aliases for `datomic.tx`/`datascript.tx` resolved to the report tx id rather than a fresh entity id, datom transaction/replay reports preserving explicit tx/op fields, portable transaction report `Value` rendering for text/prepared/immutable APIs, exact adjacent `retractEntity` tx-data ordering, value-less attr retracts and value-specific retract no-ops, CAS one/many/nil failure diagnostics, EDN text/prepared negative numeric tempids and single operation vectors, schema-aware map vector values, empty cardinality-many tempid validation, immutable DB-value `with-*`/`db-with-*` APIs for text/prepared EDN tx-data, native tx functions, registry-backed ident tx functions including EDN text/prepared `:db.fn/call` and shorthand ident calls with zero or more typed value args, immutable DB-value registered tx fn text/prepared APIs, failed registered tx fns rolling back preceding segment ops without tx/listener side effects, tx fns returning new tempid entities and generated map entities without `:db/id`, tempids-outside-add validation, and large entity-id rejection covered; remaining gaps are exact parser/API diagnostics and any still-unported transaction edge assertions |
| `upsert.cljc` | 6 | passing | vector tx tempid ordering, DataScript retry-order tempid merging, unique-value no-upsert, current-tx conflict, explicit-id identity conflicts, main conflict matrix, ref and lookup-ref upserts, non-upsert of new ref tempids, unique cardinality-many upserts, and EDN text/prepared transaction coverage for ordinary identity upsert, two-identity upsert, lookup-ref upsert, retry convergence, forward ref tempids, negative tempid refs, and rollback on conflict covered; exact diagnostic text is Vev-shaped |
| `validation.cljc` | 2 | passing | bad entity ids, bad attrs, nil values, bad ref values, unknown ops, tempids outside add, bad tx root shapes, uniqueness, schema booleans/keywords, component schema, and rollback/no-mutation validation are covered through runtime and EDN text APIs; exact Clojure exception types/messages are host |
| `index.cljc` | 5 | passing | main index order, component filtering, AVET schema filtering/errors, empty DB `find-datom`, prefix `find-datom`, `seek-datoms`, `rseek-datoms`, upstream `index-range`, tuple-value compare, lookup-ref index args, and binary-bound backed index access are covered; exact lazy sequence rendering is host/API shape |
| `tuples.cljc` | 11 | passing | tuple schema and validation, derived tuple maintenance, direct tuple attr rejection with redundant final-state tuple assertions, map-atomic versus vector-sequential tuple component updates, unique tuple conflicts/upserts, tuple lookup refs including nested ref lookup refs, tuple lookup-ref pull/query/index access, tuple query functions, and EDN text/prepared tuple tx-data covered; exact diagnostics are Vev-shaped |
| `lookup_refs.cljc` | 5 | passing | entity/query/tx/index lookup refs, mixed entity-id inputs, scalar and collection lookup-ref query inputs with DataScript-style projection of the original lookup-ref value, multi-source lookup-ref inputs, unresolved inline query lookup-ref errors, missing lookup-ref retract no-ops, and checked missing/non-unique lookup-ref errors covered; exact host/API rendering is Vev-shaped |
| `ident.cljc` | 4 | passing | keep covered |
| `explode.cljc` | 4 | passing | cardinality-many tx-map collection expansion, ref collections, reverse ref tx-map values, and Datomic-compatible nested maps through component refs or unique attributes, including multi-valued and reverse nested maps, are covered through EDN/text and Kvist tx-data; Clojure host list/array inputs are not part of Vev's native API surface |
| `components.cljc` | 2 | passing | component schema validation, forward pull/touch expansion, `retractEntity`, `retractAttribute`, multival components, and reverse navigation are covered; exact Clojure render/protocol shapes are host |
| `pull_api.cljc` | 18 | partial | repeated attr-spec normalization, DataScript namespaced reverse attrs, reverse component pull id/pattern/recursion shapes, unbounded ellipsis semantics with upstream-shaped 3000-hop deep recursion coverage, pull over filtered/restored/`init-db` DB values, plain rendered `Value.Map`/`Value.Vector` pull result shape including keyword/string/symbol `:as` keys and nil pull-many lookup-ref misses, text/prepared/lookup-ref pull APIs that return portable `Value` roots, ABI-friendly named `:xform` transforms for `vector`/`name`, typed native pull xform callbacks through text/prepared/query pull APIs, DataScript-shaped typed visitor trace events for attr/wildcard/reverse/nested pull traversal, and C ABI result-row/value-tree callbacks for pull/result values covered; exact collection/scalar edge cases remain |
| `entity.cljc` | 6 | passing | entity id/db access, scalar/many attr reads, contains, lookup-ref and ident construction, missing/dangling refs, forward/reverse ref navigation, nested reverse navigation, and touch are covered; Clojure protocol equality/hash/print/cache behavior is host |
| `filter.cljc` | 1 | passing | materialized filtered DBs cover query, entity, index access, chaining, and semantic DB equivalence; Clojure hash/equality/runtime wrapper behavior is host |

## Parser And Portable API

These are the primary compatibility gate for broad consumption. The first query
and transaction text APIs now exist, and query text inputs are consumed in
DataScript `:in` source order, but full parser parity still trails some native
Kvist literal conveniences. New DataScript compatibility work should prefer
EDN/text coverage first and add Kvist macro coverage as a convenience layer.

| Namespace | Upstream tests | Status | Notes |
| --- | ---: | --- | --- |
| `parser.cljc` | 3 | partial | direct parser APIs now cover DataScript binding, `:in`, and `:with` shapes including scalar vars, `_`, collection, tuple, nested collection/tuple bindings, source vars, and `%`; flat EDN node reader also feeds query/pull/tx/rules text subsets; prepared binding/`:in`/`:with` values have portable EDN-ish `Value.Map` rendering. Exact Clojure parser record rendering and diagnostics remain Vev-shaped |
| `parser_find.cljc` | 4 | passing | scalar, collection, tuple, pull, aggregate, custom aggregate, top-n aggregate, and multi-argument aggregate find elements including constants and source-symbol args covered through EDN text/prepared query parsing |
| `parser_query.cljc` | 1 | passing | vector and map query forms, map-form inline `:rules`, `:find`, `:with`, `:in`, named DB sources, ignored `_` input placeholders, optional ordered `:where`, direct map-as-relation inputs, float constants, nested input/result destructuring, reusable prepared query values including structured `not`/`or`, `ground`, `get-else`, `get-some`, pull-find rendering, return-map marker plus typed key metadata rendering, stable portable `:error-code` categories including `:edn-read` for reader-level malformed EDN, and checked validation for duplicate/out-of-order vector sections, unsupported and duplicate map query sections, duplicate return-map markers, unknown `:find`/`:with` vars, `:find`/`:with` overlap, duplicate inputs/`:with`, unknown source vars, and missing `%` for rule calls covered; exact diagnostic text is Vev-shaped |
| `parser_return_map.cljc` | 1 | passing | `:keys`/`:strs`/`:syms`, keyed text helpers, tuple return-map shape, prepared query `:return-map` marker plus typed key rendering for vector and map query forms, and marker-specific duplicate/count/collection/scalar validation for vector and map query forms covered; exact API rendering is Vev-shaped |
| `parser_rules.cljc` | 3 | partial | direct `parse-rules-text` API plus query text paths cover ordinary and source-qualified rule calls including wildcard arguments, plain and required rule vars, multiple branches, inline map-query `:rules`, ordered text rule bodies, rule-body `get-else`/`get-some`, and empty/duplicate/arity rule validation; prepared rules, queries, and tx-data have portable EDN-ish `Value.Map` rendering. Remaining exact Clojure parser record rendering remains Vev-shaped |
| `parser_where.cljc` | 6 | passing | data patterns including placeholders, symbol constants, `$`-prefixed symbol constants in non-source positions, lookup-ref entity terms, named DB source patterns, 1/2/3/4/5-wide relation-source rows, zero-arg and normal predicate/function syntax, custom predicate/function vars, missing?, not/not-join, or/or-join including branch-local predicate/function forms, source-qualified `not`/`not-join`/`or`/`or-join`, `and` branches, ordinary/source-qualified rule clauses, nested text `not`, direct `parse-clause-text` value rendering for data/predicate/function/rule/not/or clauses, and malformed pattern/group validation covered; exact parser object rendering is Vev-shaped |
| `pull_parser.cljc` | 1 | passing | query text pull finds, pull pattern variables, direct pull text APIs, reusable prepared pull pattern values, and portable prepared pull-pattern parser rendering cover attrs, wildcard including string `"*"`, DataScript namespaced reverse attrs, nested maps with vector or list pattern values, recursive map values including string ellipsis, flat/nested `:default`/`:as`/`:limit`/`:xform` option forms including string/vector option heads, repeated attr specs, option-wrapped map keys, checked rejection of malformed option/map specs, and schema-aware validation for reverse refs, nested refs/recursion, and explicit limits through query pull literals and pattern inputs; exact parser object rendering/diagnostic text is Vev-shaped |
| transaction EDN text | n/a | partial | `transact-text`, immutable `with-text`/`db-with-text`, reusable prepared tx-data, and immutable `with-prepared`/`db-with-prepared` cover `:db/add`, `:db/retract`, `:db/retractEntity`, `:db.fn/retractAttribute`, `:db.fn/cas`, `:db.fn/call`/shorthand transaction functions with typed value args, single operation vectors, map tx-data, set-valued cardinality-many collections, lookup refs, idents, float values, string/current-tx/negative numeric tempids, generated map ids, Datomic-compatible component/unique nested maps, reverse ref tx-map attrs including nested maps, ordinary and tuple upsert/lookup-ref transactions, rejection of map/set/non-tuple-vector datom values, and bad-shape/no-mutation validation through the normal transaction engine |

## Host Or Later Runtime APIs

These are useful, but not the next engine-parity gate.

| Namespace | Upstream tests | Status | Notes |
| --- | ---: | --- | --- |
| `conn.cljc` | 2 | passing | create/conn-from-db/conn-from-datoms and reset reports with tx-data, before/after snapshots, metadata, and listener delivery are covered; Clojure schema-map storage shape is host |
| `listen.cljc` | 1 | passing | named listener registration, tx-data delivery, metadata delivery, and unlisten behavior are covered through native report sinks; raw C ABI transaction report callbacks plus Java `Connection.listen` and Clojure `listen`/`unlisten` wrappers cover host post-commit listeners for in-memory connections |
| `serialize.cljc` | 5 | passing | `init-db` from datoms plus typed serializable and EDN-ish datom snapshot text roundtrips covered, including schema, retractions, refs, symbols, tuples, special floats, and next-tx recovery; DataScript's JVM/CLJS codec matrix is host/format work |
| `storage.clj` | 5 | partial | snapshot-file, SQLite datom-row durable reopen/query paths, native wrapper-level append-on-transaction SQLite connection mode, SQLite tx metadata rows, storage-neutral C ABI durable connection handles backed by SQLite, and basic Python/Rust/Java/Clojure durable wrapper smokes use the neutral connect API; exact DataScript storage API and richer packaged host ergonomics remain |
| `datafy.cljc` | 1 | host | Clojure-specific shape |
| `db.cljc` | 4 | passing | semantic DB diff is covered; record-updatable, hash-cache, and UUID helpers are Clojure/DataScript runtime details |
| `issues.cljc` | 5 | passing | issue-262 vector result isolation, issue-369 mixed-type DB diff, and issue-381 schema inspection are covered; issue-330/331 are Clojure pprint/meta host behavior |
| `query_v3.cljc` | 2 | passing | active validation cases plus the disabled relation-query example are covered through Vev relation DB APIs, including arity, non-collection sources, explicit `$`, prepared queries, and scalar/tuple/map primary sources |
| `lru.cljc` | 2 | host | DataScript implementation detail |
| `core.cljc` | 1 | host | test harness/runtime behavior |
| `cljs.cljc` | 0 | host | ClojureScript environment behavior |

## Batch Order

1. Tighten parser validation against `parser_*.cljc`, especially malformed
   `:find`, `:in`, `:where`, rule, pull, transaction, and return-map shapes.
   Portable prepared parser values now expose stable `:error-code` categories,
   including `:edn-read` for reader-level malformed EDN across query, rules,
   pull, and tx-data parser values; exact DataScript parser record/message
   parity remains the open work.
2. Keep MusicBrainz/Day-of-Datomic as targeted regression and performance
   coverage. The real-data comparison matrix currently passes, so new
   MusicBrainz work should start from a specific failing query/API/storage
   shape rather than broad expansion.
3. Continue SQLite storage work with write/reopen measurements and metadata
   inspection only where MusicBrainz or larger write-bench runs need it.
4. Replace the current rule/fixpoint and aggregate hot paths with measured
   implementations. The current engine is semantically useful, but DataScript
   parity also needs predictable performance on recursive rules and large
   relations.
5. Keep Kvist literal macros aligned with the typed AST as ergonomic sugar, not
   as the definition of compatibility.
