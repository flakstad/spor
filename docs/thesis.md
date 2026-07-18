# VevDB Thesis

Vev exists to make immutable database values a normal programming model outside
the Clojure ecosystem.

The core idea is:

- information is represented as facts
- facts accumulate over time
- reads happen against immutable database values
- writes produce new database values
- application logic can treat the database as ordinary data

The irreducible core is:

- datoms
- transactions
- immutable DB snapshots
- Datalog-as-data

Everything else is optional or later:

- durable storage
- file format
- SQL views
- full-text search
- vector indexes
- sync
- server packaging
- hosted services

Vev should compromise on implementation technique before compromising on the
database-as-value model.

## Design filter

Vev's target feel is Datomic's ideas with SQLite's accessibility.

That means:

- preserve facts, time, and immutable snapshots as the semantic center
- keep the embedded path small, portable, and boring to deploy
- make Kvist an implementation advantage, not an adoption requirement
- prefer examples that make the programming model obvious quickly
- say no to features that turn the core into a kitchen sink

When evaluating a feature, ask whether it makes immutable database values easier
to understand, use, preserve, or distribute. If not, it belongs outside the core.
