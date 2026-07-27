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
