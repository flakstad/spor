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
- `VEV_COMPARE_VEV_FIRST=1`: run Vev before the comparison engines
- `VEV_COMPARE_SKIP_BASELINES=1`: run only VevDB
- `VEV_BENCH_PEOPLE`: fixture size
- `VEV_BENCH_WARMUP_MS`: warmup duration
- `VEV_BENCH_MS`: measurement duration
- `VEV_BENCH_REPEATS`: repeat count
- `DATASCRIPT_VERSION`: DataScript release; default `1.7.8`
- `DATALEVIN_VERSION`: Datalevin release; default `0.10.7`
- `DATOMIC_VERSION`: Datomic Peer release; default `1.0.7705`

The comparison runner places a checked-in deterministic fixture generator
ahead of the upstream benchmark sources. All engines therefore receive the
same seeded values, insertion order, fixture size, warmup, measurement window,
and repeat count. Set the three version variables to the historical pins
`1.7.4`, `0.10.5`, and `1.0.7277` when reproducing the July 2026 snapshot.

The campaign runner reuses one immutable Vev fixture across query shapes; each
shape still runs its own warmup. This changes only untimed fixture construction
and avoids rebuilding the same 100,000 datoms seven times per process.

Compare only runs with the same fixture and timing settings.

For a campaign with five timed windows per query, raw output, median, and p95:

```sh
bench/run_comparative_benchmarks.py --track both
```

The runner's JSON output retains every engine's stdout, stderr, and individual
timed-window samples. Pass `--runs 5` for five full process repetitions; Vev's
position and the baseline order are then alternated between processes.
