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

For applications, download the `vev-native-<platform>-<version>.zip` archive
from a VevDB release. It is a relocatable C SDK containing the header, matching
native/import library, `pkg-config` metadata, this README, and
`examples/basic.c`. No VevDB source checkout or SQLite installation is needed.

After extracting it:

```sh
export VEV_SDK="$PWD/vev-<version>"
PKG_CONFIG_PATH="$VEV_SDK/lib/pkgconfig" \
  clang "$VEV_SDK/examples/basic.c" \
  $(PKG_CONFIG_PATH="$VEV_SDK/lib/pkgconfig" pkg-config --cflags --libs vev) \
  -Wl,-rpath,"$VEV_SDK/lib" \
  -o basic
./basic example.vev
```

On Windows, compile against `include/vev.h` and `lib/vev.lib`, and keep
`lib/vev.dll` on `PATH` or beside the application executable.

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

`vev_connection_query_edn` is the compact durable query entry point for simple
applications. Prepared queries, typed results, immutable DB snapshots, pull,
and typed transaction builders remain available when more control is needed.
