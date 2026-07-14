# Next Steps

This is the current Vev execution plan, not a changelog.

## Active Gate

Turn the verified local Vev artifacts into reproducible, publishable packages.
The MusicBrainz workshop and real-application gates are complete in Clojure and
Kvist. The current step is reproducible platform artifacts; the next
user-visible milestone is installation through normal host package mechanisms
without repository-local build paths.

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
`Conn` and immutable `DB` values for both in-memory and durable operation, with
literal `transact`, query-first `q`, `pull`, and `db-with` operations. The
Kvist contact book uses only this surface; storage types and SQLite remain
internal. These operations throw on failure, `q` exposes ordinary result rows,
`pull` returns a Vev value directly, and every owning value uses the same
overloaded `close` operation. DB values can be passed through application code
as ordinary values until their owner closes them.

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
- Non-Kvist consumers are primary product surfaces.
- Published coordinates must not be documented as available until publication
  has actually succeeded.
- Performance changes must be generic engine/storage work, never
  application-specific benchmark handling.

## Remaining Work

1. Make release builds reproducible for each supported OS/architecture. At
   minimum, produce and smoke macOS arm64 first, then add Linux x86-64 before
   calling the release generally available.
2. Publish or stage the native platform artifact first, then Java and Clojure
   artifacts that depend on it. Verify fresh temporary Clojure and Maven
   projects using normal coordinates and no repository-local Maven path.
3. Define Kvist package installation explicitly. Until Kvist has a registry,
   document a stable source dependency/vendor workflow that does not require
   copying arbitrary internal files.
4. Extend the dependency-only application smoke to every packaged host before
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
