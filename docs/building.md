# Build from source

## Requirements

A native build needs:

- Kvist
- Odin
- Clang
- Python 3
- `curl`
- `unzip`
- `ar` or `llvm-ar`

The build downloads a pinned SQLite amalgamation and verifies its checksum.

## SQLite

VevDB links SQLite into the native library by default. This is the build used
for releases:

```sh
scripts/build_native_library.sh
```

To use SQLite supplied by your application or system:

```sh
VEV_SQLITE_MODE=system scripts/build_native_library.sh
```

The linker must be able to find `sqlite3`. Set `VEV_SQLITE_LIB_DIR` when it is
not on the normal library path. Setting it also selects `system` mode:

```sh
VEV_SQLITE_LIB_DIR=/path/to/sqlite/lib \
scripts/build_native_library.sh
```

The same settings work with `scripts/build_cli.sh`.

VevDB does not yet have a SQLite-free build. In-memory databases do not use
SQLite at runtime, but the native library still links it.

## Native library

```sh
scripts/build_native_library.sh
```

Outputs:

```text
build/include/vev.h
build/lib/libvev.dylib   # macOS
build/lib/libvev.so      # Linux
build/lib/vev.dll        # Windows
build/lib/vev.lib        # Windows import library
```

## CLI

```sh
scripts/build_cli.sh
build/vevdb --version
```

On a release tag, the command prints the release version. A local build from
another commit also prints the abbreviated commit and its date.

## Checks

Run the core client and CLI checks:

```sh
scripts/smoke_clients.sh
scripts/smoke_cli.sh
```

`smoke_clients.sh` builds the native library first. Missing optional language
toolchains are skipped.

Run all package checks only when every client toolchain is installed:

```sh
scripts/smoke_packages.sh
```

Run the full release build only from a complete release environment:

```sh
scripts/check_release_environment.sh
scripts/build_release.sh
```

The release build requires every supported language toolchain, including JDK
25 or newer.

## Overrides

- `KVIST_BIN`: Kvist executable
- `KVIST_REPO_DIR`: Kvist checkout
- `KVIST_PACKAGES_DIR`: Kvist package directory
- `VEV_SQLITE_MODE`: `bundled` (default) or `system`
- `VEV_SQLITE_LIB_DIR`: SQLite library directory in `system` mode
- `VEV_LIB`: native VevDB library for client tests

Build output stays under `build/`.
