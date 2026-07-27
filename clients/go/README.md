# VevDB for Go

**Status: in progress. Not published.**

This cgo integration test will move to a standalone Go module.

```sh
scripts/build_c_abi.sh
scripts/smoke_go_package.sh
```

Current module path:

```text
github.com/vevdb/vev/clients/go
```

```go
conn, err := vev.CreateConn()
if err != nil {
    return err
}
defer conn.Close()

conn.Transact(`[{:db/id 1 :user/name "Ada"}]`)
result := conn.QueryText(
    `[:find ?name :where [?e :user/name ?name]]`, `[]`)
```

Native handles require `Close`. SQLite is included in the VevDB library.
