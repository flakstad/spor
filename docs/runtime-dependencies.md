# Runtime Dependencies

VevDB applications use VevDB APIs and VevDB store files. They do not install SQLite,
set up SQLite schemas, run SQLite migrations, or issue SQL.

Durable VevDB stores are implemented on SQLite. Release builds compile the
official SQLite amalgamation into `libvev` and the standalone CLI with FTS5
enabled. The amalgamation version and SHA3-256 checksum are pinned in
`scripts/build_sqlite.sh`.

## What Users Install

The prebuilt distributions are self-contained:

- Clojure users add `com.vevdb/vev-clj`; it brings in `vev-java` and the
  bundled native VevDB library.
- Java users add `com.vevdb:vev-java`; its release jar contains the supported
  platform libraries.
- CLI users unpack the platform `vevdb-cli` archive and place `vevdb` on
  `PATH`.
- C ABI consumers unpack the native bundle containing `vev.h` and `libvev`.

None of these consumers installs SQLite separately. Java and Clojure currently
require Java 21 and the FFM preview/native-access options documented by their
packages.

## Source Builds

`scripts/build_sqlite.sh` downloads the pinned SQLite amalgamation once into
`build/vendor/sqlite`, verifies its SHA3-256 digest, and builds a static
library. `scripts/build_native_library.sh` and `scripts/build_cli.sh` use that
library by default.

Set `VEV_SQLITE_CACHE_DIR` to share the downloaded and compiled SQLite cache.
Set `VEV_SQLITE_LIB_DIR` only when deliberately testing another compatible
static SQLite build.

Building VevDB from source requires:

- Kvist and Odin
- Clang
- `llvm-ar` or `ar`
- Python 3, `curl`, and `unzip` for the pinned amalgamation

No system SQLite development or runtime package is required.

## Verifying Artifacts

The release gate runs:

```sh
scripts/check_self_contained_native.sh build/lib/libvev.dylib
scripts/check_self_contained_native.sh build/vevdb
```

The check uses `otool`, `ldd`, or `objdump` according to the platform and fails
if an artifact depends on a SQLite dynamic library.

## Store Paths

Use ordinary file paths for local durable stores:

```text
app.vev
data/app.vev
```

SQLite manages the file internally, but it is a VevDB store from the
application's point of view. The extension is not semantically important;
`.vev` is the recommended convention.
