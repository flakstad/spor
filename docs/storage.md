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

Long-lived latency-sensitive applications can explicitly call
`ensure-resident!` after connecting. That connection then retains the current
immutable datoms and indexes in memory, so repeated queries and transaction
planning use VevDB's resident execution path. Transactions are still appended
to the same durable SQLite store and a newly opened connection observes them.
The choice is per connection: it is a memory/latency policy, not another store
format or source of truth.

In resident mode, acknowledgement follows the transaction-log commit. Durable
index roots are derived state and may temporarily trail that commit; they are
never part of the truth boundary. Resident reads already own the committed
indexes, and a newly opened connection detects an unindexed log tail and
materializes it rather than returning a stale root. Maintenance may publish a
new root independently.

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
