# VevDB for Rust

**Status: in progress. Not published.**

This Cargo integration test will move to a standalone package repository.

```sh
scripts/build_c_abi.sh
scripts/smoke_rust_package.sh
```

The crate links to `VEV_LIB_DIR` or the repository library under `build/lib`.
It wraps native handles with RAII.

```rust
let conn = Conn::create()?;
conn.transact(r#"[{:db/id 1 :user/name "Ada"}]"#);

let db = conn.db()?;
let result =
    db.q("[:find ?name :where [?e :user/name ?name]]", "[]")?;
```

The package is currently `publish = false`. SQLite is included in the VevDB
library.
