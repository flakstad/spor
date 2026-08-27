# Small transaction comparison

This harness applies the same five logical transaction shapes to DataScript,
Datalevin, and Datomic:

- one new fact
- cardinality-one replacement
- explicit retraction
- `retractEntity`
- one replacement plus three facts on the current transaction entity

Vev uses the native resident durable benchmark in
`bench/resident_small_transactions.kvist`. The Clojure reference runner uses
DataScript and Datomic Peer in memory, while Datalevin uses synchronous WAL
with its strict durability profile. The result's `storage` field is therefore
part of every comparison; in-memory and durable numbers must not be presented
as equivalent storage guarantees.

Run the complete matrix and retain raw output as JSON:

```sh
bench/run_transaction_comparison.py
```

Or run one Clojure engine directly:

```sh
bench/transaction_comparison/run_engine.sh datalevin --samples 40
```

The defaults pin DataScript 1.7.8, Datalevin 0.10.7, and Datomic Peer
1.0.7705. Override their corresponding `*_VERSION` environment variables to
reproduce another release. A `VEV_BENCH_DATOMIC_URI_PREFIX` can point the
Datomic adapter at a running transactor; without it, Datomic uses `datomic:mem`.
The aggregate runner accepts the same value as `--datomic-uri-prefix` and then
records both Datomic in-memory and durable rows.
