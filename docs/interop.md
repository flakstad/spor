# Interop

## Principle

Interop is now part of the active compatibility gate, because VevDB's primary
long-term consumers are non-Kvist callers. Durable storage still waits, but the
native ABI, EDN text APIs, prepared handles, and host wrappers must stay current
with the semantic engine.

VevDB's primary source language is Kvist, with readable Odin output as a quality
gate. Kvist users may consume VevDB as a source package when that is the most
direct integration path.

For other native platforms and host languages, the primary integration artifact
should be a native library with a narrow C ABI. The CLI binary is for tooling,
inspection, import/export, smoke tests, and operational workflows; it is not the
main application integration model.

Future server packaging, if it exists, should wrap the same semantic core
rather than force a different internal model.

The current integration stack is:

1. native Kvist API
2. stable internal semantic model
3. native library packaging through a narrow C ABI
4. EDN text and prepared handles for portable query/tx/pull
5. host-specific wrappers for Python, Rust, Java, Clojure, Go, and Node/TypeScript
6. CLI binary over the same engine when tooling needs it
7. only later, if justified, server/daemon packaging
8. only later, if justified, transactor/peer-style packaging

## Repository And Package Identity

The canonical repository is:

```text
https://github.com/vevdb/vev
```

It drives the published and planned package identities:

- Clojure deps coordinate: `com.vevdb/vev-clj`
- Java/Maven coordinate: `com.vevdb:vev-java`
- native JVM artifacts by platform: `com.vevdb:vev-native-<platform>`
- Rust crate name, if published: `vevdb`
- Go module path: `github.com/vevdb/vev/clients/go`
- Node package name, if published: `@vevdb/vev`
- Python distribution and import name, if published: `vevdb`
- C SDK: `include/vev.h`, `libvev`, and pkg-config package `vev`
- Odin package: platform-specific `vev-odin` vendor bundles contain the
  handwritten package and matching native engine

The first packaging pass still supports explicit local library paths and
environment overrides, while the C SDK, JVM artifacts, CLI, and Odin vendor
bundle have release-shaped external-consumer proofs.

The C SDK release is `vev-native-<platform>-<version>.zip`. It contains
`include/vev.h`, `libvev`, relocatable `pkg-config` metadata, and a buildable
basic example. `scripts/smoke_native_bundle.sh` extracts the archive and
verifies both a generated external consumer and the packaged example,
including durable open/write/reopen/query through `vev_connect`.

The CLI path builds `build/vevdb` from `src/vev_cli/main.kvist`. It exposes
`--version` plus durable `info`, `transact`, `query`, and `pull` commands over
the native Kvist implementation. Each platform release contains a standalone
`vevdb-cli-<platform>-<version>` archive. `scripts/smoke_cli_package.sh` extracts
and exercises that artifact.

Runtime dependency details are tracked in
[`runtime-dependencies.md`](runtime-dependencies.md). VevDB builds a pinned,
checksum-verified SQLite amalgamation with FTS5 into the CLI and `libvev`.
Prebuilt consumers therefore have no separate SQLite runtime dependency.

The JVM path has bundled-native loading. The Java loader checks explicit path
configuration, local `build/lib`, then classpath resources under
`com/vevdb/native/<platform>/<library>`. Platform builds stage and test one
native resource each; the combined release merges all verified resources into
the final `vev-java` jar:

- `vev-java-<version>.jar`
- `vev-clj-<version>.jar`

`scripts/smoke_jvm_coordinates.sh` verifies a fresh Maven project and a fresh
Clojure project against a staged repository. The projects use only
`com.vevdb:vev-java` or `com.vevdb/vev-clj`; no repository source classpath,
platform selection, SQLite installation, or explicit native-library path is
present. The Java wrapper also checks the native ABI version before exposing a
connection.

It also writes a local Maven repository under `build/m2`, so release candidates
can be tested from outside the repo before publication:

```clojure
{:mvn/local-repo "/path/to/vev/build/m2"
 :deps {com.vevdb/vev-clj {:mvn/version "0.2.0-rc.2"}}}
```

For Java, the matching Maven dependency is `com.vevdb:vev-java`. Both
coordinates are published on Maven Central, and the one-dependency Clojure and
Java paths are mechanically verified by the combined release gate.

The Python path has the same explicit-to-bundled fallback shape: explicit
`vevdb.Library(path)`, `VEV_LIB`, repo `build/lib`, then
`native/<platform>/<library>` next to `vevdb.py`. The public constructor shape
is `vevdb.create_conn()` for in-memory work and
`vevdb.connect("app.vev")` for durable stores;
`vevdb.Library(path).create_conn()` is the explicit-library variant.
`clients/python/pyproject.toml` defines the future `vevdb` package metadata, and
`scripts/smoke_python_package.sh` validates that metadata plus the temporary
bundled-native package layout.

The Node path loads `VEV_NODE_NATIVE`, then a local `vev_native.node`, then
`native/<platform>/vev_native.node` next to `vev.js`. The addon is linked with
both repo-local and addon-relative rpaths so the platform `libvev` can sit next
to the addon in a future package. `clients/node/package.json` contains the
current `@vevdb/vev` package metadata while remaining private, and
`scripts/smoke_node_package.sh` verifies that metadata plus the temporary
bundled-native package layout.

The Go path is a cgo package at `github.com/vevdb/vev/clients/go`. Its public
constructor shape is `vev.CreateConn()` for in-memory work and
`vev.Connect("app.vev")` for durable stores; `OpenMemory()` remains a
compatibility alias. `scripts/smoke_go_package.sh` verifies import from a
separate temporary Go module using a local `replace`.

The Rust path is a local Cargo package under `clients/rust`, already named
`vevdb` with `publish = false`. It is still a smoke binary plus RAII wrapper in
one package; before publication it should likely split into `vevdb-sys` for raw
C ABI bindings and `vevdb` for the safe wrapper.

Odin consumption uses the handwritten `vev` package rather than generated
engine output. Each `vev-odin-<platform>-<version>.zip` release asset contains
that package plus the matching native engine under `vev/lib`. Applications
vendor the directory and call `load_bundled`; durable connections, transactions,
and typed query-row traversal are available without a separate native install.
`scripts/smoke_odin_bundle.sh` builds and runs a fresh external consumer using
only the extracted bundle.

## Native API

The native Kvist API should be the first-class source-level surface.

It should expose:

- open/create connection
- close
- transact
- get current DB snapshot
- query
- pull

Kvist callers should get the best syntax VevDB can offer: literal query,
transaction, and pull forms that lower directly to the same typed internal
structures used by every other frontend.

## Query Frontends

VevDB should have one engine with multiple front doors:

- Kvist literal macros for Kvist applications
- EDN string APIs for C/Odin/other host languages
- prepared queries for repeated execution

These frontends must converge early into the same internal `Query`, tx data,
and pull representations. Strings should not have separate semantics from
Kvist literals.

Frontend parity is tracked explicitly in `docs/frontend-parity.md`. New query,
pull, or transaction syntax should update both the Kvist literal macro path and
the EDN text path, then add a parity test.

The EDN string API is required for broad consumption. It is the portable
baseline: every host can pass text through a narrow ABI, queries can be logged
and stored, and Datomic/DataScript examples stay recognizable.

Prepared queries are the production form of the same idea:

```text
vev_prepare_query(conn, "[:find ?e :where [?e :name ?name]]") -> query_handle
vev_query_prepared(db, query_handle, inputs) -> result
```

A parse-and-run helper is still useful:

```text
vev_query_text(db, "[:find ?e :where [?e :name \"Ivan\"]]", inputs) -> result
```

Direct host-side AST builders should wait until a real caller proves they are
needed. A large struct-building ABI is more surface area than VevDB needs now.

## SQL stance

SQL should not be a phase-1 query surface. VevDB's broader story is not
"local-first instead of SQLite"; it is SQLite-like embedding for immutable
facts, relationships, and Datalog-as-data.

A later SQL layer may be useful for inspection, BI tools, or simple interop, but
it should start as a view over datoms, schema, and transactions rather than a
second primary semantic model.

## Native library and CLI

The native library should be the primary binary artifact for non-Kvist
consumers. It can link SQLite internally or depend on a platform SQLite library,
but SQLite should remain an implementation detail behind VevDB's storage adapter.

The CLI binary should stay thin:

- inspect local databases
- run smoke tests
- import/export data
- support debugging and operational workflows
- exercise the same engine path as embedded users

The CLI should not become the only supported way to use VevDB from applications.

## C ABI

The C ABI should be intentionally narrow.

Good candidates:

- opaque connection handle
- opaque DB snapshot handle or snapshot token
- transact from text or binary payload
- query from text
- prepared query handles
- pull from text pattern
- results in a simple encoded representation
- release/free functions for every owned handle/result

Avoid exposing:

- internal structs directly
- storage handles
- backend-specific details
- pointer ownership rules that leak deep engine internals

The implementation lives in `src/vev_abi` with the public header in
`include/vev.h`. It currently proves the foreign-consumer path:

- open an in-memory connection
- transact EDN text
- query EDN text
- prepare a query
- run a prepared query
- retain immutable DB values
- run pull APIs
- bind statement inputs without reparsing EDN
- stream result rows and nested values through callbacks
- register transaction functions that return EDN tx-data
- free returned strings and handles

Java exposes the raw transaction-function callback path as
`TxFunctionRegistry`. This is a low-level host extension, not Datomic stored
functions, and is intentionally absent from the Datomic-shaped `vev.core`
namespace. See `docs/c-abi.md`, `clients/c/smoke.c`, and the Python/Rust/Java
smoke examples, plus the Go and Node/TypeScript smoke examples.

## Clojure/JVM

Clojure consumption is active. The intended stack is:

- native engine
- stable C ABI/native shared library boundary
- Java Foreign Function & Memory wrapper
- Clojure namespace layer on top of the Java wrapper

This keeps Clojure ergonomic without making the engine JVM-shaped internally.

## Java-side options

Current direction:

- Java Foreign Function & Memory API wrapper
- a small Java library exposing a friendlier object API
- a Clojure namespace layer on top of that Java library

JNI remains a fallback only if FFM compatibility becomes a real blocker.

The important point is:

- Clojure should consume a wrapper
- the engine should not become JVM-shaped internally

## Go

Go is a strong host-language fit for VevDB's embedded-native shape: CLIs,
developer tools, local daemons, infrastructure agents, and application servers
often accept a small native database dependency when it gives them simple
deployment and predictable local reads.

The first Go surface should stay close to the C ABI:

- `Conn`, `DB`, and `PreparedQuery` wrappers around opaque handles
- EDN transaction/query strings for broad compatibility
- prepared queries for repeated execution
- explicit close/release behavior

The current `clients/go` module proves that path through `cgo`, including typed
result rows, pull, lookup refs, immutable DB snapshots, `conn-from-db`, and
durable SQLite reopen checks. `cmd/vev-go-smoke` runs the full smoke workload,
and `scripts/smoke_go_package.sh` verifies the package from a separate Go
module using a local `replace`. A fuller Go client can grow from the same shape
once real callers prove which typed statement bindings and transaction-builder
helpers are worth maintaining.

## Node/TypeScript

Node is the right first JavaScript target. It is widely used in developer
tooling, Electron-style desktop applications, local-first app backends, and
automation, all of which can plausibly embed a native database.

The initial Node/TypeScript path is a tiny N-API addon plus a JavaScript facade
and TypeScript declarations:

- Node owns wrapper objects
- the native addon owns/release C ABI handles
- EDN text remains the portable query and transaction boundary
- prepared handles preserve the same production path as other hosts

The current smoke example covers typed row materialization, pull, lookup refs,
pull-many, immutable DB snapshots, and durable SQLite metadata/query checks.
Browser JavaScript should be treated as a separate WASM packaging effort. It
has different constraints around storage, binary distribution, threading, and
host APIs, so it should not drive the Node package shape yet.

## Public data shape

For foreign consumers, the safest boundary is:

- queries as EDN text, plus prepared query handles
- pull patterns as EDN text, plus prepared pattern handles if needed
- tx data as EDN text or encoded values
- results as a portable encoded format

This keeps the ABI stable even if internal ASTs evolve.

It also helps preserve a possible future transport boundary if VevDB later runs
out of process.

If VevDB ever explores a transactor/peer split, these same explicit plain-data
boundaries will still be valuable. They should make the model more plausible
without forcing the project to commit to it today.
