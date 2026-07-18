# VevDB for C

The C ABI is VevDB's stable raw interop surface. Other clients should build on
top of this ABI rather than depending on Kvist or generated Odin internals.

Current local development:

```sh
scripts/build_c_abi.sh
```

That builds:

- `include/vev.h`
- the platform library under `build/lib`
- `build/lib/pkgconfig/vev.pc`

Manual compile example:

```sh
PKG_CONFIG_PATH="$PWD/build/lib/pkgconfig" \
  clang clients/c/smoke.c $(pkg-config --cflags --libs vev) \
  -Wl,-rpath,"$PWD/build/lib" \
  -o build/examples/c/vev_c_smoke
```

`scripts/smoke_c_package.sh` verifies the pkg-config SDK shape from a temporary
C program, including in-memory query and durable `vev_connect` open/write/reopen
query.

The C API owns opaque handles explicitly. Returned strings and arrays must be
freed with the matching `vev_*_free` function documented in `include/vev.h`.

Durable stores are opened through VevDB APIs, for example with a path like
`app.vev`. SQLite with FTS5 is statically included in release builds; no
SQLite installation or schema setup is required by the C application.
