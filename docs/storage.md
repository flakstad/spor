# Storage

VevDB supports in-memory databases and durable local stores.

```clojure
(d/create-conn)             ; in memory
(d/connect "example.db")    ; durable
```

Both expose the same transaction, database-value, query, pull, entity, index,
and history model.

## Durable stores

Durable stores use SQLite internally. The native library includes a pinned
SQLite build with FTS5. Applications do not install SQLite, create tables, run
migrations, or issue SQL.

VevDB stores datoms, transaction metadata, and persistent EAVT, AEVT, AVET, and
VAET index roots. Reads use immutable snapshots backed by those indexes.

Ordinary paths and `sqlite://` paths select the same backend. VevDB does not
require a file extension. Replace `example.db` above with the path you want.

## Concurrency

Several connections and processes may open one store.

- Readers use stable snapshots.
- One writer commits at a time.
- Writers refresh the current basis before assigning a transaction ID.
- Existing database values do not change.
- Call `db` again to observe newer commits.

SQLite WAL mode provides the file-level reader/writer coordination.

The store format is private to VevDB. Use VevDB APIs for reads, writes, and
inspection.
