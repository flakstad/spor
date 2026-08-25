# VevDB for Odin

The public package lives in
[vevdb/vev-odin](https://github.com/vevdb/vev-odin).

Download its platform bundle and unpack `vev` under `vendor/`:

```odin
import vev "vendor/vev"

library, ok := vev.load_bundled("vendor/vev")
assert(ok)
defer vev.unload(&library)

connection, ok := vev.create_conn(&library)
assert(ok)
defer vev.close(&connection)

tx, ok := vev.transact(
    &connection, `[{:db/id 1 :user/name "Ada"}]`)
assert(ok)
defer delete(tx)

result, ok := vev.query(
    &connection,
    `[:find ?name :where [?e :user/name ?name]]`,
)
assert(ok)
defer vev.close(&result)
```

The bundle contains the Odin source and matching native VevDB library. SQLite
is included.

Durable coordinates can be inspected without constructing a connection:

```odin
head, head_ok, head_error := vev.storage_head_basis_t(&library, "example.db")
defer delete(head_error)
indexed, indexed_ok, indexed_error := vev.storage_indexed_basis_t(&library, "example.db")
defer delete(indexed_error)
```

`head` is the latest committed transaction. `indexed` is the latest durable
index root and may be lower while maintenance is deferred. The older
`storage_basis_t` name remains a compatibility alias for indexed basis.

This engine repository keeps a mirror for coordinated ABI checks:

```sh
scripts/smoke_odin_package.sh
```
