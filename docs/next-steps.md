# Next Steps

This document contains the current Vev release gate and remaining work. It is
not a changelog.

## Current State

Vev is usable as an embedded, native, Datomic-shaped database from Kvist,
Clojure, Java, C, Python, Rust, Node, Go, and Odin. Its primary application
surface is `q`, `pull`, `transact`, `db`, and `db-with` over connections and
immutable database values.

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

The real 1968-1973 MusicBrainz sample currently validates the complete paired
Clojure and Kvist workshop. The setup uses pinned upstream sources rather than
copied or invented examples:

- `Datomic/mbrainz-sample` at `a7c0aab6828cfa09d5ff3c6075579673377b4a43`
- `Datomic/day-of-datomic` at `daa457f766e16f55243a95513e759573b8827329`
- `Datomic/day-of-datomic-conj` at `cf1e260cff0aa582fe2ae17bb1fcfaeebb139f80`

On the current development machine, importing 763,299 MusicBrainz datoms takes
about 18.4 seconds and persisting their indexed durable store takes about 19.6
seconds. The complete Clojure workshop then passes in about 15 seconds. The
complete Kvist workshop reports `source=kvist section=summary ok=true`.

Durable schema changes are versioned. Normal connection open no longer reruns
all migrations or rewrites the FTS index: a marked 763,299-datom store opens in
about 12 ms instead of about 10.2 seconds. An older unmarked store pays the
migration once and is marked for later opens.

Kvist's `kvist:edn` reader builds parsed vectors, lists, sets, and maps with
linear mutable builders followed by one immutable freeze. A 100,000-form,
5.1 MB MusicBrainz transaction chunk parses in about 0.4 seconds rather than
following the former quadratic append path. This work is on Kvist main and is
verified through the installed `kvist` binary.

Vev vendors the optional official `kvist:cli` package under `deps/cli`, pinned
to its upstream revision, so repository builds do not depend on an undeclared
machine-local package path.

## Hard Constraints

- In-memory mode must remain independent of SQLite.
- Durable storage details must remain behind normal Vev APIs.
- Clojure and Kvist APIs remain Datomic-shaped, including query-first `q` with
  the database value after the query form.
- Reusable Kvist database forms are named immutable data, not string-only or
  macro-only representations.
- Non-Kvist consumers are primary supported product surfaces.
- Engine and storage changes must be general mechanisms, not benchmark-specific
  query handling.

## Remaining Work

1. Publish the verified combined `vev-java` and `vev-clj` artifacts to the
   selected public Maven repository. The combined release already verifies
   clean consumer caches against a temporary Maven HTTPS repository, without
   repository-local classpaths, native paths, or `:mvn/local-repo`.
2. Cut the first tagged release from a successful gate run and publish its
   checksummed native bundles, combined JVM artifacts, source package, and
   adapter packages.

Parser diagnostic exactness, additional DataScript edge cases, and specialized
query optimizations continue after this release gate. They are not allowed to
delay a working MusicBrainz tutorial and normal package consumption unless they
expose correctness or safety failures.

## Exit Criteria

This gate is complete when:

- the installed Kvist compiler passes the 379-test engine suite, parser-input
  suite, and MusicBrainz mini suite
- a clean MusicBrainz setup completes both Clojure and Kvist workshops
- contact-book examples pass through the canonical application API
- one versioned command produces a complete checksummed artifact manifest
- macOS arm64 and Linux x86-64 artifacts pass package-only host smokes
- the combined manifest proves that both platform releases came from the same
  Vev commit and agree on all platform-independent artifact hashes
- fresh Clojure and Java projects consume staged or published coordinates
  without repository-local setup

## Verification Commands

```sh
kvist test src/vev_tests/vev_test.kvist
kvist test src/vev_tests/parser_input_test.kvist
kvist test src/vev_tests/musicbrainz_test.kvist

scripts/musicbrainz_workshop_setup.sh --from-datomic --validate
scripts/build_release.sh
```
