# Vev Node/TypeScript

This is a Node N-API smoke client over Vev's C ABI. It contains a small native
addon plus a CommonJS wrapper and TypeScript declarations.

Current local development:

```sh
scripts/build_c_abi.sh
```

The build script compiles `clients/node/vev_native.cc` into
`build/examples/node/vev_native.node` and runs `clients/node/smoke.js` with
`VEV_NODE_NATIVE` pointing at that addon.

The wrapper loads the native addon in this order:

- `VEV_NODE_NATIVE`
- `vev_native.node` next to `vev.js`
- `native/<platform>/vev_native.node` next to `vev.js`

Planned package name:

```text
@vevdb/vev
```

`clients/node/package.json` contains the current package metadata and bundled
native-file allowlist. It remains `"private": true` until the package is ready
to publish, but the local smoke validates the intended package identity.

Example:

```js
const vev = require("@vevdb/vev");

const conn = vev.createConn();
try {
  conn.transact('[{:db/id 1 :user/name "Ada"}]');

  const db = conn.db();
  try {
    console.log(vev.q('[:find ?name :where [?e :user/name ?name]]', db));
    console.log(db.pull('[:user/name]', 1));
  } finally {
    db.close();
  }
} finally {
  conn.close();
}
```

`conn.queryText(...)` remains available for quick EDN text calls, but DB
snapshots are the closer match to Vev's immutable database value model.
Use `conn.prepare(...)` when reusing the same query many times.

The package should continue to expose explicit native-addon loading for local
development while supporting bundled platform binaries. `scripts/build_c_abi.sh`
links the addon with both repo-local and addon-relative library rpaths, so a
future package can place `vev_native.node` and the platform `libvev` in the same
`native/<platform>` directory.

`scripts/smoke_node_package.sh` verifies the package metadata and package-like
layout from a temporary directory without `VEV_NODE_NATIVE`.

Durable stores are opened through Vev APIs with paths such as `app.vev`. The
Node addon loads the Vev native library, whose release build includes SQLite
with FTS5. Node application code does not install or configure SQLite.
