# Vev Rust

This is currently a small Rust crate over Vev's C ABI. The local Cargo package
is named `vev` with `publish = false`, so it can grow into the published Rust
crate without moving paths again.

Current local development:

```sh
scripts/build_c_abi.sh
```

The Rust crate has a `build.rs` that links against `VEV_LIB_DIR` or, by
default, the platform library under the repo's `build/lib`. The top-level build
script sets `VEV_LIB_DIR` explicitly and runs the smoke binary.

Likely package split before publishing:

- `vev-sys`: raw generated or hand-maintained C ABI bindings over `include/vev.h`
- `vev`: safe RAII wrapper with `Connection`, immutable `DB` snapshots,
  prepared queries, statements, pull patterns, and typed result batches

The wrapper follows that direction now: native handles are owned by Rust structs
and released through `Drop`. The `vev-rust-smoke` binary exercises the wrapper,
and `scripts/smoke_rust_package.sh` verifies that a separate temporary Cargo
project can depend on `clients/rust` by path.

Basic usage in the current smoke wrapper:

```rust
let conn = Conn::open_memory()?;

conn.transact(r#"[{:db/id 1 :user/name "Ada"}]"#);

let db = conn.db()?;
let rows = db.q("[:find ?name :where [?e :user/name ?name]]", "[]")?;
let pulled = db.pull("[:user/name]", 1)?;
```

Prepared queries remain available when a query is reused:

```rust
let query = conn.prepare("[:find ?name :where [?e :user/name ?name]]")?;
let rows = query.query_db(&db, "[]")?.rows();
```

DB snapshots expose an RAII entity view over the native `vev_entity_t` handle:

```rust
let db = conn.db()?;
let ada = db.entity(1)?;
let friend = ada.ref_entity(":user/friend")?;

assert_eq!(ada.get(":user/name")?, Value::String("Ada".to_string()));
assert_eq!(friend.get(":user/name")?, Value::String("Grace".to_string()));
```

Parser tooling can inspect a single where clause through the wrapper's
`parse_clause_edn` helper.

The smoke wrapper also exposes durable typed-builder bulk ingestion:
`DurableConn::transact_bulk_report(&[&first, &second])`. This commits several
prepared builders as one durable Vev transaction, producing one tx id and one
SQLite commit.

The local `TxBuilder` wrapper exposes the C builder's primitive value adders:
`add_string`, `add_keyword`, `add_symbol`, `add_entity`, `add_int`, and
`add_bool`.

The current binary target is still `vev-rust-smoke`; the library crate identity
is the future public crate identity.

Durable stores are opened through Vev APIs with paths such as `app.vev`. The
Rust wrapper links to `libvev`, whose release build includes SQLite with FTS5.
Rust application code does not install or configure SQLite.

```rust
let durable = DurableConn::open("app.vev")?;
durable.transact(r#"[{:db/id 1 :user/name "Durable Ada"}]"#)?;
let rows = durable.q("[:find ?name :where [?e :user/name ?name]]", "[]")?;
```
