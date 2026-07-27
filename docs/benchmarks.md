# Benchmarks

The benchmark scripts compare local builds and check performance regressions.
They do not define published performance numbers.

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
