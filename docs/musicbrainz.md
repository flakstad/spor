# MusicBrainz Workshop

The MusicBrainz workflow validates that Vev can follow real Datomic tutorial
material from Clojure and Kvist against the same persistent store. Examples are
ported from upstream rather than invented for Vev.

## Upstream Sources

The current workshop covers executable material from:

- `build/upstream/mbrainz-sample/examples/clj/datomic/samples/mbrainz.clj`
- `build/upstream/mbrainz-sample/schema.edn`
- `build/upstream/mbrainz-sample/resources/rules.edn`
- `build/upstream/day-of-datomic-conj/src/music_brainz.clj`
- `build/upstream/day-of-datomic/tutorial/query.clj`
- `build/upstream/day-of-datomic/tutorial/pull.clj`
- `build/upstream/day-of-datomic/tutorial/aggregates.clj`
- `build/upstream/day-of-datomic/tutorial/decomposing_a_query.clj`

The data source is Datomic's 1968-1973 MusicBrainz sample backup. Vev's local
export contains 763,299 datoms split into a schema file and eight
bounded value chunks.

`scripts/fetch_workshop_sources.sh` checks out pinned revisions of all three
upstream repositories under `build/upstream`. The validation setup runs it
automatically, so the workshop does not rely on manually prepared source trees.

## Requirements

Local source builds require:

- `kvist`
- Odin
- Clang and an archiver for the bundled SQLite build
- Java 25 and Clojure CLI for the Clojure workshop

Applications use Vev store paths and Vev APIs. They do not create SQLite
schemas, issue SQL, or otherwise manage SQLite directly. See
`docs/runtime-dependencies.md` for platform details.

## Create Or Refresh The Store

With an existing Vev-compatible MusicBrainz export under
`build/musicbrainz`:

```sh
scripts/musicbrainz_workshop_setup.sh
```

This command builds the importer, replaces the tutorial store, imports every
chunk, verifies close/reopen/query, and builds the native library needed by
host clients. The resulting store is:

```text
build/musicbrainz/vev-mbrainz-tutorial.sqlite
```

Use `--validate` to create the store and then run both host suites:

```sh
scripts/musicbrainz_workshop_setup.sh --validate
```

Paths can be overridden without editing tutorial code:

```sh
VEV_MUSICBRAINZ_EXPORT_PREFIX=/path/to/export-prefix \
VEV_MUSICBRAINZ_STORE=/path/to/musicbrainz.vev \
  scripts/musicbrainz_workshop_setup.sh
```

The Datomic backup is not itself a Vev transaction export. If the exported
chunks are absent and a local Datomic Pro installation is available, explicitly
run the source-conversion path:

```sh
DATOMIC_HOME=/path/to/datomic-pro \
  scripts/musicbrainz_workshop_setup.sh --from-datomic --validate
```

Datomic is only needed to read its backup format and produce the portable EDN
transaction chunks. It is not required to open or use the resulting Vev store.

## Run The Workshops

Clojure:

```sh
scripts/musicbrainz_workshop_clojure.sh
```

Kvist:

```sh
scripts/musicbrainz_workshop_kvist.sh
```

The Clojure examples use `vev.core` as `d` and follow the familiar query-first
shape:

```clojure
(d/q '[:find ?name :where [?e :artist/name ?name]] db)
```

The Kvist examples use Vev's literal data DSL with the database after the query
form:

```clojure
(d.q '[:find ?name :where [?e :artist/name ?name]] db)
```

EDN strings remain available where the workshop intentionally exercises the
cross-language parser surface.

## Compare With Datomic

Datomic comparison is optional and separate from ordinary Vev use. Prepare the
local sample and run:

```sh
scripts/musicbrainz_sample.sh prepare
scripts/compare_musicbrainz_workshop.sh
```

For Vev-only row/fingerprint validation:

```sh
scripts/compare_musicbrainz_workshop.sh --skip-datomic
```

The comparison harness checks row counts and portable fingerprints across Vev
Clojure, Vev Kvist, and local Datomic. It also supports focused workloads and
measured runs; use `--help` for the current options.

## Current Result

- Full store refresh succeeds with 763,299 datoms.
- The refreshed store closes, reopens, and answers the import smoke queries.
- The complete Clojure workshop validation passes.
- The parallel Kvist workshop validation reports `summary ok=true`.
- Versioned schema migrations keep an already-current durable connection open
  near constant-time instead of rebuilding fulltext state on every open.
- Covered Datomic comparisons match row counts and portable fingerprints.
- Covered persistent Vev performance is accepted for the current usability
  gate. Further tuning starts from a measured application blocker, not a
  workshop-specific special case.
