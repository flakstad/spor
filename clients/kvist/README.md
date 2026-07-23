# VevDB for Kvist

This package preserves Kvist's `Data`-oriented Vev API while loading the
prebuilt Vev native engine through its stable C ABI. Importing it does not
compile Vev's implementation into the application.

Unpack the platform bundle under `vendor/vev` and import its `kvist` package:

```clojure
(import d "deps:vev/kvist")

(let [conn (d.connect "app.vev")
      db (d.db conn)
      names (d.q '[:find ?name :where [?e :person/name ?name]] db)]
  ...)
```

Build with `-collection:deps=vendor`. The facade finds `libvev` from `VEV_LIB`
for explicit development/test overrides, beside the executable for command-line
applications, or under `Contents/Frameworks` in a macOS application bundle.

Transactions and queries accept ordinary local Kvist `Data`; only canonical EDN
inputs and opaque native handles cross the library boundary. Canonical query
text is prepared once per connection, and typed result trees are traversed into
fresh local `Data` values without rendering result EDN.
