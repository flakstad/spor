#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KVIST_BIN="${KVIST_BIN:-kvist}"
KVIST_WORKDIR="${KVIST_ROOT:-$REPO_ROOT}"
DATASCRIPT_ROOT="${DATASCRIPT_ROOT:-}"

if [[ -n "${KVIST_ROOT:-}" ]]; then
  export KVIST_PACKAGES_DIR="${KVIST_PACKAGES_DIR:-$KVIST_ROOT/packages}"
fi

if [[ -z "$DATASCRIPT_ROOT" ]]; then
  echo "DATASCRIPT_ROOT must point to a DataScript checkout" >&2
  exit 1
fi

VEV_OUT="$(mktemp)"
DS_OUT="$(mktemp)"
VEV_ERR="$(mktemp)"
DS_ERR="$(mktemp)"
trap 'rm -f "$VEV_OUT" "$DS_OUT" "$VEV_ERR" "$DS_ERR"' EXIT

if ! (
  cd "$KVIST_WORKDIR"
  "$KVIST_BIN" run "$REPO_ROOT/bench/query_rules.kvist"
) > "$VEV_OUT" 2> "$VEV_ERR"; then
  cat "$VEV_ERR" >&2
  exit 1
fi

if ! clojure \
  -Sdeps "{:deps {datascript/datascript {:local/root \"$DATASCRIPT_ROOT\"}}}" \
  -M "$REPO_ROOT/bench/datascript_query_rules.clj" > "$DS_OUT" 2> "$DS_ERR"; then
  cat "$DS_ERR" >&2
  exit 1
fi

awk '
function field_value(prefix,    i) {
  for (i = 1; i <= NF; i++) {
    if (index($i, prefix "=") == 1) {
      return substr($i, length(prefix) + 2)
    }
  }
  return ""
}

FNR == NR && /^engine=vev / {
  workload = field_value("workload")
  n = field_value("n")
  median = field_value("median_us") + 0
  vev[workload "|" n] = median
  next
}

FNR != NR && /^engine=datascript / {
  workload = field_value("workload")
  n = field_value("n")
  median = field_value("median_us") + 0
  ds_order[++ds_count] = workload "|" n
  ds_workload[ds_count] = workload
  ds_n[ds_count] = n
  ds_median[ds_count] = median
}

END {
  printf "%-24s %8s %14s %14s\n", "workload", "n", "vev_text", "vev_prepared"
  for (i = 1; i <= ds_count; i++) {
    workload = ds_workload[i]
    n = ds_n[i]
    ds_value = ds_median[i]
    text_key = workload "-text|" n
    prepared_key = workload "-prepared|" n
    text = "-"
    prepared = "-"
    if (text_key in vev && vev[text_key] > 0) {
      text = sprintf("%.1fx", ds_value / vev[text_key])
    }
    if (prepared_key in vev && vev[prepared_key] > 0) {
      prepared = sprintf("%.1fx", ds_value / vev[prepared_key])
    }
    printf "%-24s %8s %14s %14s\n", workload, n, text, prepared
  }
}
' "$VEV_OUT" "$DS_OUT"
