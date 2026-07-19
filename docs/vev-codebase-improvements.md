# VevDB Codebase Improvements

This is the current ownership document for codebase findings. It is not a historical log; items are grouped by current disposition.

Status labels:

- `done`: implemented in Vev.
- `todo`: worthwhile Vev work, not blocked on Kvist.
- `kvist`: better solved in Kvist compiler/packages/tooling.
- `kvist-done`: implemented in Kvist compiler/packages/tooling.
- `later`: real issue, but larger design work or lower priority than DataScript parity, C ABI, and performance.
- `not-now`: valid observation, but not worth changing currently.

## Done

- `done` Avoid eager `arr.range` in hot ordinary loops.
  Runtime and ABI hot paths now use explicit counted `while` loops where Vev needs zero allocation. See commit `76cb603`.

- `done` Replace duplicate query-step builder logic.
  Query step indexing was consolidated so each step kind no longer repeats the same push/counter shape.

- `done` Keep macro and EDN frontend parity visible.
  The test suite now has canaries that exercise equivalent literal macro and EDN string paths.

- `done` Keep benchmark status current.
  `bench/datascript_bench/README.md` and `docs/benchmarks.md` contain current DataScript comparison results and known baseline caveats.

- `done` Avoid extra `Value` array copies in parser rendering paths.
  Parser-rendered vectors now return direct `Value` literals around owned dynamic arrays when the caller already owns the array.

- `done` Use `arr.sort!` for primitive local sorts.
  `sort-strings!` and `sort-i64!` now delegate to Kvist's array sort instead of carrying local insertion sorts.

- `done` Expose public shallow cleanup for values and results.
  `delete-owned-value`, `delete-value-containers-shallow`, `delete-pull-result-shallow`, `delete-result-set-shallow`, and `delete-profiled-result-set-shallow` are now available in the `vev` package. ABI result cleanup delegates to these helpers, and query rule benchmarks use them instead of deleting only `rows`.

- `done` Define duplicate transaction function registration semantics.
  Native transaction execution now rejects duplicate tx-fn idents with a clear failed report, and the C ABI registration API rejects duplicates before allocating a callback slot.

- `done` Remove ABI transaction listener tombstones.
  ABI `unlisten` now deletes the owned listener name and removes the listener entry, matching pure Kvist listener behavior.

- `done` Add typed empty statement collections and lookup-ref collection binds.
  The C ABI now exposes string, keyword, entity, and int lookup-ref collection bind functions. Python statement bindings support explicit typed empty collections/tuples/relations and non-string lookup-ref collections.

- `done` Introduce ordered, indexed query variable collection.
  The main query variable collectors now preserve stable order while using a temporary string membership index. The older linear `append-var-once!` remains for smaller validation/update paths where carrying an index would add more complexity than it removes.

- `done` Use `set[T]` in high-volume pure membership paths.
  Recursive transitive traversal, entity-column de-duplication, and result-row de-duplication now use Kvist sets instead of `map[T]bool` where no boolean payload exists.

- `done` Add a tempid lookup table during transaction resolution.
  Transaction resolution now keeps a parallel `map[string]u64` while preserving the ordered tempid report vector, avoiding repeated scans for resolved tempids in larger transactions.

- `done` Add direct entity read helpers.
  `entity-first-value`, `entity-first-value-kw`, `entity-has-value?`, `entity-has-value-kw?`, `entity-first-ref`, and `entity-first-ref-kw` provide allocation-free first/existence reads. `entity-get`, `entity-contains?`, and `entity-ref` now delegate to those helpers instead of building full arrays.

- `done` Validate negative integer query entity terms.
  EDN text query parsing now rejects negative integer literals in entity-term positions before they can be cast to `u64`, while preserving negative integers in value positions.

- `done` Make tuple schema transaction helpers slice-based.
  `tuple-attrs-schema-tx-from` now accepts an arbitrary `[]string` of component attrs, and the existing two-attr `tuple-attrs-schema-tx` delegates to it.

- `done` Add public shallow lifecycle cleanup for prepared/query/report containers.
  `delete-query-shallow`, `delete-prepared-query-shallow`, `delete-prepared-rules-shallow`, `delete-prepared-tx-data-shallow`, `delete-tx-report-shallow`, and `delete-live-tx-report-shallow` are now canonical Vev helpers. The C ABI prepared-query free path delegates to the package helper instead of carrying a duplicate local copy.

- `done` Tighten temporary text-query cleanup.
  Direct `q-text` variants that parse a short-lived query now defer `delete-query-shallow` after execution, so temporary query container arrays are not leaked on the main EDN string API path.

- `done` Broaden Clojure/Java pull lookup-ref API shapes beyond string values.
  Direct pull lookup-ref APIs now support string, keyword, entity, and int values through the C ABI and Java wrapper. The Clojure wrapper dispatches Datomic-style lookup refs such as `[:user/email "ada@example.com"]`, `[:user/status :active]`, and `[:user/code 1001]`.

- `done` Improve C ABI value inspection helpers.
  `vev_value_map_get` and `vev_value_text_equals` now cover the common C-client map lookup/text comparison boilerplate used by pull and tx-report inspection. The C smoke delegates to those helpers instead of hand-scanning map entries.

- `done` Tighten ABI transaction builder cleanup.
  `vev_tx_free` now deletes the C-owned attr strings and value payloads held by `vev_tx_create` builders before releasing the raw wrapper array. The cleanup stays builder-specific because generic `Tx-Data` can contain borrowed package literals.

- `done` Remove global Clojure prepared-query cache.
  Ad hoc Clojure `q`, `rows`, and `scalar` calls now prepare a temporary native query handle and close it after use. Explicit `vev/prepare` remains the reuse path, avoiding cross-engine prepared handle sharing and unbounded native cache lifetime.

- `done` Add shared benchmark timing helpers.
  `bench/support` now owns elapsed-time and sample percentile helpers. Query-rule, stress, ABI-native, and index benchmarks use the shared `Timing` helpers instead of carrying local copies.

- `done` Add local builders for pull spec option variants.
  Pull spec constructors, EDN pull option parsing, and recursion-depth rewriting now use shared `pull-spec-with-*` helpers instead of manually copying every `Pull-Spec` field for each option variant.

- `done` Use a local set for cardinality-one entity/attr tracking.
  The transaction path now uses `set[string]` for the local entity/attr membership table. Helper-heavy membership paths still use `map[string]bool` until pointer-shaped set mutation is usable end-to-end in Vev.

- `done` Avoid repeated reachability scans in rule-call planning.
  Rule planning now computes the reachable rule-name set once per call plan and reuses it for call-rule filtering, recursive dependency detection, and acyclic depth. This keeps the general dependency-graph path while removing repeated `rule-reaches-name?` scans from the hot planning path.

- `done` Add a `Value-Map-Builder` for pull rendering.
  Pull map rendering now uses a small builder to centralize duplicate-key checks and map materialization instead of open-coding key scans against the raw `Value` item array.

- `done` Centralize schema property lookup.
  Keyword, boolean, and ident schema helpers now share `schema-property-value-for-entity`, giving hot schema predicate paths one EAVT property accessor that can later be backed by a cached schema view.

- `done` Use `kvist:str` helpers for EDN string parsing/rendering.
  Runtime EDN string parsing now delegates escape decoding to `kstr.unescape`, and EDN string rendering uses `kstr.builder` instead of building an intermediate dynamic array of string fragments.

- `done` Use `defiter` for EDN child traversal.
  `EDN-Doc` now has local `edn-siblings`, `edn-children`, and `edn-child-pairs` iterators for linked child-list traversal. Query and EDN text decoding paths can use direct `for` loops over child indexes instead of hand-rolled sibling cursor loops.

- `done` Use `set[T]` for ordered query-variable and binding membership indexes.
  Binding de-dupe keys, ordered query-variable collection, and primitive projection de-dupe now use `set[string]` for pure membership state instead of `map[string]bool` payload emulation.

- `done` Use `arr.repeat` for dense boolean index initialization.
  Dense transitive-rule helper arrays now use the package repeated-array helper instead of a manual fill loop.

- `done` Add a generic typed column-batch C ABI handle.
  Host adapters can now call `vev_query_db_prepared_column_batch_with_inputs` once and inspect `vev_column_batch_kind` instead of probing every exact-shape column API. The handle wraps the existing entity, string, entity/int, and entity/string/int flat layouts and exposes uniform borrowed pointer accessors.

## VevDB TODO

- `done` Finish parser-owned AST/value cleanup.
  The EDN parser keeps AST strings as borrowed source text deliberately and now cleans parser-owned nested value containers on failed recursive value, serialized DB, datom, transaction argument, lookup-ref, CAS, and partial tx-data parse paths. Failed tx text parsing also rolls back entries appended to the caller's output array.

- `done` Make host result decoding less duplicated.
  The Clojure wrapper now funnels `rows` and `q` through shared optimized-result dispatch helpers instead of repeating the entity-column, entity/int-pair, entity/string/int-triple, and generic result fallback cascade in each call shape. Java and C ABI compatibility accessors remain intentionally available.

- `done` Use set-backed visited state where linear arrays were still used for cycle tracking.
  Recursive retract now carries a `set[u64]`, wildcard/component pull recursion uses the same count-map state as explicit pull recursion, and traced pull traversal no longer copies a `u64` path array at each recursive step. Specialized transitive-rule helpers keep their own dense/set visited paths.

- `todo` Consider a map-backed `Binding` index.
  Binding lookup is order-preserving but scan-heavy. A binding could keep ordered items plus `map[string]int`, or relation join code could build a temporary lookup map for join keys.

- `todo` Consider reshaping `Query-Relation` attrs.
  Parallel `attrs` / `attr-sources` arrays couple indexes manually. A small `{name source}` record or an auxiliary source map would be clearer.

- `done` Add explicit SCC metadata for rule components.
  Rule dependency analysis now builds strongly connected component metadata from the dependency graph using DFS finish order plus reverse traversal. Recursive checks and prepared rule-call planning can ask component metadata instead of repeatedly checking pairwise mutual reachability.

- `done` Add a component-local memoized rule fixpoint for positive rules.
  Recursive rule calls whose reachable rule set is plain positive Datalog, currently data clauses plus rule calls with no source-qualified calls, can use a memo table keyed by rule name/params and iterate to a local fixpoint. This covers non-linear recursive rule bodies that are not handled by the linear/alternating transitive recognizers.

- `done` Add a conservative delta path for positive recursive rules.
  Positive recursive components now use accumulated memo tables plus per-iteration delta tables. Bodies with multiple recursive rule calls are evaluated once per recursive call position with that position reading the delta table and the other positions reading accumulated memo rows. This avoids re-probing the full memo each iteration for the common semi-naive shape.

- `done` Add set-backed rule memo duplicate detection.
  Rule memo entries now keep a `seen` key set next to the accumulated binding table, so primitive rule outputs avoid linear `binding-exists?` scans on insert. Structural scan fallback remains for output bindings that cannot be represented by the primitive binding key.

- `done` Cache typed relation views for recursive rule memo/delta tables.
  Rule memo entries now own cached typed `Query-Relation` views for accumulated rows and current delta rows. Broad rule-call joins reuse those typed views and fall back to the row projection path for unsupported call shapes, while small current relations still use the cheaper row-wise matcher.

- `done` Append primitive-compatible rule memo outputs into valid typed caches.
  When a memo or delta relation view is already valid, new primitive-compatible rule outputs are appended directly to the cached typed columns. Unsupported values invalidate the view and rebuild through the conservative row source on the next broad join.

- `done` Keep compatible multi-branch rule-call unions typed.
  Broad rule-call application now accumulates compatible typed branch joins into a typed `Query-Relation` instead of always materializing each branch through `Binding` rows. If a branch falls off the typed path or has an incompatible layout, the accumulator flushes through the audited materialization helper and continues on the conservative row path.

- `done` Keep compatible materialized helper-rule branch output typed and deduped.
  Materialized non-recursive helper rules now project branch outputs into typed relations when possible and append them through a typed unique accumulator keyed by projected columns. Unsupported projections flush through the audited materialization helper and keep the existing `unique-bindings` fallback.

- `done` Stream recursive rule body results into memo insertion.
  Positive recursive rule fixpoint loops now append directly from the `Query-Relation` produced by rule-body evaluation. Typed-only relations create one temporary binding row at a time for memo insertion instead of allocating a full materialized result array before appending.

- `done` Normalize transaction macro entity dispatch.
  Literal transaction macro paths for add/retract, value-less attr retract, and entity retract now share one entity dispatch helper for lookup refs, current-tx/tempid strings, idents, and numeric entity ids instead of repeating the same matrix in each macro branch.

- `todo` Consolidate ABI exported query/bind variants.
  Several exported collection/query functions repeat null checks, prepared-query checks, input parsing, cleanup, and result dispatch. Add local helpers or Vev macros before extending the matrix further.

- `done` Adopt column batches in host adapters.
  Java `DB.queryColumns`, Python `DB.query_columns`, Rust `Db::query_columns`, Go `DB.QueryColumns`, and the Clojure optimized query path now prefer the generic column-batch handle for flat prepared query results, then fall back to the generic result API. Java, Python, Rust, and Go also expose bound statement column batches over live connections and/or immutable DB snapshots where their adapter has a statement type. Exact-shape C functions remain available for low-level callers.

- `todo` Add generic query/parser AST visitors.
  Source validation, source-input validation, relation-DB query rewriting, and EDN query section parsing all hand-walk the same query or EDN shapes. A reusable visitor/mapper plus single-pass section indexing would reduce duplicate traversal logic.

- `partial` Build reusable physical query operators.
  The first reusable physical operator is `Clause-Index-Scan`, which resolves a clause once, selects the DB index/range once, and streams matching datom indexes without allocating a candidate array. Relation clause production, row-binding clause execution, selectivity candidate counting, single-clause typed anti-join matching, simple typed `or` branch matching, transitive traversal helpers, and the generic source-aware typed bound-clause path now consume that scan directly. Source-input relation clauses also build `Query-Relation` rows and typed columns directly instead of first materializing a binding array and cloning it into a relation, and bound source-input clauses now extend existing typed rows directly. Initial no-input, scalar `:in`, and simple collection `:in` query relations also build typed rows directly, with richer input shapes falling back to compatibility binding expansion. Typed row-producing operators now share `Query-Relation-Builder` for column materialization and cleanup across predicate filters, `not`, `or`, function clauses, `ground`, `get-else`, `get-some`, bound-clause scans/fallback, relation-source extension, and rule-call fallback. Typed product and typed hash joins now fill output columns directly and leave compatibility `Binding` rows empty until a binding-only consumer materializes through `query-relation-materialized-bindings`, including both borrowed `Query-Relation` inputs and converted `Typed-Relation` fallback inputs. Provably empty typed joins, including empty inputs and incompatible common column kinds, return an empty typed joined relation before the generic binding fallback. Scalar built-in function clauses, tuple function output for typed built-ins such as `vector`/`tuple`, nested tuple and collection destructuring for `ground` and typed function outputs, scalar `ground`, collection fanout `ground`, tuple `ground`, relation `ground`, single ordinary DB-clause `not`, plain `not-join`, plain multi-clause DB `not` including source-qualified clauses, plain branch-local predicate/function pipelines for typed-supported operators, nested plain branch-local `not` pipelines, single-clause `or` branches, plain multi-clause DB `or` branches including source-qualified clauses, plain `or-join` branch pipelines, plain branch-local source-input pipelines, relation-source extension, `get-else`, and `get-some` now resolve typed inputs and append/filter typed columns without converting every input row to a `Binding`; dynamic op vars, native callbacks, complex relation-source negative or branch groups, branch-local operators outside the typed evaluator, and non-columnar values intentionally fall back. Generic DB clause scans resolve scan ranges directly from typed columns, have a typed candidate row matcher, and append matching candidate rows directly into output typed columns without allocating one temporary binding per datom while preserving repeated-variable and reverse-attribute semantics; filter-only clauses also skip the produced-value array. Unbound DB clause relation construction now has the same typed-first shape: it streams scan candidates, checks wildcard/value/lookup-ref, reverse-attribute, tx/op, and repeated-variable semantics directly against each datom, and fills projected clause-variable columns without compatibility rows, falling back to the binding-backed constructor only for non-columnar values. Same-entity star scans now have an initial relation-native operator for all-current cardinality-one shapes with fixed-value filters and one or two projected attrs; it aligns `AVET` filter streams and `AEVT` output streams by entity id and fills normal typed `Query-Relation` columns directly. Binding fallback product/hash/nested-loop joins now materialize typed-only inputs through `query-relation-materialized-bindings` before tuple iteration, so typed-only producers remain correct when they hit conservative join paths. General rule-call projection for typed rule-result and memo/delta parameter relations now writes repeated-var, constant, and wildcard projections directly into typed output columns instead of allocating a temporary `Binding` for each row. Trusted-unique typed result rendering also skips per-row dedupe arrays. Simple no-pull aggregate rendering now reads group keys, `:with` keys, dedupe keys, and aggregate input values directly from typed columns, with custom/function-var/limit-var/pull cases falling back to binding materialization. Pull find rendering can also resolve pull entity vars from typed rows and render pull results directly from the selected DB/source before falling back to binding materialization. Remaining work: broader star/merge-scan shapes, richer branch-local relation-source join/dynamic pipelines, deeper pull/host result materialization, and reducing the remaining fallback projection operators that still need binding materialization.
  Latest source-input cleanup: initial relation-source producers no longer allocate one temporary `Binding` per source row. They use a small row-local var/value table, preserve repeated-var and constant semantics, and append projected vars directly into typed columns.

- `done` Cache prepared rule planning data.
  `Query` now owns cached `Rule-Call-Plan` values. Prepared queries build those plans when rules are attached, and execution reuses them by rule-call step index instead of rebuilding dependency graphs and transitive-shape recognition on every prepared run. Deeper SCC/component metadata remains tracked separately under rule component planning.

- `done` Add a rule lookup/index structure for planning.
  Prepared rule-call planning now builds one rule-name index for the query's rules and reuses it while constructing dependency graphs for every cached call plan. Execution still preserves original rule ordering by filtering the source rule array after reachability is known.

- `done` Extend rule indexes to validation and arity checks.
  Rule-call known checks, arity checks, rule definition validation, required-binding validation, ordered query validation, and planned rule-body readiness checks now reuse the rule-name index instead of scanning unrelated rule branches by name/arity in each path. Wrapper helpers remain for call sites that do not already own an index.

- `done` Make index order a typed helper.
  Public datom index APIs now convert order strings once to a typed `Public-Index-Order` and use `db-index-slice` to select `eavt`, `aevt`, `avet`, or `vaet`. Datoms, seek, and reverse-seek share the same typed dispatch path while preserving the public `:eavt`/`:aevt`/`:avet`/`:vaet` API.

- `partial` Add structured parser diagnostics and malformed-input suites.
  Portable prepared parser values now include stable `:error-code` categories across binding, `:in`, `:with`, clause, rules, query, pull-pattern, and tx-data parser entry points, including `:edn-read` for reader-level malformed EDN across query, rules, pull, and tx-data values. Prepared query values also retain and render return-map marker plus typed key metadata for `:keys`, `:strs`, and `:syms`, and direct `parse-clause-text` exposes single where-clause parser values. Remaining work is exact malformed-input namespace coverage and DataScript/Clojure parser record or diagnostic text parity where that is worth exposing.

- `done` Add test support helpers for Vev values and results.
  Vev tests now have row-level `Value` matchers for entity, string, integer, and arbitrary expected values. Existing result search helpers delegate through those matchers, giving compatibility tests a less verbose pattern for result-row assertions without introducing a larger fixture DSL.

- `partial` Materialize pull values more cleanly for ABI results.
  ABI results currently keep pull structures in the result plus a side array of rendered pull `Value`s. The side array now stores per-row pull offsets, so `vev_result_pull` is O(1) instead of scanning previous rows to find the flattened pull value. A single owned materialized result representation would still simplify pull result access and cleanup further.

## Kvist / Compiler / Package Work

- `kvist-done` Optimize ordinary `for` over eager bounded `arr` producers.
  Kvist now lowers ordinary direct `for` sources over `arr.range`, `arr.repeat`, `arr.repeatedly`, `arr.iterate`, `arr.cycle`, and `arr.take-nth` to direct loops without allocating helper arrays. Vev's existing `while` workarounds can stay where they are clearer, but new ordinary loops no longer pay the eager-array cost for these source forms.

- `kvist-done` Comparator/key sorting with captures.
  Kvist now supports captured inline `fn` key functions for `arr.sort-by` and `arr.sort-by!`, using explicit capture-aware sort helpers. Vev may still keep custom datom and `Value` sorting where it needs non-key comparator semantics, but captured key sorting no longer blocks ordinary package use.

- `not-now` ABI metadata/header generation.
  `include/vev.h`, Python signatures, Java/JNA bindings, and Rust declarations mirror the Kvist ABI manually. A sidecar generator from exported declarations would reduce drift, but the current manual surface is acceptable unless drift becomes a concrete maintenance problem.

- `not-now` Better C ABI glue ergonomics.
  Vev's ABI layer needs raw Odin for wrapper structs, callback proc types, pointer casts, and repeated `runtime.default_context()` setup. This is genuine friction, but the current cases are mostly Odin interop surface area and exported-ABI boilerplate rather than a small package/compiler improvement. Prefer Vev-local helper macros or code generation if the ABI layer keeps growing; do not add new Kvist interop syntax without a separate design.

- `not-now` Captured C callback ergonomics.
  ABI transaction callbacks currently need a fixed trampoline table, while tx listeners already store callback/user pairs directly in raw Odin. Removing the tx-function slot limit is a Vev ABI/runtime representation change unless Kvist gets first-class host callback wrapping. Leave this as-is unless the fixed slot count becomes a concrete product limit.

- `not-now` Shared macro/runtime parser descriptions.
  Query, pull, and tx syntax must exist both as Kvist literal macros over source forms and runtime EDN text parsing over `EDN-Doc` nodes. A shared parser description or codegen story could reduce parity drift, but it would be a new language/tooling design rather than a small compiler/package cleanup. Leave this alone unless concrete parity bugs show that tests are not enough.

- `kvist-done` Record update syntax.
  Kvist already has `assoc` and `update` for shallow struct copy-with-field-changed code, including threaded forms such as `(-> spec (assoc .children children))`. Pull spec variants and similar record updates can use those helpers instead of hand-copying records.

- `kvist-done` Ownership-transfer annotations for consuming helper functions.
  Kvist now infers consuming parameters from ordinary bodies. A helper like
  `value-vector-owned(items: [dynamic]Value) -> Value` becomes consuming when
  it explicitly deletes `items` or transfers it through a proven owning
  result; callers then move tracked owned locals without a declaration form.

- `not-now` Static lookup tables shared between macro and runtime code.
  Predicate/function/aggregate operator tables exist as macro allow-lists and runtime string dispatch. A Vev-local macro source of truth could reduce recognition-list drift, but it would not remove the runtime behavior dispatch and is not worth the extra abstraction right now.

- `kvist-done` Macro string/number helpers for source parsing.
  Kvist macros now have `parse-int` / `str.parse-int` and `digit?` / `str.digit?` helpers for source-string parsing. `parse-int` returns an integer on success and `nil` on failure, preserving `0` as a truthy parsed value in macro conditionals.

- `kvist-done` String builder/unescape helpers.
  `kvist:str` now has `str.builder`, `str.write!`, `str.finish`, `str.destroy!`, and `str.unescape`. Vev uses these for EDN string escape decoding and scalar string rendering; broader recursive value rendering should wait for a clearer owned-string result convention.

- `not-now` Standard Option/Maybe type.
  Vev uses value-plus-`has-*` fields and raw sentinel values in schema attrs, index args, input binding parsing, and absent `Value` results. Do not introduce a standard Option/Maybe abstraction for this now; Kvist's existing multi-return `[value ok]` style and explicit fields are acceptable.

- `kvist-done` Array fill/repeat helpers.
  `arr.repeat` already covers owned repeated arrays, and Kvist now has `arr.fill!` for in-place slice/dynamic-array initialization. Vev uses `arr.repeat` for dense boolean index initialization.

- `kvist-done` Pointer-to-set helper signatures usable for mutation.
  Kvist now lowers `core.get`, `core.delete!`, `map.dissoc!`, and `contains?` correctly for pointer-to-map targets, which also covers `^set[T]` after set lowering. `set.contains?` forwards through the pointer-aware core membership form, so Vev can use ordinary `set.contains?` spelling with value sets and pointer-shaped helper signatures.

- `kvist-done` Better macro-time collection utilities.
  Kvist macros now have a macro-time `reduce` helper over source form collections, plus macro-time `+` for numeric accumulators. Literal tx/pull-style macros can fold over option and clause forms instead of enumerating every ordering by hand.

- `kvist-done` Inferred lifetime boundaries without a managed-type protocol.
  Kvist infers allocating results, borrowed views, and consuming parameters
  from ordinary bodies. Vev does not annotate types or install behavior through
  `Type-destroy`/`Type-clone` naming. `Prepared-Pull-Pattern` intentionally
  retains its explicit `owns-source` bit and cleanup procedure because it is an
  opaque native aggregate assembled outside a typed Data-decoding boundary.
  Its internal owning scopes use ordinary `defer` cleanup. Likewise,
  `query-relation-builder-add-binding!` deletes a rejected binding explicitly;
  the compiler infers that consuming path for callers without changing the
  `Binding` type. Continue removing redundant cleanup only where inference is
  proven by executable lifetime tests, not by adding Vev-specific compiler
  behavior.

  The audit also made two previously ungated test files executable again.
  `index_storage_test.kvist` still has 35 failures on untouched Vev main because
  its transaction-partition expectations and manual shared-snapshot cleanup
  predate the current storage model. `source_branch_test.kvist` likewise has ten
  unchanged baseline failures around typed-plan counters and legacy result
  ownership. These are not regressions from managed ownership; keep them as a
  separate modernization task rather than changing semantics opportunistically
  during ownership migration.

## Later Architecture

- `later` Revisit manual tagged structs.
  `Term`, tx EDN entities, input bindings, query inputs, pull visits, native query functions, rule call strategies, ground clauses, aggregate find specs, tx function callbacks, index args, and EDN nodes use kind enums plus payload flags. Some can become `defunion`, but broad conversion is not urgent and may affect ABI or serialization expectations.

- `later` Add stronger tx data invariants.
  `Tx-Data` is a wide struct with `op` string and many flags. At minimum it wants an op enum; longer-term it may want smaller entity/value-ref variants.

- `later` Use `keyword` or domain-specific distinct string types more deeply.
  First-class Kvist keywords are now available, but Vev still stores many symbolic DB values as strings for compatibility with EDN text and ABI surfaces. Convert only where it improves invariants without adding wrapper churn.

- `later` Replace string dedupe keys with comparable key structs.
  Row and binding dedupe use length-prefixed strings. Struct keys would avoid formatting and make collisions structurally impossible, but this needs careful map-key support and benchmarking.

- `later` Use an EDN writer/builder.
  Serialization currently builds string parts and concatenates. This is real cleanup, but not on the critical path unless serialization becomes hot or harder to maintain.

- `later` Revisit `DB` and entity borrow semantics.
  `DB`, `DB-Source`, and `Entity` are value structs carrying dynamic-array headers. A distinct borrowed DB handle/reference type could make owner vs view semantics clearer, but this needs an API-wide ownership decision.

- `later` Revisit EDN document child storage.
  `EDN-Doc` stores children as linked sibling indexes in one node array, which forces linear `edn-child-at` and cursor loops. Child spans or child-index arrays would better match Kvist slice-heavy traversal.

- `done` Add generic typed result/column batches.
  The C ABI exposes a native one-call column batch/result handle with typed column accessors. Java, Python, Rust, Go, and the Clojure optimized query path use that generic batch path for flat prepared query results before falling back to the generic result API. Java, Python, Rust, and Go also expose bound statement column batches for the adapters that have statement handles. Exact-shape low-level C functions remain available, but the public host adapter direction is now the generic column batch handle.

- `later` Consolidate transitive graph execution.
  Forward/reverse adjacency construction, sparse/dense BFS, unbound-start emission, and alternating traversal all carry similar graph-walk logic. A graph traversal helper should come with the broader physical-operator layer.

- `later` Normalize EDN value decoding modes.
  Normal EDN value conversion and serialized-value conversion are nearly the same recursive decoder with a few tag hooks. A parameterized decoder mode would reduce duplication once the parser surface stabilizes.

- `later` Decide canonical map ordering.
  Map equality is order-insensitive, while map ordering compares stored item arrays. Canonical map storage or a map-specific comparator would make equality and ordering semantics line up.

- `later` Generate ABI handle/accessor declarations.
  The handle/accessor pairs are mechanical. This is a good macro-generation target once the ABI shape stabilizes further.

- `later` Generate value-wrapper APIs.
  `q-*value*` wrappers mostly delegate to result-returning APIs plus `result-set-value`. A macro can generate these once the public surface stops moving.

- `later` Improve tests with table assertions.
  Some long indexed assertions could use `t.are`, but this is cleanup rather than product progress.

## Not Now

- `not-now` Replace all simple build-output loops with transforms.
  Some parser rendering helpers benefit from owned constructors, but many query loops need early returns, ownership cleanup, mutable stats, or index bounds. Manual loops are fine there.

- `not-now` Convert every local membership helper to generic `contains?`.
  Use package helpers where it clarifies code. Keep specialized helpers when they encode typed semantics or avoid repeated conversions.

- `not-now` Broad wrapper-matrix collapse.
  Query and pull variants are intentionally explicit while the API is still being shaped for C, Java, Python, Clojure, Rust, and Kvist. Macro generation should come after the final public API settles.

- `not-now` Replace all raw `core:strings` calls with `kvist:str`.
  Prefer `kvist:str` where it makes code clearer, but mixed `core:strings` usage is not worth a dedicated cleanup pass unless the surrounding code is already changing.
