# VevDB for Node.js

**Status: in progress. Not published.**

This N-API integration test will move to a standalone `@vevdb/vev` package
repository.

```sh
scripts/build_c_abi.sh
scripts/smoke_node_package.sh
```

The wrapper loads the addon from:

1. `VEV_NODE_NATIVE`
2. `vev_native.node` beside `vev.js`
3. `native/<platform>/vev_native.node`

```js
const vev = require("./vev");
const conn = vev.createConn();

try {
  conn.transact('[{:db/id 1 :user/name "Ada"}]');
  console.log(conn.queryText(
    '[:find ?name :where [?e :user/name ?name]]', '[]'));
} finally {
  conn.close();
}
```

Native handles require `close()`. SQLite is included in the VevDB library.
