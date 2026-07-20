# VevDB for Go

This is a cgo package over VevDB's C ABI. The API is still smoke-level, but it is
now importable at the planned module path and has a smoke command under
`cmd/vev-go-smoke`.

Current local development:

```sh
scripts/build_c_abi.sh
```

The script builds and runs `clients/go/cmd/vev-go-smoke` against the platform
library under `build/lib`.

Module path:

```text
github.com/vevdb/vev/clients/go
```

The first polished package should keep the same basic shape:

- `Conn`, `DB`, durable connection, prepared query, statement, and result types
- `CreateConn` for in-memory work and `Connect` for durable VevDB stores
- explicit `Close` methods for native handles
- EDN text APIs for parity with other hosts
- prepared queries and typed statement bindings for repeated work
- prepared pull patterns for direct `Pull`/`PullMany` reuse
- DB-backed entity views over immutable snapshots
- typed transaction builders for durable bulk and logical group commits
- `ParseClauseEDN` for DataScript-style single where-clause parser tooling

Basic usage in the current wrapper:

```go
conn, err := vev.CreateConn()
if err != nil {
    return err
}
defer conn.Close()

conn.Transact(`[{:db/id 1 :user/name "Ada"}]`)

db, err := conn.DB()
if err != nil {
    return err
}
defer db.Close()

result, err := db.Q(`[:find ?name :where [?e :user/name ?name]]`, "[]")
if err != nil {
    return err
}

pulled, err := db.Pull("[:user/name]", 1)
```

`Q` returns the query's Datomic find shape as a `Value`; relation queries are
`SetValue`, collections and tuples are `[]Value`, and scalar finds return the
scalar value or `nil`.

Use `vev.Prepare(...)` and `db.QueryRows(...)` when reusing the same query many
times.

Entity views use the same explicit close pattern as other native handles:

```go
db, _ := conn.DB()
defer db.Close()

ada, _ := db.Entity(1)
defer ada.Close()

name, _ := ada.Get(":user/name")
friend, _ := ada.Ref(":user/friend")
defer friend.Close()
```

Durable bulk writes use typed transaction builders. `TransactBulk` flattens
several builders into one ordinary durable transaction; `TransactLogicalBulk`
preserves one tx/report per builder under one SQLite commit:

```go
first, _ := vev.NewTxBuilder(1)
defer first.Close()
second, _ := vev.NewTxBuilder(1)
defer second.Close()

first.AddString(1, ":user/name", "Ada")
first.AddInt(1, ":user/age", 37)
first.AddBool(1, ":user/active", true)
second.AddString(2, ":user/name", "Grace")
second.AddKeyword(2, ":user/role", ":role/admin")

report, _ := durable.TransactBulk([]*vev.TxBuilder{first, second})
defer report.Close()

reports, _ := durable.TransactLogicalBulk([]*vev.TxBuilder{first, second})
defer reports.Close()
```

`scripts/smoke_go_package.sh` verifies that this package can be imported from a
separate Go module using a local `replace` to this checkout.

Durable stores are opened through VevDB APIs with paths such as `app.vev`. The Go
package uses cgo over `libvev`, whose release build includes SQLite with FTS5.
Go application code does not install or configure SQLite.
