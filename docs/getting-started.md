# Getting Started

VevDB is an embedded Datalog database for immutable DB values. The normal workflow
is:

1. create an in-memory connection or connect to a durable VevDB store
2. transact schema and data
3. take an immutable DB value with `db`
4. query, pull, or inspect entities from that DB value
5. use `with` / `db-with` when you want a hypothetical DB without changing the
   connection

Durable stores are opened with VevDB paths such as `app.vev`. VevDB currently uses
SQLite internally for durability, but application code does not create SQLite
tables or issue SQL.

## MusicBrainz Workshop

The repository includes parallel Clojure and Kvist ports of the upstream
Datomic MusicBrainz tutorial material. With the exported sample chunks present,
create the persistent store and validate both hosts with one command:

```sh
scripts/musicbrainz_workshop_setup.sh --validate
```

The individual host commands are:

```sh
scripts/musicbrainz_workshop_clojure.sh
scripts/musicbrainz_workshop_kvist.sh
```

See `docs/musicbrainz.md` for sample export conversion, optional Datomic
comparison, path overrides, and runtime requirements.

The validation command fetches the exact pinned upstream tutorial sources into
`build/upstream`; no separate clone or copied tutorial fixture is required.

## Application Example

The contact book is a small non-workshop application implemented in Python,
Clojure, and Kvist. The Clojure and Kvist versions both:

- use an in-memory connection for the test path
- transact schema and data
- query and pull through an immutable DB value
- prove that `db-with` does not mutate the original DB
- use a durable VevDB store in normal operation
- close, reopen, transact, and reopen again to verify persistence

Run the Clojure and Kvist applications together:

```sh
scripts/contact_book.sh
```

To verify the Clojure application as an external package consumer rather than
through repository source paths:

```sh
scripts/contact_book_package_clojure.sh
```

That command creates a temporary project whose only VevDB dependency is
`com.vevdb/vev-clj`, backed by the locally built Maven artifacts.

## CLI

The VevDB CLI is a standalone executable with SQLite included. A release
archive unpacks to `vevdb-<version>/bin/vevdb`; copy that executable onto
`PATH`. A source build writes the same executable to `build/vevdb`:

```sh
build/vevdb --version
build/vevdb transact app.vev '[{:db/id 1 :user/name "Ada"}]'
build/vevdb query app.vev '[:find ?name :where [?e :user/name ?name]]'
build/vevdb pull app.vev '[:user/name]' 1
build/vevdb info app.vev
```

Query, transaction, and pull arguments can also be loaded from files with
`@path`.

## Clojure

The Clojure API is the most polished public wrapper today. It accepts ordinary
Clojure data and follows the same connection -> DB value -> query shape:

```clojure
(require '[vev.core :as d])

(def conn (d/create-conn))

(d/transact conn
  [{:db/id 1
    :artist/name "John Lennon"}
   {:db/id 2
    :artist/name "Yoko Ono"}])

(def db (d/db conn))

(d/q
  '[:find ?name
    :where [?e :artist/name ?name]]
  db)

(d/pull db [:artist/name] 1)
```

Registered transaction functions use the same Datomic-shaped tx-data calls.
Install the ident in the DB, then provide executable behavior from the host
process:

```clojure
(with-open [fns (d/tx-fns conn
                  {:artist/rename
                   (fn [db e name]
                     [[:db/add e :artist/name name]])})]
  (d/transact conn [[:db/add 100 :db/ident :artist/rename]])
  (d/transact conn [[:artist/rename 1 "John Winston Lennon"]] fns))
```

Successful transaction reports can be observed with listeners:

```clojure
(def listener
  (d/listen conn :audit #(println (:tx-data %))))

(d/transact conn [{:db/id 3 :artist/name "George Harrison"}])
(d/unlisten conn listener)
```

Durability is a separate connection choice:

```clojure
(def durable (d/connect "app.vev"))

(d/transact durable [{:db/id 1 :artist/name "Durable Ada"}])
(d/q
  '[:find ?name
    :where [?e :artist/name ?name]]
  (d/db durable))
```

For local development from this repo:

```sh
clojure -M:clj-dev
```

Then open `examples/clojure/getting_started.clj` in an editor and evaluate the
forms inside its `(comment ...)` block one at a time.

This local alias uses the Java loader, which looks for the platform library
under `build/lib`. The intended published Clojure experience is a normal
deps.edn dependency that pulls in and loads the platform native library itself:

```clojure
{:deps {com.vevdb/vev-clj {:mvn/version "0.2.0-rc.2"}}}
```

The same shape can be tested locally after `scripts/package_jvm.sh`:

```clojure
{:mvn/local-repo "/path/to/vev/build/m2"
 :deps {com.vevdb/vev-clj {:mvn/version "0.2.0-rc.2"}}}
```

The combined release gate runs `scripts/smoke_jvm_coordinates.sh` against a
fresh Clojure project and a fresh Maven project. It verifies that
`com.vevdb/vev-clj` is enough for Clojure and `com.vevdb:vev-java` is enough
for Java, including automatic extraction of the current platform library.

DB snapshots are passable immutable values with JVM-managed cleanup. Use them
like Datomic DB values; they do not normally need `with-open`. Explicitly
closing a DB snapshot is only useful when a tight loop needs deterministic
release. Connections and explicitly allocated helpers such as prepared queries
should still be closed when their application lifecycle ends.

## Kvist

Kvist applications import the high-level `vev_app` package and use the same
connection -> immutable DB value -> query shape. Queries, transactions, and
pull patterns can be named, immutable Kvist data values rather than EDN
strings:

```clojure
(package main)

(import data "kvist:data")
(import fmt "core:fmt")
(import d "../src/vev_app")

(def artists
  '[{:db/id 1 :artist/name "John Lennon"}
    {:db/id 2 :artist/name "Yoko Ono"}])

(def artist-names
  '[:find ?name
    :where [?e :artist/name ?name]])

(def artist-pattern
  '[:artist/name])

(defn main []
  (let [conn (d.create-conn)]
    (defer (d.close conn))
    (d.transact conn artists)
    (let [snapshot (d.db conn)]
      (defer (d.close snapshot))
      (let [result (d.q artist-names snapshot)
            artist (d.pull snapshot artist-pattern 1)]
        (for [[name] result]
          (fmt.println (data.string name)))
        (let [{name :artist/name} artist]
          (fmt.println (data.string name)))))))
```

Durability changes only connection creation:

```clojure
(let [conn (d.connect "app.vev")]
  ...)
```

Quoted values are static `Data`, so the same value can be passed to `d.q`,
`d.transact`, `d.pull`, or `d.db-with`. Keep queries quoted when symbols such
as `?name` are part of the query data.

When `Data` is expected, transaction and input collections can instead use
ordinary contextual literals. Runtime names and expressions are inserted
directly, without quasiquote and unquote:

```clojure
(defn contact-tx [id: i64, name: string] -> Data
  [{:db/id id :contact/name name}])

(d.transact conn
  [[:db/add [:entity/id "counter"] :entity/value index]])

(d.q contacts-by-emails snapshot [first-email second-email])
```

Use `q-text` only when a query arrives as EDN text at runtime:

```clojure
(d.q-text query-text snapshot input-text)
```

High-level query and pull results are ordinary immutable `Data`. Destructure
known tuple, relation-row, return-map, and nested pull shapes directly:

```clojure
(let [[name company] (d.q contact-tuple-query snapshot email)
      {profile-name :contact/name
       {friend-name :contact/name} :contact/knows}
        (d.pull snapshot contact-profile-pattern entity)]
  ...)

(for [[name company] (d.q contacts-query snapshot)]
  ...)

(for [{name :name company :company}
      (d.q contact-map-query snapshot email)]
  ...)
```

Sequential destructuring supplies `nil` for a missing position, including an
empty sequence. Validate counts or kinds first when missing data would be
invalid. For optional map access, keywords are callable:

```clojure
(let [company (:contact/company profile)
      fallback (:contact/company profile "Independent")]
  ...)
```

This ergonomic `Data` style is the public and dynamic boundary. VevDB keeps typed
columns, native result builders, storage indexes, and ownership-sensitive query
inputs inside the engine where their native representation is deliberate.
Explicit conversions such as `data.int` and `data.string` remain the boundary
from `Data` to native Kvist values.

The database handle is an immutable snapshot and can be passed through normal
Kvist code. Native handles own resources, so the owner closes each connection
and DB snapshot exactly once with `d.close`; immutable `Data` results are
managed values. The complete in-memory and durable application is
`examples/kvist/contact_book.kvist`.

## Python

The Python client is a pure `ctypes` wrapper today:

```python
import vevdb

with vevdb.create_conn() as conn:
    conn.transact('[{:db/id 1 :user/name "Ada"}]')
    with conn.db() as db:
        print(vevdb.q('[:find ?name :where [?e :user/name ?name]]', db))
        print(db.pull('[:user/name]', vevdb.Entity(1)))

with vevdb.connect("app.vev") as conn:
    conn.transact('[{:db/id 1 :user/name "Durable Ada"}]')
    print(vevdb.q('[:find ?name :where [?e :user/name ?name]]', conn))
```

`examples/python/contact_book.py` is a small app-style smoke that uses the same
API in both modes: in-memory for test-style immutable DB values, durable for
close/reopen persisted state.

```sh
scripts/smoke_real_app.sh
```

`scripts/smoke_python_package.sh` validates the package metadata and simulates
a future wheel layout by loading a bundled `native/<platform>/<library>` next
to `vevdb.py`.

## Node/TypeScript

The Node wrapper loads a native N-API addon and exposes a small CommonJS API:

```js
const vev = require("@vevdb/vev");
const conn = vev.createConn();
try {
  conn.transact('[{:db/id 1 :user/name "Ada"}]');
  const db = conn.db();
  try {
    console.log(vev.q('[:find ?name :where [?e :user/name ?name]]', db));
    console.log(db.pull('[:user/name]', 1));
  } finally {
    db.close();
  }
} finally {
  conn.close();
}
```

`scripts/smoke_node_package.sh` simulates a future npm package by loading
`native/<platform>/vev_native.node` and the adjacent platform `libvev` from a
temporary package directory.

## Go

The Go wrapper is importable at the planned module path:

```go
import vev "github.com/vevdb/vev/clients/go"

conn, err := vev.CreateConn()
defer conn.Close()

conn.Transact(`[{:db/id 1 :user/name "Ada"}]`)
db, err := conn.DB()
defer db.Close()

rows, err := db.Q(`[:find ?name :where [?e :user/name ?name]]`, "[]")
defer rows.Close()

pulled, err := db.Pull("[:user/name]", 1)

durable, err := vev.Connect("app.vev")
defer durable.Close()
```

`scripts/smoke_go_package.sh` verifies that shape from a temporary Go module
using a local `replace` to this checkout.

## Rust

The Rust wrapper is a local crate over the C ABI and follows the intended RAII
shape:

```rust
let conn = Conn::open_memory()?;

conn.transact(r#"[{:db/id 1 :user/name "Ada"}]"#);

let db = conn.db()?;
let rows = db.q("[:find ?name :where [?e :user/name ?name]]", "[]")?;
let pulled = db.pull("[:user/name]", 1)?;

let durable = DurableConn::open("app.vev")?;
durable.transact(r#"[{:db/id 1 :user/name "Durable Ada"}]"#)?;
let durable_rows = durable.q("[:find ?name :where [?e :user/name ?name]]", "[]")?;
```

## Java

Java uses the Java 25 Foreign Function & Memory wrapper in `clients/java`:

```java
import com.vevdb.Vev;

Vev vev = Vev.load();
Vev.Connection conn = vev.createConn();
conn.transact("[{:db/id 1 :user/name \"Ada\"}]");
Vev.DB db = conn.db();
System.out.println(vev.queryRows(java.util.Map.of(
    "query", "[:find ?name :where [?e :user/name ?name]]",
    "args", java.util.List.of(db))));
System.out.println(db.pull("[:user/name]", 1));
```

Local Java runs need Java 25 and native access for the unnamed module:

```sh
--enable-native-access=ALL-UNNAMED
```

The Maven Central coordinate is `com.vevdb:vev-java`. The artifact contains
the supported platform native libraries, so ordinary Java projects have a
one-dependency VevDB setup.

## C

The raw C ABI is the stable lowest-level integration surface:

```sh
PKG_CONFIG_PATH="$PWD/build/lib/pkgconfig" \
  clang clients/c/smoke.c $(pkg-config --cflags --libs vev) \
  -Wl,-rpath,"$PWD/build/lib" \
  -o build/examples/c/vev_c_smoke
```

Use `include/vev.h` for the current handle and ownership rules.
`scripts/smoke_c_package.sh` verifies the pkg-config package from a temporary C
program.

## Other Clients

Current smoke clients:

- Python: `clients/python`
- Rust: `clients/rust`
- Go: `clients/go`
- Node/TypeScript: `clients/node`
- Odin: `clients/odin`

Python, Rust, Go, and Node remain source-oriented clients while their public
package shapes stabilize. C is distributed as the platform native SDK, and
Odin is distributed as a platform vendor bundle containing both its package and
native engine.

## Current Limitations

- VevDB is still pre-production.
- Durable SQLite storage works, but the next storage milestone is shared
  immutable/chunked index storage rather than whole DB/index copying.
- The C ABI is the portability boundary; higher-level clients are still being
  shaped around it.

## Local Repository Checks

From this repository, the broad smoke suite is:

```sh
scripts/smoke_clients.sh
scripts/smoke_cli.sh
scripts/smoke_cli_package.sh
scripts/smoke_packages.sh
```

For focused package checks:

```sh
scripts/smoke_c_package.sh
scripts/smoke_jvm_package.sh
scripts/smoke_python_package.sh
scripts/smoke_node_package.sh
scripts/smoke_go_package.sh
scripts/smoke_rust_package.sh
scripts/smoke_odin_package.sh
```

These build the self-contained native library under `build/lib`, local JVM
proof artifacts under `build/jvm` and `build/m2`,
`build/lib/pkgconfig/vev.pc`, `build/vevdb`, a standalone CLI archive under
`build/release/cli`, and temporary smoke artifacts or projects for the host
wrappers.
