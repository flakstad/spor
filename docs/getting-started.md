# Getting started

VevDB is embedded. Open a connection, transact data, take an immutable database
value, then query or pull from it.

Use an in-memory connection for temporary data. For a durable store, pass a
file path. The examples use `example.db`; replace it with the path you want.

## CLI

Download a CLI archive from a
[VevDB release](https://github.com/vevdb/vev/releases). The executable includes
SQLite.

```sh
vevdb transact example.db '[{:db/id 1 :user/name "Ada"}]'
vevdb query example.db '[:find ?name :where [?e :user/name ?name]]'
vevdb pull example.db '[:user/name]' 1
vevdb info example.db
```

See the [CLI reference](cli.md) for query inputs, file arguments, output, and
exit status.

## Clojure

```clojure
{:deps {com.vevdb/vev-clj {:mvn/version "0.2.0"}}}
```

```clojure
(require '[vev.core :as d])

(def conn (d/create-conn))

(d/transact conn
  [{:db/id 1 :person/name "Ada"}
   {:db/id 2 :person/name "Grace"}])

(def db (d/db conn))

(d/q '[:find ?name
       :where [?e :person/name ?name]]
     db)

(d/pull db [:person/name] 1)
```

For durability, replace `create-conn` with:

```clojure
(d/connect "example.db")
```

See [vev-clj](https://github.com/vevdb/vev-clj) for the complete API.

## Other languages

| Language | Status | Link |
| --- | --- | --- |
| C | Built in | [Header](../include/vev.h) |
| Kvist | Built in | [API](../clients/kvist) |
| Java | Available | [vev-java](https://github.com/vevdb/vev-java) |
| Odin | Available | [vev-odin](https://github.com/vevdb/vev-odin) |
| Python | In progress | [Integration code](../clients/python) |
| Rust | In progress | [Integration code](../clients/rust) |
| Go | In progress | [Integration code](../clients/go) |
| Node.js / TypeScript | In progress | [Integration code](../clients/node) |

In-progress clients are experimental and not published.

See [Build from source](building.md) for local development.
