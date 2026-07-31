# VevDB for C

The C ABI is VevDB's native integration surface.

Build and test it:

```sh
scripts/build_c_abi.sh
```

Build output:

```text
build/include/vev.h
build/include/vev_sqlite.h
build/lib/<platform library>
build/lib/pkgconfig/vev.pc
```

Release SDKs contain the header, matching library, `pkg-config` file, and a
small example. SQLite is included.

Compile the repository smoke program:

```sh
export PKG_CONFIG_PATH="$PWD/build/lib/pkgconfig"

clang clients/c/smoke.c \
  $(pkg-config --cflags --libs vev) \
  -Wl,-rpath,"$PWD/build/lib" \
  -o build/examples/c/vev_c_smoke
```

Opaque handles and returned strings have explicit ownership. See `vev.h` and
the [C ABI guide](https://github.com/vevdb/vev/blob/main/docs/c-abi.md).

The same library also provides a Vev-prefixed SQLite API for ordinary
application databases. It uses the SQLite bundled in VevDB without exporting
`sqlite3_*` symbols. See the
[SQLite guide](https://github.com/vevdb/vev/blob/main/docs/sqlite.md) and
`vev_sqlite.h`.
