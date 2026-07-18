# Vev Odin

Vev is authored in Kvist and lowers through Odin, but generated Odin is build
output, not the public Odin package surface.

For Odin applications, the supported direction is a small wrapper over the C
ABI:

- link against the platform library under `build/lib`
- import functions matching `include/vev.h`
- manage Vev handles explicitly, mirroring the C ABI ownership rules

`clients/odin/smoke.odin` is the first concrete proof of that direction. It
uses `core:dynlib` to load the Vev native library, opens an in-memory
connection, transacts EDN, runs a Datalog query, and frees returned C ABI
strings.

The smoke also exercises the DB-value path directly through the ABI:

```odin
snapshot := api.db(conn)
defer api.db_release(snapshot)

query := api.prepare_query(query_text)
defer api.free_query(query)

result := api.query_db(snapshot, query, empty_inputs)
defer api.string_free(result)
```

That is the shape a future Odin package should wrap in Odin-native `Conn`,
`DB`, prepared-query, and result types.

Run it from the repo root after building the native library:

```sh
scripts/build_c_abi.sh
odin run clients/odin -file
```

Or pass an explicit native library path:

```sh
odin run clients/odin -file -- build/lib/libvev.dylib
```

The focused package proof is:

```sh
scripts/smoke_odin_package.sh
```

It builds the smoke wrapper into a temporary directory and runs it against the
platform native Vev library, mirroring how an Odin application would dynamically
load `libvev`.

Directly depending on generated Odin should remain a development/debug escape
hatch rather than the documented integration path.

Durable stores are opened through Vev APIs with paths such as `app.vev`. The
release native library includes SQLite with FTS5; Odin application code does
not install or configure SQLite.
