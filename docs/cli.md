# CLI

The `vevdb` CLI reads and writes durable VevDB stores. SQLite is included in
the executable.

Download a CLI archive from a
[VevDB release](https://github.com/vevdb/vev/releases), unpack it, and put
`vevdb-<version>/bin/vevdb` on `PATH`.

## Commands

```text
vevdb --version
vevdb info <store>
vevdb transact <store> <transaction>
vevdb query <store> <query> [inputs]
vevdb pull <store> <pattern> <entity-id>
```

`<store>` may be a relative or absolute file path. Relative paths resolve from
the current working directory. VevDB does not require a file extension. The
examples below use `example.db`; replace it with the path you want.

## Write and read

```sh
vevdb transact example.db '[{:db/id 1 :user/name "Ada"}]'
vevdb query example.db '[:find ?name :where [?e :user/name ?name]]'
vevdb pull example.db '[:user/name]' 1
vevdb info example.db
```

Successful command output is EDN:

- `transact` prints a transaction report.
- `query` prints `{:ok ... :error ... :rows ...}`. Each row contains `:values`
  and any `:pulls`.
- `pull` prints the pulled entity map.
- `info` prints `{:basis-t ... :tx-count ...}`.

Queries with `:in` accept an EDN input vector:

```sh
vevdb query example.db \
  '[:find ?name :in $ ?active :where [?e :user/active ?active] [?e :user/name ?name]]' \
  '[true]'
```

The database value is supplied by the CLI and is not included in the input
vector.

## EDN files

Transaction, query, query-input, and pull-pattern arguments ending in `.edn`
are read from files.

```sh
vevdb transact example.db transactions.edn
vevdb query example.db query.edn
vevdb query example.db query.edn inputs.edn
vevdb pull example.db pull.edn 1
```

Store paths and entity IDs are not EDN arguments.

## Exit status

The CLI exits with a non-zero status when a store cannot be opened, a file
cannot be read, input is invalid, or an operation fails. A failed transaction
still prints its EDN transaction report.

## Legacy stores

`confirm-entity-partitions` marks a backed-up legacy store as using separate
entity and transaction ID ranges:

```sh
vevdb confirm-entity-partitions legacy.db
```

Use it only when upgrading a legacy store that asks for this confirmation.
