# Kvist/native transaction boundary

> Follow-up (2026-08-27): transaction resolution/planning has since been
> optimized. The final checked exact public Ro transaction now measures
> 2.104 ms median / 3.726 ms p95 on fresh disposable databases, with 0.160 ms
> resolution and 0.467 ms planning. See [resident transaction resolution and
> planning](transaction-resolution-planning-profile.md). The measurements below
> remain the `b0f2700d`/`87a948c9` boundary and pre-optimization baseline.

This report measures the complete public Kvist `Data` → native durable VevDB
→ Kvist `Tx-Report` path at commit `b0f2700d`. The initial hypothesis was that
EDN conversion explained 6–7 ms of a 8.7–9.8 ms Ro transaction. It does not:
the exact warm Ro transaction spends almost all of that time in VevDB
resolution and planning. The measured public-boundary overhead is below the
1 ms goal before this change and is now guarded by a concrete budget.

## Method

Measurements were made on 2026-08-27 on an Apple M1 Pro with 16 GiB RAM,
Darwin 24.5.0, the bundled SQLite build, and Odin
`dev-2026-05:ea5175d86`. Each ordinary matrix row has 100 warm transactions.
The exact Ro run uses two independently seeded disposable copies of Ro's demo
database and the transaction issued by `set-semantic-checkbox!`, including
the actor, source, and cause provenance datoms.

The benchmark has three passes:

1. The actual public Kvist `transact-data` call.
2. A manually split compatibility path measuring `edn.write`, native call,
   exact DB retains, report EDN rendering, and Kvist `edn.read`.
3. An opt-in native profile for parsing, resolution, validation, planning,
   `db-after`, report ownership, append, derived bookkeeping, and commit.

Profiling is disabled for the public and manual totals. The phase clocks add
observable overhead, so the profiled engine total must not be subtracted from
an unprofiled public total. Phase values come from an equivalent separate pass
and need not sum exactly to the unprofiled total.

## Public totals

The small and large synthetic stores contain 50 and 2,000 entities
respectively. The Ro-like shape is a cardinality-one replacement plus three
transaction-provenance assertions and produces about six effective datoms.

| database/workload | public median | public p95 | old EDN median | old EDN share |
| --- | ---: | ---: | ---: | ---: |
| small/append | 0.425 ms | 0.581 ms | 0.054 ms | 12.2% |
| small/replacement | 0.590 ms | 0.807 ms | 0.065 ms | 10.5% |
| small/explicit retract | 0.498 ms | 0.759 ms | 0.058 ms | 11.7% |
| small/Ro-like | 1.037 ms | 1.322 ms | 0.130 ms | 11.7% |
| large/append | 0.772 ms | 1.049 ms | 0.054 ms | 6.9% |
| large/replacement | 1.983 ms | 2.176 ms | 0.062 ms | 3.1% |
| large/explicit retract | 1.845 ms | 2.363 ms | 0.054 ms | 2.9% |
| large/Ro-like | 2.555 ms | 2.829 ms | 0.124 ms | 4.8% |
| exact Ro demo/Ro transaction | 9.014 ms | 9.763 ms | 0.165 ms | 1.8% |

“Old EDN” is the sum of Kvist transaction rendering, VevDB transaction
parsing, native report rendering, and Kvist report parsing. It deliberately
includes parsing inside the engine to give EDN the largest defensible share.

## Exact Ro phase profile

| phase | median | p95 |
| --- | ---: | ---: |
| public `transact-data` | 9.014 ms | 9.763 ms |
| compatibility manual total | 9.107 ms | 9.908 ms |
| unprofiled native call | 8.980 ms | 9.786 ms |
| Kvist transaction `edn.write` | 0.006 ms | 0.007 ms |
| ABI input copy | 0.001 ms | 0.001 ms |
| VevDB EDN parse | 0.044 ms | 0.053 ms |
| resolution | 1.785 ms | 2.020 ms |
| validation | 0.004 ms | 0.005 ms |
| planning | 6.004 ms | 7.353 ms |
| `db-after` | 1.221 ms | 1.347 ms |
| core report construction/ownership | 0.028 ms | 0.033 ms |
| canonical append | 0.233 ms | 0.282 ms |
| derived bookkeeping | 0.006 ms | 0.010 ms |
| SQLite commit | 0.151 ms | 0.309 ms |
| native report handle construction | 0.018 ms | 0.024 ms |
| listener dispatch | 0.017 ms | 0.021 ms |
| native cleanup | 0.002 ms | 0.002 ms |
| retain `db-before` | 0.002 ms | 0.003 ms |
| retain `db-after` | 0.001 ms | 0.002 ms |
| native report → EDN | 0.058 ms | 0.064 ms |
| Kvist report `edn.read` | 0.057 ms | 0.065 ms |
| native report Value → Kvist `Data` | 0.062 ms | 0.072 ms |

The earlier 2.7–3.2 ms internal result used a much simpler schema and
transaction representation. On the actual Ro schema, resolution and planning
alone account for about 7.8 ms median. The public/native difference is about
0.13 ms on the manually split path, not 6–7 ms.

## API decision

The public Kvist API remains `transact`, `transact-data`, `with`, and
`with-data`, returning the same rich `Tx-Report`. The implementation now reads
the existing structured `vev_tx_report_value` tree instead of calling
`vev_tx_report_edn` and reparsing its text. The EDN report and transaction
entry points remain public compatibility APIs.

No field is removed, delayed, or replaced by an acknowledgement. `:ok`,
`:error`, `:vev/error`, `:tx`, `:tx-data`, `:tempids`, and `:tx-meta` are
materialized before return. `db-before` and `db-after` still come directly
from the native report rather than by rereading the connection.

The alternative APIs were evaluated as follows:

- A field-oriented report ABI would duplicate Value-map traversal, enlarge the
  stable C surface, and save less than the measured 0.062 ms materialization.
- A general transaction Value/builder ABI is the right shape if input parsing
  later becomes material: an opaque caller-owned Value tree borrowed for a
  `transact-value-report`/`with-value-report` call. It should serve queries and
  reports too and must not expose VevDB structs. The current input render plus
  parse costs only 0.050 ms median on the exact Ro case, so implementing that
  ownership surface now is not justified.
- An opaque transaction-only handle would make the C API less general and the
  Odin/Kvist APIs less idiomatic than a common Value tree.
- Acknowledgement-only and Ro-specific entry points were rejected because they
  violate the required ordinary rich-report contract.

For VevDB/Datomic users this retains one report shape for `with` and
`transact`. Odin continues to expose the tagged native `Value` API. Kvist gets
fresh local `Data` with its existing close discipline. C keeps opaque handles
and no VevDB internal struct crosses the ABI.

## Ownership and lifetime

- `vev_tx_report_t` owns its immutable report Value tree.
- `vev_tx_report_value(report)` and every child returned from it are borrowed,
  read-only views. They are valid until `vev_tx_report_free(report)` and must
  not be freed separately.
- Kvist recursively materializes a fresh `Data` tree while the report is live.
  Its `internal-owner-data` owns that tree and therefore keeps `tx-data`,
  `tempids`, and `tx-meta` projections valid until `d.close(&report)`.
- `vev_tx_report_db_before` and `vev_tx_report_db_after` return independent
  retained immutable DB handles. Each must be released once. They keep the
  exact acknowledged bases even if another connection or process commits.
- A Value returned by `vev_connection_tx_profile_value` is a caller-owned
  handle and is released with `vev_value_handle_free`.
- There is no shared mutable serialization buffer.

The compatibility materializer intentionally preserves the prior EDN `Data`
shape for native entities and floats: `[:vev/entity id]` and
`[:vev/float text]`, including NaN and both infinities. UUIDs and instants keep
their tagged-literal forms.

## Compatibility, gain, and risk

`vev_tx_report_edn` is unchanged. `vev_tx_report_value` already existed, so
the report optimization adds no data-path ABI. The three transaction-profile
functions are additive diagnostics; old clients ignore them, and the Odin
wrapper treats them as optional.

Direct report output falls from 0.115 ms median for render plus parse to
0.062 ms for structured materialization in the exact Ro case, a 0.053 ms
gain. The full public median in the paired disposable-database run is 9.014 ms
versus 9.107 ms for the compatibility path. Absolute engine work, especially
Ro-schema planning, remains the useful next optimization target.

The regression budget conservatively sums every boundary phase's p95 rather
than subtracting separately sampled totals. It is 0.185 ms for the exact Ro
case and 0.137 ms for large/Ro-like, against a checked 1.000 ms limit.

The main semantic risk was treating native typed entities/floats like ordinary
query results. Same-report differential tests exposed that mismatch during
development. The final tests compare the structured and EDN views of the same
native handle for success, failure, `with`, entity markers, floats, tx data,
tempids, and tx metadata. Existing retained-snapshot, multiwriter,
cross-process, history, backup, migration, transaction-function, provenance,
CAS, retract, schema-reference, reopen, memory-tracking, and PBT suites remain
the wider invariants.

## Reproduction

Run the deterministic public matrix and its boundary budget:

```sh
python3 bench/check_kvist_transaction_boundary.py --samples 100
```

Ro can run the same executable through VevDB's actual public Kvist package.
Use disposable database copies because the benchmark commits transactions:

```sh
RO=/path/to/ro-next/build/ro
VEV_LIB="$PWD/build/lib/libvev.dylib"

"$RO" demo --db build/bench/ro-public.vev
"$RO" demo --db build/bench/ro-native.vev

python3 bench/check_kvist_transaction_boundary.py \
  --no-build --ro-only --samples 100 \
  --ro-public-db build/bench/ro-public.vev \
  --ro-native-db build/bench/ro-native.vev
```

The public and native paths must differ so both runs start from independently
owned, equivalent stores.
