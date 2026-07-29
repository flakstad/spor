#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATALEVIN_BENCH="${DATALEVIN_BENCH:-/Users/andreas/Projects/datalevin/benchmarks/datascript-bench}"

if [[ ! -d "$DATALEVIN_BENCH" ]]; then
  echo "Datalevin datascript-bench not found: $DATALEVIN_BENCH" >&2
  exit 1
fi

queries=("$@")
if [[ ${#queries[@]} -eq 0 ]]; then
  queries=(q1 q2 q2-switch q3 q4 qpred1 qpred2)
fi

versions=()
if [[ -n "${VEV_COMPARE_BASELINES:-}" ]]; then
  # shellcheck disable=SC2206
  versions=(${VEV_COMPARE_BASELINES})
else
  versions=(datascript datalevin)
fi

if [[ "${VEV_COMPARE_DATOMIC:-0}" == "1" ]]; then
  versions=(datomic "${versions[@]}")
fi

if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
  if [[ "${VEV_COMPARE_USE_UPSTREAM_SCRIPT:-0}" == "1" ]]; then
    (
      cd "$DATALEVIN_BENCH"
      ./bench.clj "${versions[@]}" "${queries[@]}"
    )
    (
      cd "$ROOT"
      VEV_BENCH_ISOLATED_DBS="${VEV_BENCH_ISOLATED_DBS:-true}" \
        bench/datascript_bench/run_vev.sh "${queries[@]}"
    )
    exit 0
  fi
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_version() {
  local version="$1"
  local out="$tmp_dir/$version.out"
  echo "running $version: ${queries[*]}" >&2
  case "$version" in
    datascript)
      (
        cd "$ROOT"
        clojure -Srepro -Sdeps "{:paths [\"$DATALEVIN_BENCH/src-datascript\"] :deps {datascript/datascript {:mvn/version \"1.7.4\"}}}" \
          -M -m datascript-bench.datascript "${queries[@]}"
      ) >"$out"
      ;;
    datalevin)
      (
        cd "$ROOT"
        clojure -Srepro \
          -J--add-opens=java.base/java.nio=ALL-UNNAMED \
          -J--add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
          -Sdeps "{:paths [\"$ROOT/bench/datascript_bench/src\" \"$DATALEVIN_BENCH/src\"] :deps {datalevin/datalevin {:mvn/version \"0.10.5\"}}}" \
          -M -m vev-datascript-bench.datalevin-runner "${queries[@]}"
      ) >"$out"
      ;;
    datomic)
      (
        cd "$ROOT"
        clojure -Srepro -Sdeps "{:paths [\"$DATALEVIN_BENCH/src\" \"$DATALEVIN_BENCH/src-datomic\"] :deps {com.datomic/peer {:mvn/version \"1.0.7277\"}}}" \
          -M -m datalevin-bench.datomic "${queries[@]}"
      ) >"$out"
      ;;
    vev)
      (
        cd "$ROOT"
        VEV_BENCH_ISOLATED_DBS="${VEV_BENCH_ISOLATED_DBS:-true}" \
          bench/datascript_bench/run_vev.sh "${queries[@]}"
      ) >"$out"
      ;;
    *)
      echo "unsupported version: $version" >&2
      exit 1
      ;;
  esac
}

cell_for() {
  local version="$1"
  local column="$2"
  awk -v version="$version" -v column="$column" '
    BEGIN { FS = "[ \t]+" }
    NF == 0 { next }
    $1 == "version" { next }
    $1 == version {
      field = column + 1
      value = $field
      gsub(",", ".", value)
      print value
      found = 1
      exit
    }
    !fallback {
      field = column
      value = $field
      gsub(",", ".", value)
      fallback_value = value
      fallback = 1
    }
    END {
      if (!found && fallback) print fallback_value
      if (!found && !fallback) exit 1
    }
  ' "$tmp_dir/$version.out"
}

ratio() {
  local numerator="$1"
  local denominator="$2"
  awk -v n="$numerator" -v d="$denominator" 'BEGIN { if (d == "" || d == 0) print "---"; else printf "%.2fx", n / d }'
}

if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
  for version in "${versions[@]}"; do
    run_version "$version"
  done
fi

run_version vev

printf "query"
if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
  for version in "${versions[@]}"; do
    printf "\t%s" "$version"
  done
fi
printf "\tvev"
if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
  for version in "${versions[@]}"; do
    printf "\t%s/vev" "$version"
  done
fi
printf "\n"

for i in "${!queries[@]}"; do
  index=$((i + 1))
  vev_value="$(cell_for vev "$index")"
  printf "%s" "${queries[$i]}"
  if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
    for version in "${versions[@]}"; do
      printf "\t%s" "$(cell_for "$version" "$index")"
    done
  fi
  printf "\t%s" "$vev_value"
  if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
    for version in "${versions[@]}"; do
      baseline_value="$(cell_for "$version" "$index")"
      printf "\t%s" "$(ratio "$baseline_value" "$vev_value")"
    done
  fi
  printf "\n"
done

if [[ "${VEV_COMPARE_RAW:-0}" == "1" ]]; then
  printf "\nraw rows:\n"
  if [[ "${VEV_COMPARE_SKIP_BASELINES:-0}" != "1" ]]; then
    for version in "${versions[@]}"; do
      cat "$tmp_dir/$version.out"
    done
  fi
  cat "$tmp_dir/vev.out"
fi
