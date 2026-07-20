# VevDB for Java

This package is the Java 25 Foreign Function & Memory wrapper for VevDB's native
C ABI. It is the lower JVM layer used by the Clojure package.

Current local development:

```sh
scripts/build_c_abi.sh
scripts/stage_jvm_native.sh
scripts/package_jvm.sh
```

That builds the platform native library under `build/lib`, compiles the Java
wrapper into `build/examples/java`, runs the Java smoke, and stages the native
library under `build/jvm-native` using the resource layout below.

The wrapper loads the native library in this order:

1. `-Dvev.library=/path/to/libvev.dylib`
2. `VEV_LIB=/path/to/libvev.dylib`
3. the platform library under `build/lib`
4. bundled classpath resource:
   `com/vevdb/native/<platform>/<mapped-library-name>`

Java 25's FFM API is final. Local runs only need native access enabled:

```sh
--enable-native-access=ALL-UNNAMED
```

Maven coordinate:

```text
com.vevdb:vev-java
```

The combined release artifact is a one-dependency entry point for Java
applications. It contains every verified platform native library, so Java
users do not list a separate `vev-native-*` dependency.

Basic usage:

```java
try (Vev vev = Vev.load();
     Vev.Connection conn = vev.createConn()) {
    conn.transact("[{:db/id 1 :user/name \"Ada\"}]");
    try (Vev.DB db = conn.db()) {
        System.out.println(vev.query(Map.of(
            "query", "[:find ?name :where [?e :user/name ?name]]",
            "args", List.of(db))));
        System.out.println(db.pull("[:user/name]", 1));
    }
}
```

`Vev.query` follows the Datomic request-map and `:find` result shape. Relation
queries return a `Set` of tuple `List` values, collections and tuples return
`List` values, and scalar finds return the scalar or `null`. Reusable prepared
queries remain available through `queryResult`, `DB.query`, and `ResultSet`.

DB snapshots can also produce entity views. The view is tied to the immutable
DB value, not the live connection:

```java
try (Vev.DB db = conn.db();
     Vev.EntityView ada = db.entity(1);
     Vev.EntityView friend = ada.ref(":user/friend")) {
    System.out.println(ada.get(":user/name"));
    System.out.println(ada.values(":user/email"));
    System.out.println(friend.get(":user/name"));
    System.out.println(ada.touch());
}
```

Parser tooling can inspect a single where clause with
`vev.parseClauseEdn("[?e :user/name ?name]")`.

Transaction functions use a host registry plus a Datomic-style installed ident
in the DB:

```java
try (Vev.TxFunctionRegistry fns = vev.txFunctionRegistry()) {
    fns.register(":user/set-age", (db, args) ->
        "[[:db/add " + args.get(0) + " :user/age " + args.get(1) + "]]");
    conn.transact("[[:db/add 100 :db/ident :user/set-age]]");
    try (Vev.TxReport report =
             conn.transactReport("[[:user/set-age 1 42]]", fns)) {
        System.out.println(report.value());
    }
}
```

The Java callback returns EDN tx-data text. Higher-level clients such as
Clojure can wrap this and let callbacks return ordinary host data. The same
registry shape works for durable `vev.connect("app.vev")` handles.

Typed transaction builders are also accepted by durable connections, so bulk
host writes do not have to round-trip through EDN text:

```java
try (Vev.DurableConnection durable = vev.connect("app.vev");
     Vev.TxBuilder tx = vev.txBuilder(2)) {
    tx.addString(1, ":user/name", "Ada");
    tx.addString(1, ":user/email", "ada@example.com");
    try (Vev.TxReport report = durable.transactReport(tx)) {
        System.out.println(report.value());
    }
}
```

For explicit bulk ingest, pass several builders. VevDB commits them as one
ordinary durable transaction and returns one transaction report:

```java
try (Vev.DurableConnection durable = vev.connect("app.vev");
     Vev.TxBuilder first = vev.txBuilder(1);
     Vev.TxBuilder second = vev.txBuilder(1)) {
    first.addString(2, ":user/name", "Grace");
    second.addString(3, ":user/name", "Hedy");
    try (Vev.TxReport report = durable.transactReport(List.of(first, second))) {
        System.out.println(report.value());
    }
}
```

Successful transaction reports can be observed with a listener registration:

```java
try (Vev.TxReportListenerRegistration listener =
         conn.listen("audit", report -> System.out.println(report))) {
    conn.transact("[{:db/id 2 :user/name \"Grace\"}]");
}
```

The callback receives the decoded report value while the native report handle is
still valid. Keep data you need by copying it into ordinary Java structures
inside the callback.

Durable connections returned by `vev.connect("app.vev")` expose the same
`listen` / `unlisten` API. Durable listener reports are delivered after
successful commits only.

The Java package supports explicit native library paths, but normal consumers
do not need one. The combined release merges each verified platform library
into `com.vevdb:vev-java` as classpath resources such as:

```text
com/vevdb/native/darwin-aarch64/libvev.dylib
com/vevdb/native/darwin-x86_64/libvev.dylib
com/vevdb/native/linux-aarch64/libvev.so
com/vevdb/native/linux-x86_64/libvev.so
com/vevdb/native/windows-x86_64/vev.dll
```

`scripts/stage_jvm_native.sh` creates that resource tree for one platform.
`scripts/assemble_jvm_release.sh` verifies the platform-independent Java
classes agree and assembles the final cross-platform jar after all platform
builds pass.

`scripts/package_jvm.sh` builds local proof jars under `build/jvm`:

```text
vev-java-0.2.0-rc.2.jar
vev-native-<platform>-0.2.0-rc.2.jar
vev-clj-0.2.0-rc.2.jar
```

It also writes a local Maven-style repository under `build/m2`. These
per-platform artifacts exercise native loading during platform builds. The
combined release writes the publishable `vev-java` and `vev-clj` artifacts
after merging all platform resources.

`scripts/smoke_jvm_coordinates.sh` verifies a fresh Maven project with only
`com.vevdb:vev-java` and a fresh Clojure project with only
`com.vevdb/vev-clj`. Neither consumer selects a platform artifact or configures
a native-library path.

Durable stores are opened through VevDB APIs with paths such as `app.vev`. The
release native library includes SQLite with FTS5. Java and Clojure applications
do not install or configure SQLite; they load VevDB and call `connect`.
