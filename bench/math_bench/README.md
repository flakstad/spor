# Math benchmark adapter

This adapter runs Datalevin's Mathematics Genealogy rule benchmark.

Workloads:

- `q1`: grand-advisors
- `q2`: shared university
- `q3`: different research area
- `q4`: recursive academic ancestry

Export the upstream dataset:

```sh
MATH_BENCH_JSON=/path/to/data.json.gz \
  bench/math_bench/run_export.sh
```

Run all workloads:

```sh
bench/math_bench/run_vev.sh
```

Run one:

```sh
bench/math_bench/run_vev.sh q4
```

Variables:

- `MATH_BENCH_BUILD`: generated data and binary directory
- `MATH_BENCH_WARMUPS`: warmup count
- `MATH_BENCH_SAMPLES`: sample count
- `KVIST_BIN`: Kvist executable
- `KVIST_ROOT`: Kvist checkout
- `KVIST_PACKAGES_DIR`: Kvist package directory

The harness checks expected row counts before reporting timings.
