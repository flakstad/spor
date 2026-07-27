# Packages

The Kvist API and C ABI are part of the engine. Published host packages wrap
the C ABI and live in standalone repositories.

## Standalone packages

| Language | Repository | Distribution |
| --- | --- | --- |
| Clojure | [vev-clj](https://github.com/vevdb/vev-clj) | `com.vevdb/vev-clj` |
| Java | [vev-java](https://github.com/vevdb/vev-java) | `com.vevdb:vev-java` |
| Odin | [vev-odin](https://github.com/vevdb/vev-odin) | release vendor bundle |

The Clojure package depends on the Java package. The Java artifact contains the
native libraries for supported platforms.

## Engine repository

This repository owns:

- the engine
- the [C header](../include/vev.h)
- the [Kvist API](../clients/kvist)
- native SDK and CLI releases
- cross-language release checks

The in-tree Java, Clojure, and Odin copies exist for coordinated engine checks.
Use their standalone repositories as the public source.

## In progress

| Language | Current integration code | Intended package |
| --- | --- | --- |
| Python | [clients/python](../clients/python) | `vevdb` |
| Rust | [clients/rust](../clients/rust) | `vevdb` |
| Go | [clients/go](../clients/go) | standalone Go module |
| Node.js / TypeScript | [clients/node](../clients/node) | `@vevdb/vev` |

These APIs are experimental. Their in-tree code is used for integration tests
while separate packages are prepared.

## Boundary

EDN is the portable text format for transactions, queries, inputs, pull
patterns, and diagnostics. Prepared and typed APIs avoid repeated parsing and
result rendering.

Host wrappers own:

- native library discovery
- handle lifetimes
- host value conversion
- package-manager conventions

They do not expose internal Kvist or generated Odin types.
