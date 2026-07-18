# VevDB for Clojure

This is the Clojure package layer for VevDB. It depends on the JVM wrapper in
`clients/java`, which uses Java 21 Foreign Function & Memory to call the native
VevDB shared library.

The public API accepts ordinary Clojure data and serializes it to the same EDN
text frontend used by C, Python, Rust, and Java callers.

## Intended Published Usage

Normal application setup should be one dependency. The Clojure package should
pull in the Java wrapper, and the Java wrapper should pull in the right
platform native artifact, then load the native library itself:

```clojure
{:deps {com.vevdb/vev-clj {:mvn/version "0.1.0"}}}
```

The source repository can instead be consumed through a Git coordinate:

```clojure
{:deps
 {com.vevdb/vev-clj
  {:git/tag "<release-tag>"
   :git/sha "<release-sha>"}}}
```

Its `deps.edn` brings in the published `vev-java` artifact, which contains the
native VevDB engine. Both forms therefore provide the same self-contained
runtime.

Application code should not pass Java paths or native library paths around:

```clojure
(require '[vev.core :as d])

(def conn (d/create-conn))

(d/transact conn
  [{:db/id 1
    :user/name "Ada"
    :user/email "ada@example.com"}])

(def db (d/db conn))

(d/q
  '[:find ?name
    :where [?e :user/name ?name]]
  db)
```

Transaction listeners are report callbacks on successful commits:

```clojure
(def listener
  (d/listen conn :audit
    (fn [report]
      (println (:tx-data report)))))

(d/transact conn [{:db/id 2 :user/name "Grace"}])
(d/unlisten conn listener)
```

The same `d/listen` / `d/unlisten` functions work for durable connections
opened with `d/connect`; failed transactions do not notify listeners.

Durable usage should be similarly direct:

```clojure
(def conn (d/connect "app.vev"))

(d/transact conn [{:db/id 1 :user/name "Ada"}])
(d/q '[:find ?name :where [?e :user/name ?name]] (d/db conn))
```

For bulk host writes, `tx-builder` can be passed to the same `d/transact`
function on either in-memory or durable connections:

```clojure
(def tx (d/tx-builder conn 2))
(d/tx-add! tx 2 :user/name "Grace")
(d/tx-add! tx 2 :user/email "grace@example.com")
(d/transact conn tx)
(.close tx)
```

The current repo has not published the Java/Clojure/native artifacts yet, so
local development still has extra setup. The Java loader already supports the
future packaged shape by checking for bundled native resources after explicit
local paths.

The durable backend uses SQLite internally. Release builds link SQLite with
FTS5 into the native VevDB library, so Clojure users do not install or configure
SQLite; application code opens a VevDB store with `d/connect`.

## Local Development

Current local source development is path-based:

```clojure
{:deps {vev/vev-clj {:local/root "clients/clojure"}}}
```

That path only adds the Clojure source. It is useful when editing this repo, but
it is not the intended application setup unless the root `:clj-dev` alias or
equivalent Java/native classpath is also present.

Build the native library and Java classes first:

```sh
scripts/build_c_abi.sh
scripts/stage_jvm_native.sh
scripts/package_jvm.sh
```

`scripts/package_jvm.sh` builds local Java, native-resource, and Clojure jars
under `build/jvm` and a local Maven-style repository under `build/m2`. Release
automation combines the verified platform resources into one `vev-java` jar,
so applications do not select a native artifact.

That local repository can be consumed from a separate test project:

```clojure
{:mvn/local-repo "/path/to/vev/build/m2"
 :deps {com.vevdb/vev-clj {:mvn/version "0.1.0"}}
 :aliases {:run {:jvm-opts ["--enable-preview"
                            "--enable-native-access=ALL-UNNAMED"]}}}
```

`scripts/smoke_jvm_package.sh` verifies each platform package during its native
build. `scripts/smoke_jvm_coordinates.sh` verifies the final combined artifacts
from a fresh Maven project and a fresh Clojure project.

When developing from the repo root, the root `:clj-dev` alias adds the locally
built Java classes and the required JVM flags:

```sh
clojure -M:clj-dev
```

Then open `examples/clojure/getting_started.clj` and evaluate the forms inside
its `(comment ...)` block one at a time. That command is a repo
smoke/development concern, not the desired public API.
Until native artifacts are packaged, no-arg `create-conn` and one-arg
`connect` resolve the native library from the `vev.library` JVM property, then
`VEV_LIB`, then a local `build/lib` library, then a bundled platform resource.

`q` uses Datomic/DataScript-style query-first argument order. The wrapper also
accepts DB-first calls for compatibility with earlier VevDB code, but new code
should follow the familiar query-then-sources shape:

```clojure
(d/q '[:find ?name :where [?e :user/name ?name]] db)
```

For Datomic `d/query`-style host code, use `query` with a request map:

```clojure
(d/query
  {:query '[:find ?name
            :in $ ?email
            :where [?e :user/email ?email]
                   [?e :user/name ?name]]
   :args [db "ada@example.com"]})
```

Return-map markers produce Clojure maps:

```clojure
(d/q
  '[:find ?name ?email
    :keys name email
    :where [?e :user/name ?name]
           [?e :user/email ?email]]
  db)
;; => #{{:name "Ada", :email "ada@example.com"}}
```

Inputs are passed as ordinary arguments after the query and DB:

```clojure
(d/q
  '[:find ?name
    :in $ [?email ...]
    :where [?e :user/email ?email]
           [?e :user/name ?name]]
  db
  ["ada@example.com" "grace@example.com"])
```

Plain `q`/`rows` calls prepare a temporary native query handle and close it after
the call. Use `prepare` when the same query should be reused:

```clojure
(def email-query
  (d/prepare conn
    '[:find ?e ?email
      :in $ ?needle
      :where [?e :user/email ?email]
             [(= ?email ?needle)]]))

(d/prepared-edn email-query)
(d/q email-query db "ada@example.com")
```

Single where clauses can be parsed directly for DataScript-style parser tooling:

```clojure
(d/parse-clause conn '[?e :user/email ?email])
```

`prepared-edn` also works for reusable pull patterns:

```clojure
(def person-pattern
  (d/prepare-pull-pattern db
    [:user/name {:user/friend [:user/name]}]))

(d/prepared-edn person-pattern)
(d/pull db person-pattern 1)
```

Pull follows the same DB-value shape:

```clojure
(d/pull db
  [:user/name {:user/friend [:user/name]}]
  1)

(d/pull-many db [:user/name] [1 2])
```

Entity views also follow the DB-value shape. They are backed by the immutable
DB snapshot, so later transactions on the connection do not change what the
view sees:

```clojure
(let [db (d/db conn)
      ada (d/entity db 1)]
  (:user/name ada)
  (d/entity-values ada :user/email)
  (d/entity-ref ada :user/friend)
  (d/touch ada))
```

Lookup refs and idents are supported through the same function:

```clojure
(d/entity db [:user/email "ada@example.com"])
(d/entity db :user/ada)
```

Transaction functions follow Datomic's installed-ident model: the DB contains
the function ident, while the host registry supplies the executable callback for
this process.

```clojure
(with-open [fns (d/tx-fns conn
                  {:user/set-name
                   (fn [db e name]
                     [[:db/add e :user/name name]])})]
  (d/transact conn [[:db/add 100 :db/ident :user/set-name]])
  (d/transact conn [[:user/set-name 1 "Ada"]] fns))
```

The same shape works with `d/connect` durable handles. The callback receives
`(db & args)` and returns ordinary tx-data. The DB value is valid for the
callback call; keep durable application state outside the callback if it needs
to outlive the transaction.

Immutable DB values support Datomic/DataScript-style `with` operations:

```clojure
(let [report (d/with db [{:db/id 3 :user/name "Barbara"}])
      next-db (d/db-with db [{:db/id 3 :user/name "Barbara"}])]
  [(:ok report)
   (d/q '[:find ?e :where [?e :user/name "Barbara"]] db)
   (d/q '[:find ?e :where [?e :user/name "Barbara"]] next-db)])
```

A mutable connection can also be initialized from an immutable DB snapshot:

```clojure
(def next-conn (d/conn-from-db next-db))

(d/transact next-conn [{:db/id 4 :user/name "Dorothy"}])
(d/q '[:find ?name :where [?e :user/name ?name]] (d/db next-conn))
```

Durable connections use the same transaction and DB-value query shape:

```clojure
(def durable (d/connect "app.vev"))

(d/connection-info durable)
;; => {:backend :sqlite, :path "app.vev", :basis-t 0, :tx-count 0, :tx-ids []}

(d/transact durable [{:db/id 1 :user/name "Ada"}])
(d/q '[:find ?name :where [?e :user/name ?name]] (d/db durable))
```

For explicit durable bulk ingest, native builders can be committed as one
ordinary transaction:

```clojure
(with-open [first (d/tx-builder durable 1)
            second (d/tx-builder durable 1)]
  (d/tx-add! first 2 :user/name "Grace")
  (d/tx-add! second 3 :user/name "Hedy")
  (d/transact-bulk durable [first second]))
```

The wrapper has JVM cleanup fallback for native handles, so examples use normal
Clojure values. In long-running processes or tight loops that create many
connections, DB snapshots, prepared queries, or pull patterns, call `.close`
explicitly when a handle is no longer needed.

The current package is deliberately thin:

- `transact` and `with` return transaction report maps from typed native report handles
- `transact-text` and `with-text` return raw EDN report strings
- `q` returns a set of row vectors
- `rows` returns an ordered vector of row vectors
- entity ids are converted to integers
- pull maps are converted to Clojure maps
- immutable DB snapshots are passable values with JVM cleaner fallback; they
  still implement `AutoCloseable` for explicit cleanup in tight loops

Run through the top-level ABI smoke script:

```sh
scripts/build_c_abi.sh
```
