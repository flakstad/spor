# VevDB for Odin

VevDB is authored in Kvist and lowers through Odin, but generated Odin is build
output, not the public package surface. The supported Odin API is the small,
handwritten package in [`vev`](vev).

The package dynamically loads the VevDB C ABI, checks `VEV_ABI_VERSION`, and
provides explicit Odin ownership around the native library and connections.
SQLite with FTS5 is included in the native VevDB library.

Odin intentionally has no official package manager. Vendor the `vev` directory
in your source tree or pin this repository as a Git submodule. A project with
this layout:

```text
my-app/
  main.odin
  vendor/
    vev/
      doc.odin
      vev.odin
```

can use:

```odin
import vev "vendor/vev"

library, ok := vev.load("/path/to/libvev")
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

The complete consumer example is in [`example`](example). Run it from the
repository root after building the native library:

```sh
scripts/build_c_abi.sh
odin run clients/odin/example -- build/lib/libvev.dylib
```

Use `libvev.so` on Linux and `vev.dll` on Windows. Release native SDK archives
contain the matching library, C header, `pkg-config` metadata, license, and no
external SQLite runtime dependency.

The release-shaped package proof checks the package, runs the consumer example,
and also runs the lower-level ABI coverage program:

```sh
scripts/smoke_odin_package.sh
```

The next standalone client repository should be `vevdb/vev-odin`, with the
`vev` package at its root, tagged source releases, a pinned tested Odin compiler
version, examples, and CI against every native VevDB release platform. That
repository shape is deliberately vendor-friendly and is the artifact to share
with the Odin community.
