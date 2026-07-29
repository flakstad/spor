# VevDB for Clojure

The public Clojure package lives in
[vevdb/vev-clj](https://github.com/vevdb/vev-clj).

```clojure
{:deps {com.vevdb/vev-clj {:mvn/version "0.2.2"}}}
```

This in-tree copy lets the engine test coordinated C ABI, Java, and Clojure
changes. Do not use it as the public package source.

```sh
scripts/smoke_jvm_package.sh
```
