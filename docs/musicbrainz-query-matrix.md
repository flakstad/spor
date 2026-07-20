# MusicBrainz Query Matrix

This matrix tracks Vev coverage against the MusicBrainz parts of the Datomic
sample material:

- `Datomic/day-of-datomic-conj/src/music_brainz.clj`
- `Datomic/day-of-datomic/tutorial/query.clj`
- `Datomic/mbrainz-sample/schema.edn`
- `Datomic/mbrainz-sample/resources/rules.edn`

The goal is tutorial compatibility first: a Datomic user should be able to read
the workshop query and write the same query against Vev's EDN text API, with
only host wrapper syntax changed.

## Current Harness

`src/vev_tests/musicbrainz_test.kvist` is the active mini workload. It runs the
same assertions against:

- an in-memory connection
- a SQLite-backed connection after commit, close, reopen, and query

The mini dataset includes countries, artist enum idents, artists, releases,
media, and tracks. It intentionally uses the same core attr names as
`mbrainz-sample`, including:

- `:artist/name`, `:artist/gid`, `:artist/type`, `:artist/gender`,
  `:artist/country`, `:artist/startYear`, `:artist/startMonth`,
  `:artist/startDay`
- `:release/name`, `:release/year`, `:release/artists`, `:release/country`,
  `:release/media`, `:release/artistCredit`
- `:medium/tracks`, `:medium/trackCount`, `:medium/position`, `:medium/name`
- `:track/name`, `:track/duration`, `:track/artists`, `:track/position`

The restored Datomic 1968-1973 sample is also available locally through
`scripts/musicbrainz_sample.sh`. The current real-data bridge exports
Vev-compatible EDN from Datomic with compact remapped entity ids and UUID
values preserved as UUID literals. `bench/musicbrainz_import_subset.kvist`
imports either a single tx file or staged schema/value tx files.
`bench/musicbrainz_query_profile.kvist` can now run either the deterministic
mini fixture or the imported real subset.
`scripts/musicbrainz_clojure_vev_matrix.sh` runs the public Clojure wrapper
matrix through `vev.core`, Java FFM, the C ABI, and `libvev`.
`bench/musicbrainz_import_subset.kvist --sqlite-output <path>` can create the
durable Vev DB that the host wrapper opens with `--uri` for query-only timing.

Real-data import status:

| Workload | Status | Notes |
| --- | --- | --- |
| 100-item single-file subset | Passing | Confirms compact eid remap and UUID/value parsing |
| 500-value staged subset | Passing | Confirms schema-first/value-second import path |
| 5,000-value staged subset | Passing | Bulk explicit-id transaction path is practical; latest local run is about 0.55s total |
| 50k/100k/200k/400k staged subsets | Passing | Latest 400k local run is about 6.9s total |
| Full 763,274-item subset | Passing | Chunked staged import preserves expected tutorial rows; latest local import is about 16.5s |

Real-data query comparison against local Datomic is active and the full current
matrix passes:

```bash
scripts/compare_musicbrainz_query_matrix.sh --workload all --samples 1 --warmups 0
```

Latest full verifier status: all listed rows match Datomic by row count and
portable fingerprint.

| Workload | Vev rows/fingerprint | Datomic rows/fingerprint | Status | Current signal |
| --- | --- | --- | --- | --- |
| `musicbrainz-real-release-first` | `96 / 0ea8943f9ef3eb03` | `96 / 0ea8943f9ef3eb03` | Equal rows | Dependency-aware clause planning now keeps this selective and fast |
| `musicbrainz-real-track-first` | `89 / 9902d35f51335e40` | `89 / 9902d35f51335e40` | Equal rows | Clause order no longer creates the large track/release cross product |
| `musicbrainz-real-john-lennon-pre-1970-tracks` | `18 / 4598839c2af58631` | `18 / 4598839c2af58631` | Equal rows | Day-of-Datomic final query-stats example with release/media/track traversal |
| `musicbrainz-real-beatles-releases` | `16 / c57b012eecfd45ed` | `16 / c57b012eecfd45ed` | Equal rows | Constant artist lookup plus release join is fast in Vev |
| `musicbrainz-real-beatles-short-track-collection` | `140 / 50498f806d973af7` | `140 / 50498f806d973af7` | Equal rows | Collection find spec `:find [?track-name ...]` over real track rows |
| `musicbrainz-real-abbey-road-release-date-tuple` | `1 / 732a43b4c30e7be0` | `1 / 732a43b4c30e7be0` | Equal rows | Tuple find spec `:find [?year ?month ?day]` selected by Datomic-style `#uuid` literal |
| `musicbrainz-real-beatles-start-year-scalar` | `1 / 0000000363d12a10` | `1 / 0000000363d12a10` | Equal rows | Scalar find spec `:find ?year .` over artist start year |
| `musicbrainz-real-abbey-road-track-minutes` | `17 / 0f96f2c36020d31d` | `17 / 0f96f2c36020d31d` | Equal rows | Query function expression `(quot ?millis 60000)` over real track durations |
| `musicbrainz-real-miles-enum-id` | `1 / 732425642d9c79c5` | `1 / 732425642d9c79c5` | Equal rows | Enum refs joined through `:db/ident` plus UUID projection |
| `musicbrainz-real-beatles-track-count` | `1 / 0000000007068a26` | `1 / 0000000007068a26` | Equal rows | Bounded aggregate over real imported data |
| `musicbrainz-real-beatles-min-max-duration` | `1 / 9c45e54f061af2f6` | `1 / 9c45e54f061af2f6` | Equal rows | Bounded min/max aggregate over real imported data |
| `musicbrainz-real-beatles-duration-stats` | `4 / 9880798d00baf3e0` | `4 / 9880798d00baf3e0` | Equal rows | Grouped median/avg aggregate with `:with` duplicate preservation over real track durations |
| `musicbrainz-real-beatles-duration-stddev` | `4 / 1de88b32d5193758` | `4 / 1de88b32d5193758` | Equal rows | Grouped stddev aggregate with normalized six-decimal float fingerprints |
| `musicbrainz-real-beatles-duration-sum` | `4 / 773afe226788bffa` | `4 / 773afe226788bffa` | Equal rows | Grouped sum aggregate with `:with` duplicate preservation over real track durations |
| `musicbrainz-real-lookup-country` | `1 / 4167e0bf9abd1220` | `1 / 4167e0bf9abd1220` | Equal rows | Vev uses inline lookup-ref syntax; Datomic side uses equivalent entity pattern |
| `musicbrainz-real-selected-artists-releases` | `28 / 4887ecaa409643d2` | `28 / 4887ecaa409643d2` | Equal rows | Collection input binding over two artist names |
| `musicbrainz-real-release-date` | `3 / 8853c19c0b82edfa` | `3 / 8853c19c0b82edfa` | Equal rows | Tuple-shaped release date projection over selected releases |
| `musicbrainz-real-fallback-start-month` | `2 / ea197a760bcc6589` | `2 / ea197a760bcc6589` | Equal rows | `get-else` over selected artists with mixed present/default values |
| `musicbrainz-real-get-some-country` | `1 / 7e762f127575592a` | `1 / 7e762f127575592a` | Equal rows | `get-some` returns the schema attr entity and joins through `:db/ident` |
| `musicbrainz-real-missing-start-year` | `1637 / f5e245cdd9911040` | `1637 / f5e245cdd9911040` | Equal rows | Tutorial `missing?` query over artists lacking `:artist/startYear` |
| `musicbrainz-real-dynamic-attr` | `482 / ffee4f7469006cd3` | `482 / ffee4f7469006cd3` | Equal rows | Dynamic attr input binding over `:artist/country` |
| `musicbrainz-real-top-duration` | `1 / 949eb8db5ef70199` | `1 / 949eb8db5ef70199` | Equal rows | Top-n min/max aggregates over all track durations |
| `musicbrainz-real-not-beatles-male` | `1 / ea45bdc7e8b8201b` | `1 / ea45bdc7e8b8201b` | Equal rows | Bounded `not` query uses planned group clauses |
| `musicbrainz-real-or-two-artists` | `2 / de67eb0f77cf6b42` | `2 / de67eb0f77cf6b42` | Equal rows | Bounded `or` query uses planned branch clauses |
| `musicbrainz-real-relation-artist-release` | `2 / cb2f30e6783d093d` | `2 / cb2f30e6783d093d` | Equal rows | Relation tuple input for artist/release pairs |
| `musicbrainz-real-not-join-release` | `1 / b6368059dfc36ef8` | `1 / b6368059dfc36ef8` | Equal rows | Bounded `not-join` over selected releases uses planned group clauses |
| `musicbrainz-real-or-join-release` | `2 / 5f5db031e99d9c11` | `2 / 5f5db031e99d9c11` | Equal rows | Bounded `or-join` over selected releases uses planned branch clauses |
| `musicbrainz-real-map-beatles-releases` | `16 / c57b012eecfd45ed` | `16 / c57b012eecfd45ed` | Equal rows | Vev uses EDN map query text; Datomic harness uses the equivalent vector query |
| `musicbrainz-real-keys-beatles-releases` | `16 / 2476cdd6c54275f1` | `16 / 2476cdd6c54275f1` | Equal rows | Datomic-style `:keys` return-map rows compare as map-shaped results |
| `musicbrainz-real-strs-beatles-releases` | `16 / 3fda7a2cf91332d1` | `16 / 3fda7a2cf91332d1` | Equal rows | Datomic-style `:strs` return-map rows compare as map-shaped results |
| `musicbrainz-real-syms-beatles-releases` | `16 / 18143fc0c84f8091` | `16 / 18143fc0c84f8091` | Equal rows | Datomic-style `:syms` return-map rows compare as map-shaped results |
| `musicbrainz-real-rule-track-info` | `90 / 5f20ceb057e27418` | `90 / 5f20ceb057e27418` | Equal rows | Pure rule-body planner keeps the composed track/release join selective |
| `musicbrainz-real-rule-short-track` | `135 / ea50e22c017fe85c` | `135 / ea50e22c017fe85c` | Equal rows | Rule with host input `?max` plus predicate body over real track durations |
| `musicbrainz-real-pull-release` | `5 / 974ce160e8be7539` | `5 / 974ce160e8be7539` | Equal rows | Pull expression in query result over selected release names |
| `musicbrainz-real-dynamic-pull-release` | `17 / 16930ebda61a7b2c` | `17 / 16930ebda61a7b2c` | Equal rows | Day-of-Datomic `d/query`-style pull pattern supplied through `:in` |
| `musicbrainz-real-pull-release-nested` | `5 / f4f5c38625cab0c7` | `5 / f4f5c38625cab0c7` | Equal rows | Nested pull query over release media and tracks |
| `musicbrainz-real-direct-pull-artist` | `1 / 0a11a6da90ea3115` | `1 / 0a11a6da90ea3115` | Equal rows | Direct pull by `:artist/gid` lookup ref |
| `musicbrainz-real-direct-pull-artist-wildcard` | `1 / 996526d8caead8bb` | `1 / 996526d8caead8bb` | Equal rows | Direct wildcard pull `[*]` by `:artist/gid`; fingerprints strip imported `:db/id` values because Vev remaps Datomic eids |
| `musicbrainz-real-direct-pull-artist-releases` | `1 / 78d748d66cc33844` | `1 / 78d748d66cc33844` | Equal rows | Direct reverse-ref pull through `:release/_artists` by `:artist/gid` lookup ref |
| `musicbrainz-real-direct-pull-artist-releases-limit` | `1 / cc1f2e27d4ab3f6f` | `1 / cc1f2e27d4ab3f6f` | Equal rows | Pull `limit` option over reverse `:release/_artists` many-valued relationship |
| `musicbrainz-real-direct-pull-artist-default` | `1 / 90667f13a2d95b66` | `1 / 90667f13a2d95b66` | Equal rows | Pull `default` option over missing `:artist/gender` on The Beatles |
| `musicbrainz-real-direct-pull-artist-alias` | `1 / b9c707e2c34fb125` | `1 / b9c707e2c34fb125` | Equal rows | Pull `:as` aliasing plus `:default` over missing `:artist/gender` |
| `musicbrainz-real-direct-pull-many-artists` | `2 / 3b0d165020d81f40` | `2 / 3b0d165020d81f40` | Equal rows | Direct pull-many by `:artist/gid` lookup refs |
| `musicbrainz-real-direct-pull-release` | `1 / 4e62d7d5775bd426` | `1 / 4e62d7d5775bd426` | Equal rows | Direct nested pull by `:release/gid` lookup ref |

The row fingerprints are generated from sorted projected EDN-ish row keys.
Floating values are serialized with Vev's explicit `[:vev/float "..."]` shape
on both sides before fingerprinting. Workloads that intentionally compare
floating statistical aggregates can opt into scaled normalized float tokens, as
the stddev row does. Pull comparison rows keep Vev pull
patterns in canonical attr order where Datomic map rendering sorts keys, so row
fingerprints remain strict equality checks. Wildcard pull rows strip `:db/id`
from fingerprinting because the MusicBrainz exporter deliberately remaps
Datomic eids into compact Vev ids. Both initial clause-order queries have also
been checked with explicit sorted row dumps and `diff`.

Use `scripts/compare_musicbrainz_query_matrix.sh --workload <name-or-suffix>`
to verify selected rows against Datomic. The script builds the Vev profiler,
runs both engines, and fails if any Datomic workload has a different Vev row
count or fingerprint. `--workload all` verifies the full current matrix.

The Datomic comparison currently measures native Vev query/profile binaries
against Clojure Datomic peer queries. The public Clojure Vev wrapper path is
tracked separately by `scripts/musicbrainz_clojure_vev_matrix.sh`. Its default
500-value smoke verifies host API correctness and query overhead, but wrapper
EDN transaction loading is not yet the right full-size MusicBrainz setup path:
full host comparison uses a prebuilt SQLite-backed Vev database via `--uri`
before timing Clojure query calls.

The durable-open Clojure wrapper matrix now covers the full 43-row
MusicBrainz query/pull workload and matches the native/Datomic matrix
fingerprints. This verifies the non-Kvist EDN path for tuple/scalar/collection
find specs, relation inputs, return maps, rules, `not`/`or`, direct pull,
pull-many, lookup-ref pull, and dynamic pull pattern inputs. The dynamic pull
pass fixed an input ownership bug where pull pattern strings parsed from EDN
input text could outlive their parser document and render corrupted pull keys.
The wrapper harness uses row-preserving `vev/rows` for query pull expressions
so repeated pull maps do not collapse under Clojure set equality. Direct pull
and pull-many workloads in the host wrapper matrix prepare pull patterns once
per workload run through the public prepared pull-pattern handle exposed by the
C ABI, Java wrapper, Clojure wrapper, Python wrapper, Rust wrapper, and Go
wrapper. The same-attribute UUID lookup-ref pull-many case also uses a batch C
ABI entry point so Clojure callers do not fall back to one native direct-pull
call per entity.

## Covered

These workshop shapes are covered by passing Vev tests:

| Shape | Upstream example | Vev coverage |
| --- | --- | --- |
| Basic release-by-artist join | `query.clj`, `music_brainz.clj` | `q-text` |
| Reverse refs | mbrainz-style release artists | `:release/_artists` |
| Prepared scalar input | `:in $ ?artist-name` | `prepare-query-text` plus EDN input text |
| Collection binding | `:in $ [?artist-name ...]` | `query-input-collection` |
| Tuple binding | `:in $ [?artist-name ?release-name]` | `query-input-collection` tuple value |
| Relation binding | `:in $ [[?artist-name ?release-name]]` | `query-input-relation` |
| Relation find spec | `:find ?artist-name ?release-name` | `q-text` result rows |
| Collection find spec | `:find [?release-name ...]` | mini fixture plus restored-sample comparison row |
| Tuple find spec | `:find [?year ?month ?day]` | mini fixture plus restored-sample comparison row |
| Scalar find spec | `:find ?year .` | mini fixture plus restored-sample comparison row |
| Return maps | `:keys artist release` | `q-text-keys` |
| Predicate expressions | `[(< ?year 1970)]`, `[(> ?duration ...)]` | query predicates |
| Function expressions | `[(quot ?millis 60000) ?minutes]` | mini fixture plus restored-sample comparison row |
| `get-else` | workshop query examples | EDN text query |
| Enum refs through `:db/ident` | artist type/gender query | mini fixture plus restored-sample comparison row |
| Aggregates | min/max, sum, count/count-distinct | EDN text aggregate queries |
| Statistics aggregates | median, avg, stddev by release year | EDN text aggregate query; median/avg/stddev and grouped sum have restored-sample comparison rows |
| Nested pull | release media and tracks | `pull-text` plus real Datomic comparison rows |
| Reverse-ref pull | artist to releases via `:release/_artists` | direct lookup-ref pull plus restored-sample comparison row |
| Pull limit option | `(limit :release/_artists 2)` | restored-sample comparison row |
| Pull default option | `[:artist/gender :default "group"]` | restored-sample comparison row |
| Pull alias option | `[:artist/name :as :artist]` | restored-sample comparison row |
| Dynamic pull pattern input | `music_brainz.clj` | `pattern` supplied through `:in` in query result pull expressions |
| Pull all `[*]` | `music_brainz.clj` | wildcard `pull-text` plus restored-sample id-insensitive comparison row |
| Rule input `%` | `track-release`, `track-info`, `short-track` | `q-text-with-rules`; real Datomic comparison rows cover `track-info` and input-parameter `short-track` |
| `d/query` map query form | `music_brainz.clj` | EDN map-form query text |
| Split/composed rules | `music_brainz.clj` `track-artist`/`track-release`/`track-info` | `q-text-with-rules` |
| `not` and `not-join` | original `query.clj` | mbrainz-shaped EDN text queries |
| `or` and `or-join` | original `query.clj` | mbrainz-shaped EDN text queries |
| `get-some` | original `query.clj` | mini fixture and restored-sample attr-id semantics covered |
| `missing?` | original `query.clj` | mini fixture and restored-sample comparison row |
| Lookup-ref inputs | original `query.clj` country examples | inline lookup-ref and query input lookup-ref |
| Dynamic attr input | original `query.clj` | `:artist/country` as collection input |
| Tagged UUID literals | Datomic EDN reader spelling | `#uuid "..."` accepted in tx/query/pull-compatible EDN values |
| Top-n aggregates | original `query.clj` | min/max duration vectors |
| Query profiling | `music_brainz.clj` query-stats walkthrough | Vev profile assertions on tutorial-shaped joins |
| Query-stats final production query | `music_brainz.clj` John Lennon pre-1970 tracks | real Datomic comparison row plus mini profile assertion |
| Clause-order profiling | `music_brainz.clj` comparison examples | `bench/musicbrainz_query_profile.kvist` |
| Host-facing `d/query` equivalent with `:query`/`:args` | `music_brainz.clj` | Clojure `vev/query` and Java `Vev.query(Map.of(...))` request-map wrappers |
| Return-map rows | `music_brainz.clj` | `:keys`, `:strs`, and `:syms` have restored-sample Datomic comparison rows plus Clojure/Java wrapper coverage |

## Pending Tutorial Coverage

These should be ported next using the mini fixture first, then the restored
1968-1973 sample:

| Shape | Source | Notes |
| --- | --- | --- |
| Additional Day-of-Datomic host snippets | `music_brainz.clj` | Keep porting examples that exercise host presentation rather than engine syntax |

## Host Or Datomic-Specific Later

These are not current blockers for the Vev engine:

| Shape | Reason |
| --- | --- |
| Clojure destructuring of return-map rows | Host wrapper ergonomics, not engine semantics |
| Java `HashSet` result identity/rendering | Host API shape |
| Datomic peer cache/io-stats details | Datomic implementation-specific |
| Datomic log APIs: `d/log`, `tx-ids`, `tx-data` | Future time/log/durability phase |
| Fulltext query `(fulltext $ :attr q)` | Requires a fulltext index design |
| Arbitrary JVM calls such as `System/getProperties` or method calls | Host/JVM-specific |
| Datomic timeout object shape | Host/API behavior; Vev can expose a native timeout later |

## Follow-Up

This phase is complete enough to stop being the main active development track.
Further MusicBrainz work should be targeted:

1. Add Day-of-Datomic host snippets only when they exercise a real Vev host API
   shape, not just Clojure presentation.
2. Use the full matrix as a regression gate while durable storage and host API
   work continue.
3. Keep full-import storage architecture work on the roadmap: the next write
   milestone is shared/chunked immutable DB indexes or a bulk builder, not basic
   import feasibility.
4. Keep expanding host-to-host timing comparisons beyond the current
   representative Datomic subset, using the already passing full Clojure
   wrapper matrix as the correctness gate.
