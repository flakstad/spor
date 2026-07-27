# VevDB for Java

The public Java package lives in
[vevdb/vev-java](https://github.com/vevdb/vev-java).

Maven coordinate:

```text
com.vevdb:vev-java
```

It requires JDK 25 or newer and contains the native VevDB libraries.

This in-tree copy lets the engine test coordinated C ABI and JVM changes. Do
not use it as the public package source.

```sh
scripts/smoke_jvm_package.sh
```
