# VevDB for Odin

VevDB is authored in Kvist and lowers through Odin, but generated Odin is build
output, not the public package surface. The supported Odin API is the small,
handwritten package in [`vev`](vev).

The package dynamically loads the VevDB C ABI, checks `VEV_ABI_VERSION`, and
provides explicit Odin ownership around the native library and connections.
SQLite with FTS5 is included in the native VevDB library.

Odin intentionally has no official package manager. Download the
`vev-odin-<platform>-<version>.zip` asset from a VevDB release and unpack its
`vev` directory under `vendor/`. The archive pins the Odin source and matching
native engine as one dependency:

```text
my-app/
  main.odin
  vendor/
    vev/
      doc.odin
      vev.odin
      README.md
      LICENSE
      lib/
        libvev.dylib | libvev.so | vev.dll
```

can use:

```odin
import vev "vendor/vev"

library, ok := vev.load_bundled("vendor/vev")
assert(ok)
defer vev.unload(&library)

connection, ok := vev.open_memory(&library)
assert(ok)
defer vev.close(&connection)

tx, ok := vev.transact(&connection, `[{:db/id 1 :user/name "Ada"}]`)
assert(ok)
defer delete(tx)

rows, ok := vev.query(
    &connection,
    `[:find ?name :where [?e :user/name ?name]]`,
)
assert(ok)
defer delete(rows)
```

For a shared dependency directory, expose a collection at build time:

```sh
odin build . -collection:deps=vendor
```

and import it as `import vev "deps:vev"`.

Durable stores are first-class and expose typed result traversal:

```odin
connection, ok := vev.connect(&library, "app.vev")
assert(ok)
defer vev.close(&connection)

tx, ok := vev.transact(&connection, `[{:db/id 1 :user/name "Ada"}]`)
assert(ok)
defer delete(tx)

rows, ok := vev.query_rows(
	&connection,
	`[:find ?name :where [?e :user/name ?name]]`,
)
assert(ok)
defer vev.close(&rows)

name, ok := vev.value_edn(&rows, 0, 0)
assert(ok)
defer delete(name)
```

Each `query_rows` call takes a fresh immutable DB snapshot. An application,
REPL, or VevDB CLI can therefore share the same durable store, while retained
result handles continue to represent the query basis they captured.

The complete consumer example is in [`example`](example). Run it from the
repository root after packaging the vendor bundle:

```sh
scripts/package_odin_bundle.sh
scripts/smoke_odin_bundle.sh
```

SQLite is included in the bundled native engine; users do not install SQLite
or configure a native library path.

The local package proof checks the source package, runs the consumer example,
and also runs the lower-level ABI coverage program:

```sh
scripts/smoke_odin_package.sh
```

The canonical, vendor-friendly client repository is
[`vevdb/vev-odin`](https://github.com/vevdb/vev-odin). It keeps the package at
the repository root and tests fresh consumers against every native VevDB
release platform. The copy here is retained so the engine release gate can
verify client and ABI changes together.
