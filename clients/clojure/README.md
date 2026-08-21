# VevDB for Clojure

The public Clojure package lives in
[vevdb/vev-clj](https://github.com/vevdb/vev-clj).

```clojure
{:deps {com.vevdb/vev-clj {:mvn/version "0.3.0"}}}
```

This in-tree copy lets the engine test coordinated C ABI, Java, and Clojure
changes. Do not use it as the public package source.

The package contains two namespaces:

- `vev.core` is the Datomic-like fact database API.
- `vev.sqlite` provides direct application SQL using VevDB's bundled SQLite.

```clojure
(require '[vev.sqlite :as sql])

(def app-db (sql/open "application.sqlite"))
(sql/execute-script!
 app-db "create table cache(key text primary key, value blob)")
(sql/execute! app-db "insert into cache values(?, ?)"
              ["session:42" (pr-str {:user/id 42})])
(sql/query app-db "select key, value from cache")
```

The namespace also provides named parameters, `query-one`, `scalar`, reusable
prepared statements, batches, row reduction, read-only connections, busy
timeouts, and transaction scopes.

See [SQLite](../../docs/sqlite.md) for the complete API and ownership rules for
the corresponding Kvist and C interfaces.

```sh
scripts/smoke_jvm_package.sh
scripts/test_sqlite_applications_clojure.sh
```
