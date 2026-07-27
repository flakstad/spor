# Runtime dependencies

Release artifacts include the native VevDB engine and SQLite.

| Distribution | Runtime |
| --- | --- |
| CLI | none beyond the platform runtime |
| C SDK | packaged VevDB shared library |
| Java | JDK 25 or newer |
| Clojure | JDK 25 or newer |
| Odin | packaged VevDB shared library |

Java and Clojure packages extract the matching native library from the Java
artifact. Users do not select a platform JAR or install SQLite. JVM processes
should run with native access enabled:

```sh
--enable-native-access=ALL-UNNAMED
```

C and Odin distributions keep the package and matching native library
together.

For source-build requirements, see [Build from source](building.md).

Use ordinary file paths for durable stores:

```text
example.db
data/example.db
```
