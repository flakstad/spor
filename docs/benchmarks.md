# Benchmarks

The benchmark scripts compare local builds and check performance regressions.
They do not define published performance numbers.

See the [2026-08-27 benchmark snapshot](../bench/results/2026-08-27.md) for
the latest dated local results.

## C ABI overhead

Compare native Kvist calls with matching C ABI calls:

```sh
KVIST_ROOT=/path/to/kvist \
KVIST_BIN=/path/to/kvist-bin \
KVIST_PACKAGES_DIR=/path/to/kvist/packages \
  bench/compare_abi.sh
```

## DataScript read queries

The DataScript adapter runs the same query shapes through DataScript,
Datalevin, and VevDB's in-tree Clojure wrapper.

It requires JDK 25, Clojure CLI, and a Datalevin checkout:

```sh
scripts/build_native_library.sh

DATALEVIN_BENCH=/path/to/datalevin/benchmarks/datascript-bench \
  bench/datascript_bench/run_compare.sh
```

Pass query names to run a subset:

```sh
DATALEVIN_BENCH=/path/to/datalevin/benchmarks/datascript-bench \
  bench/datascript_bench/run_compare.sh q1 q2 q2-switch
```

See [DataScript benchmark adapter](../bench/datascript_bench/README.md) for
workloads and timing options.

## Transactions

Build `bench/write_bench.kvist` for native in-memory and durable Vev writes.
The matching Datomic adapter targets either an in-memory database or a local
dev transactor:

```sh
bench/write_bench/run_datomic.sh \
  --uri datomic:mem://vev-write-bench \
  --batch 100 \
  --total 10000
```

### Small resident durable transactions

`resident_small_transactions.kvist` measures one durable commit at a time on
one long-lived resident connection. It covers a new fact, cardinality-one
replacement, explicit retract, `retractEntity`, and a Ro-shaped replacement
with three transaction-provenance facts. Every shape runs from the same seed on
both a 50-entity and a 2,000-entity database.

```sh
python3 bench/check_resident_small_transactions.py --mode both --samples 40
```

The output includes median/p95, effective `tx-data` datoms, phase time and phase
percentages. `--mode full` forces the reference full-`build-db` path; the
default `incremental` mode uses production selection. The checked-in budget is
for incremental mode and intentionally leaves headroom for CI variance.

See [resident transaction performance](resident-transaction-performance.md)
for the architecture, invariants, and a same-machine before/after profile.

### Public Kvist/native transaction boundary

`kvist_transaction_boundary.kvist` measures the actual public Kvist package,
the retained EDN compatibility path, native engine phases, report ownership,
exact DB retains, and structured report materialization:

```sh
python3 bench/check_kvist_transaction_boundary.py --samples 100
```

The checked budget conservatively sums phase p95 values and limits the
large/Ro-like overhead outside ordinary engine work to 1 ms. The benchmark can
also run the exact Ro transaction against two disposable Ro demo databases.
See [Kvist/native transaction boundary](kvist-native-transaction-boundary.md)
for commands, measurements, API rationale, and ownership rules.

The same executable includes `small`, `large`, `wide-schema`, and
`schema-churn` databases and `append`, `replacement`, `cas`,
`explicit-retract`, `retract-entity`, and `ro-like` workloads. Its profile
output includes detailed resolution/planning times, operation counts, and
effective transaction datoms. Exact Ro diagnostics select
`--ro-workload ro-demo`, `ro-demo-no-provenance`, or
`ro-demo-resolved-ids` against independent disposable database copies.

Registered transaction-function expansion has a deterministic source-backed
durable row:

```sh
kvist build bench/durable_transaction_function.kvist \
  --out build/bench/durable-transaction-function
build/bench/durable-transaction-function --samples 100 --warmup 20
```

See [resident transaction resolution and
planning](transaction-resolution-planning-profile.md) for the root cause,
scaling matrix, reference-planner differential, and current budgets.

## Durable storage amplification

The deterministic storage benchmark writes 1,000 application assertions using
five transaction shapes. Its default `committed` mode performs one real SQLite
commit for every logical transaction. It checkpoints the WAL before measuring
the SQLite file, reports file/live/freelist bytes, checkpoint and novelty
bases, every durable index artifact, `dbstat` object sizes, and transaction,
open, and query latency:

```sh
python3 bench/storage_amplification.py --build
```

Pass `--output-dir` to retain the databases for inspection, `--json-output`
to save the measurements, and `--budgets` to enforce a checked-in or local
JSON budget. A shape such as `--shape 1000x1` means 1,000 logical
transactions containing one assertion each. Every transaction also records
the normal `:db/txInstant` datom.

`--mode logical` exercises the atomic multi-transaction API instead. That mode
is useful for its distinct all-or-nothing contract, but it is not a substitute
for measuring visibility and durability after every small commit.

The checked-in regression budget covers file bytes per datom, incremental
bytes per logical transaction, derived row counts, and process-level open,
query, and transaction latency:

```sh
python3 bench/storage_amplification.py --build \
  --budgets bench/storage_amplification_budget.json
```

Latency limits are deliberately broad enough for CI machines; dated result
files remain the useful same-machine comparison.

## Recursive rules

Compare VevDB with a local DataScript checkout:

```sh
KVIST_ROOT=/path/to/kvist \
KVIST_BIN=/path/to/kvist-bin \
KVIST_PACKAGES_DIR=/path/to/kvist/packages \
DATASCRIPT_ROOT=/path/to/datascript \
  bench/compare_query_rules.sh
```

Use `bench/compare_query_rules_stress.sh` for the larger cases.

## Math genealogy

Export Datalevin's math benchmark data, then run the four rule workloads:

```sh
MATH_BENCH_JSON=/path/to/data.json.gz \
  bench/math_bench/run_export.sh

KVIST_ROOT=/path/to/kvist \
KVIST_BIN=/path/to/kvist-bin \
KVIST_PACKAGES_DIR=/path/to/kvist/packages \
  bench/math_bench/run_vev.sh
```

See [Math benchmark adapter](../bench/math_bench/README.md).

## MusicBrainz

MusicBrainz benchmarks use the durable store created by the
[MusicBrainz validation](musicbrainz.md) workflow:

```sh
scripts/musicbrainz_clojure_vev_matrix.sh --help
scripts/compare_musicbrainz_workshop.sh --help
```

To check the restored durable performance and result fingerprints on the
reference machine:

```sh
scripts/compare_musicbrainz_workshop.sh \
  --engine vev \
  --skip-kvist \
  --prepared-vev \
  --warmup-runs 10 \
  --measure-runs 25 \
  --budget-file bench/musicbrainz_durable_budget.edn
```

The checked-in budget is a same-machine regression guard, not a portable CI
limit. It validates the benchmark settings, row counts, fingerprints, and
median workload times.
