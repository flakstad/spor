# CLI

The `vevdb` CLI is VevDB's data-oriented process frontend. It reads and writes
durable SQLite-backed stores, and it can compose immutable database values in a
single invocation. SQLite is included in the executable.

Download a CLI archive from a
[VevDB release](https://github.com/vevdb/vev/releases), unpack it, and put its
`bin/vevdb` on `PATH`.

## Command reference

```text
vevdb --version
vevdb info <store>
vevdb sync <store> [target-t]
vevdb db-info <store> [--db <pipeline>]
vevdb index-info <store> [index]

vevdb transact <store> <transaction>
vevdb transact-many <store> <transactions> --mode committed|logical|flatten
vevdb with <store> <transaction> [--db <pipeline>]

vevdb query <store> <query> [inputs] [--rules <rules>]
  [--db <pipeline>] [--result envelope|q|rows|scalar]
  [--profile] [--timeout <milliseconds>]
vevdb pull <store> <pattern> <entity> [--db <pipeline>]
vevdb pull-many <store> <pattern> <entities> [--db <pipeline>]
vevdb index-pull <store> <options> [--db <pipeline>]

vevdb entity <store> <entity> [--db <pipeline>]
vevdb entity-get <store> <entity> <attribute> [--db <pipeline>]
vevdb entity-contains <store> <entity> <attribute> [--db <pipeline>]
vevdb entid <store> <entity> [--db <pipeline>]
vevdb ident <store> <entity> [--db <pipeline>]
vevdb attribute <store> <attribute> [--db <pipeline>]

vevdb datoms <store> <index> [components] [--db <pipeline>]
vevdb seek-datoms <store> <index> [components] [--db <pipeline>]
vevdb rseek-datoms <store> <index> [components] [--db <pipeline>]
vevdb index-range <store> <attribute> <start> <end> [--db <pipeline>]
vevdb tx-range <store> [start [end]]

vevdb ensure-resident <store>
vevdb compact-indexes <store>
vevdb reclaim-indexes <store>
vevdb maintain-indexes <store> [--max-steps <n>]

vevdb t-to-tx <t>
vevdb tx-to-t <tx>
vevdb squuid
vevdb squuid-time-millis <uuid>

vevdb watch <store> [--after <time-point>]
vevdb exec <store> <request>
vevdb exec --memory <request>
vevdb confirm-entity-partitions <store>
```

Use `vevdb <command> --help` for the installed command synopsis. Store paths
may be relative or absolute and do not require a file extension.

## EDN arguments and output

Transactions, queries, inputs, rules, pull patterns, entity selectors, index
components, time points, DB pipelines, and exec requests are EDN. Each such
argument accepts inline EDN, `@path`, `-` for standard input, or the legacy
`*.edn` file convention. At most one argument may consume standard input.

```sh
vevdb transact example.db '[{:db/id 1 :user/name "Ada"}]'
vevdb query example.db @query.edn @inputs.edn --result q
printf '%s\n' '[:user/name]' | vevdb pull example.db - 1
```

A successful non-streaming command prints exactly one EDN value. Datoms use
the portable vector form `[entity attribute value transaction added?]`.
Diagnostics are written as one EDN map to standard error. A rejected
`transact` or `with` prints its transaction report to standard output and exits
nonzero.

## Immutable database pipelines

Every read command accepts an ordered `--db` pipeline. It changes only the DB
value used by the invocation; it never changes the durable store.

```sh
vevdb query example.db \
  '[:find ?name :where [?e :user/name ?name]]' \
  --result q \
  --db '[[:as-of 10]
         [:with [{:db/id 7 :user/name "Hypothetical"}]]]'

vevdb datoms example.db :eavt '[]' --db '[[:history]]'
```

Pipeline operations are `[:as-of point]`, `[:since point]`, `[:history]`, and
`[:with transaction]`. Time points may be a basis `t`, transaction entity ID,
or `#inst` value.

Entity arguments accept numeric IDs, idents, and lookup refs such as
`[:person/email "ada@example.com"]`.

## Query results

`query` defaults to the legacy envelope. `--result q` preserves the query find
shape, `rows` always returns row vectors, and `scalar` returns the first scalar
value or `nil`. `--profile` wraps the selected result as
`{:ret ... :query-stats ...}`. `--timeout` enforces the frontend's elapsed-time
timeout after native evaluation; it does not interrupt native execution.

## Compositional execution

`exec` keeps native DBs, reports, and prepared query or pull values alive for
an ordered plan. References point to earlier steps and may traverse report
data or select `:db-before` and `:db-after`.

```sh
vevdb exec example.db \
  '{:steps [{:id :current :op :db}
            {:id :hyp :op :with
             :db [:ref :current]
             :tx [{:db/id 7 :task/status :done}]}
            {:id :answer :op :query
             :db [:ref :hyp :db-after]
             :query [:find ?status .
                     :where [7 :task/status ?status]]}]
    :return {:answer [:ref :answer]
             :tx [:ref :hyp :tx]}}'
```

Exec also supports `:empty-db`, `:init-db`, `:as-of`, `:since`, `:history`,
`:db-with`, prepared queries and pull patterns, named DB query sources, DB
metadata, entity and index reads, pulls, transactions, transaction ranges, and
coordinate/UUID utilities. A failed step is fail-fast unless it has
`:on-error :capture`. `exec --memory` starts without a durable store.

Query, rule, and pull forms may be EDN values. Use an EDN string for a form
that contains lists, because the exec request's portable value model does not
itself represent EDN list nodes. Relation database rows can be supplied through
`:inputs`, including named source inputs such as `$rows`.

## Transaction stream

`watch` prints one compact EDN transaction report per line. With no `--after`,
it starts after the basis captured at startup. With `--after`, it emits every
transaction strictly after that time point and then continues polling until
interrupted.

## Committed, logical, and flattened bulk writes

`transact-many --mode committed` commits each input group independently and is
the right mode for durability/storage-amplification measurements. A later
failure does not roll back earlier committed groups. `--mode logical` keeps one
transaction/report per input group while using one all-or-nothing durable
commit. `--mode flatten` combines all groups into one logical transaction.

## Legacy stores

`confirm-entity-partitions` marks a backed-up legacy store as using separate
entity and transaction ID ranges. Use it only when upgrading a legacy store
that explicitly asks for this confirmation.
