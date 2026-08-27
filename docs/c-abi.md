# C ABI

The C ABI is VevDB's portable native boundary. The
[header](../include/vev.h) is the API reference.

It provides:

- in-memory and durable connections
- immutable database values
- EDN transactions, queries, inputs, and pull patterns
- prepared queries, statements, and typed bindings
- typed result and value trees
- transaction reports and listeners
- index and history reads
- typed transaction builders
- explicit durable maintenance

## Build

```sh
scripts/build_native_library.sh
```

The build writes the header, library, and `pkg-config` file under `build/`.

Compile a consumer:

```sh
export PKG_CONFIG_PATH="$PWD/build/lib/pkgconfig"

clang clients/c/smoke.c \
  $(pkg-config --cflags --libs vev) \
  -Wl,-rpath,"$PWD/build/lib" \
  -o build/examples/c/vev_c_smoke
```

Run the full ABI smoke:

```sh
scripts/build_c_abi.sh
```

## Ownership

Connection, database, prepared-query, statement, result, report, builder, and
owned-value handles must be released with their matching function.

Strings returned by VevDB must be released with `vev_string_free`.

Values borrowed from a result, report, or owned value remain valid only while
their owner is alive. Callback arguments are borrowed for the callback.

`vev_tx_report_value` returns a borrowed immutable root owned by its
`vev_tx_report_t`. Its descendants have the same lifetime. In contrast,
`vev_tx_report_db_before` and `vev_tx_report_db_after` each return a retained
immutable database handle which the caller releases independently. They are
the exact values captured by that transaction report, not later reads from the
connection.

`vev_connection_tx_profile_value` returns an owned Value handle. Release it
with `vev_value_handle_free`. Profiling is opt-in: reset enables and clears the
ABI and engine phase accumulators, disable stops clock reads while preserving
the last values for inspection.

Do not free borrowed handles.

## Errors

Constructors and prepared operations provide status and error accessors.
Text convenience functions return EDN error data where documented.

Check status before reading a handle. Error strings are owned by the caller and
must be released with `vev_string_free`.

## ABI version

Check `VEV_ABI_VERSION` or `vev_abi_version()` before loading a library built
separately from the wrapper.

The native release bundle contains:

```text
include/vev.h
lib/<platform library>
lib/pkgconfig/vev.pc
examples/basic.c
LICENSE
README.md
```

Run `bench/compare_abi.sh` to measure native-boundary overhead.
