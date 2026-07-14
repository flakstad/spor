<div align="center">
  <img src="vev-logo-fuller.png" alt="Vev logo" width="432">
</div>

# Vev DB

**A native, embedded Datalog database for immutable database values.**

Vev weaves immutable facts into a durable fabric of attributed entities and values. Facts accumulate through append-only transactions, producing immutable database snapshots that applications can query declaratively and pass around as ordinary values.

The project follows Datomic/DataScript semantics as a practical compatibility target. If you are familiar with Datomic or DataScript, their query, transaction, and pull tutorials provide the most direct path to understanding Vev's programming model.

Vev is not trying to be a Datomic clone, a SQL database, or a database server first. Its central bet is that immutable database values, flexible facts, and Datalog-as-data are useful well beyond the Clojure ecosystem when packaged as a small, embedded native library.

## Identity

Repository: <https://github.com/vevdb/vev>

Vev is designed around a few core principles:

* Native and embedded by default.
* Embedded-first, not embedded-only.
* Immutable snapshot reads.
* Datomic-flavored Datalog queries.
* Datomic/DataScript transaction and pull syntax where practical.
* Durable storage behind a narrow adapter boundary.
* Distributed as a native library for consumption from multiple host languages
  including C, Python, Rust, Java, Clojure, Go, and Node/TypeScript.
* Supported by a CLI for inspection, import/export, and operational tooling.
* Future-friendly through a stable native ABI.
* Kvist-first implementation with readable Odin output.

The goal is to make the database feel like an ordinary part of the host program rather than an external service that everything revolves around.

## Current Usage

Vev is still under active development, but the core programming model is already
usable:

```clojure
(require '[vev.core :as d])

(def conn (d/create-conn))

(d/transact conn
  [{:db/id 1 :user/name "Ada"}
   {:db/id 2 :user/name "Grace"}])

(def db (d/db conn))

(d/q
  '[:find ?name
    :where [?e :user/name ?name]]
  db)
```

Use `create-conn` for in-memory databases and `connect` for durable Vev store
files:

```clojure
(def durable (d/connect "app.vev"))
```

Durable stores currently use SQLite internally and require a platform SQLite
runtime, but application code does not set up SQLite schemas or issue SQL.

See [docs/getting-started.md](docs/getting-started.md) for the current local
setup and host-language examples. See
[docs/runtime-dependencies.md](docs/runtime-dependencies.md) for native library
and SQLite runtime details.

For repository verification, run:

```sh
scripts/smoke_clients.sh
scripts/smoke_cli.sh
scripts/smoke_packages.sh
```

The first command builds the platform library under `build/lib`, writes
`build/lib/pkgconfig/vev.pc`, and runs the available clients under `clients/*`.
The CLI smoke verifies `build/vev` against a temporary durable Vev store.
The package smoke script verifies the current local C SDK, JVM, Python,
Node/TypeScript, Go, Rust, and Odin package shapes from temporary projects or
directories.

Current client work areas:

* `clients/c`: raw C ABI smoke and `vev.h` usage.
* `clients/python`: pure `ctypes` wrapper.
* `clients/rust`: Rust RAII smoke wrapper over the C ABI.
* `clients/java`: Java 21 FFM wrapper, planned as `dev.vevdb:vev-java`.
* `clients/clojure`: Datomic-shaped Clojure wrapper over the Java client.
* `clients/go`: cgo wrapper smoke.
* `clients/node`: Node N-API / TypeScript smoke.
* `clients/odin`: Odin `core:dynlib` smoke wrapper over the C ABI.

Runnable examples live under `examples/*`, including the Clojure
getting-started script and a Python contact-book smoke that uses both
in-memory and durable Vev:

```sh
scripts/smoke_real_app.sh
```

## Thesis

Vev exists to make immutable database values a normal programming model outside the Clojure ecosystem.

The core idea is simple:

* Information is represented as facts.
* Facts accumulate over time.
* Reads happen against immutable database values.
* Writes produce new database values.
* Application logic can treat the database as ordinary data.

The irreducible core is:

* Datoms
* Transactions
* Immutable database snapshots
* Datalog-as-data

Everything else is optional, replaceable, or can arrive later:

* Durable storage engines
* File formats
* SQL views
* Full-text search
* Vector indexes
* Synchronization
* Server packaging
* Hosted services

Vev should compromise on implementation technique before compromising on the database-as-value model.

## Design Filter

The target experience is Datomic's ideas with SQLite's accessibility.

That means preserving facts, time, and immutable snapshots as the semantic center while keeping deployment simple and unsurprising. The embedded path should remain small, portable, and easy to adopt. Kvist should be an implementation advantage, not an adoption requirement.

Examples and documentation should make the programming model obvious as quickly as possible. Features that obscure the core abstraction, expand the surface area unnecessarily, or turn the project into a kitchen sink should be treated with skepticism.

When evaluating a feature, ask:

> Does this make immutable database values easier to understand, use, preserve, or distribute?

If not, it probably belongs outside the core.

## License

Vev is licensed under the Eclipse Public License 2.0. See [LICENSE](LICENSE).

## Acknowledgements

Vev is shaped by the Datomic family of ideas and by the open-source Datalog
work around it. In particular, the project uses DataScript as a semantic
compatibility target, Datalevin as an implementation and benchmark reference,
and Day of Datomic / Datomic MusicBrainz material as workload inspiration.

Those projects remain under their own licenses:

* [DataScript](https://github.com/tonsky/datascript), Eclipse Public License 1.0.
* [Datalevin](https://github.com/datalevin/datalevin), Eclipse Public License 2.0.
* [Day of Datomic Cloud](https://github.com/cognitect-labs/day-of-datomic-cloud), Eclipse Public License 1.0.

Any copied or adapted material from those projects should retain its original
copyright notices and license terms.
