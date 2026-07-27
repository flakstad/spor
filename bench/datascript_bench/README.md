# DataScript benchmark adapter

This adapter runs Datalevin's `datascript-bench` query shapes through VevDB's
Clojure API.

It requires JDK 25 or newer and Clojure CLI.

Workloads:

- `q1`: bound attribute/value lookup
- `q2`: lookup plus same-entity attribute
- `q2-switch`: `q2` with reversed clauses
- `q3`, `q4`: wider same-entity joins
- `q5`: shared-value join
- `qpred1`, `qpred2`: value predicates
- `rules-wide-*`, `rules-long-*`: recursive rules

Build the native library first:

```sh
scripts/build_native_library.sh
```

Run VevDB with small settings:

```sh
VEV_BENCH_PEOPLE=100 \
VEV_BENCH_WARMUP_MS=5 \
VEV_BENCH_MS=10 \
VEV_BENCH_REPEATS=1 \
  bench/datascript_bench/run_vev.sh
```

Compare with DataScript and Datalevin:

```sh
DATALEVIN_BENCH=/path/to/datalevin/benchmarks/datascript-bench \
  bench/datascript_bench/run_compare.sh
```

Pass workload names to limit the run:

```sh
bench/datascript_bench/run_compare.sh q1 q2 q2-switch
```

Useful variables:

- `DATALEVIN_BENCH`: upstream benchmark directory
- `VEV_COMPARE_BASELINES`: space-separated `datascript`, `datalevin`, or
  `datomic`
- `VEV_COMPARE_DATOMIC=1`: include Datomic
- `VEV_COMPARE_SKIP_BASELINES=1`: run only VevDB
- `VEV_BENCH_PEOPLE`: fixture size
- `VEV_BENCH_WARMUP_MS`: warmup duration
- `VEV_BENCH_MS`: measurement duration
- `VEV_BENCH_REPEATS`: repeat count

Compare only runs with the same fixture and timing settings.
