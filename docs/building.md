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
- `VEV_SQLITE_LIB_DIR`: prebuilt SQLite library directory
- `VEV_LIB`: native VevDB library for client tests

Build output stays under `build/`.
