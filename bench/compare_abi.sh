#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KVIST_BIN="${KVIST_BIN:-kvist}"
KVIST_WORKDIR="${KVIST_ROOT:-$REPO_ROOT}"

if [[ -n "${KVIST_ROOT:-}" ]]; then
  export KVIST_PACKAGES_DIR="${KVIST_PACKAGES_DIR:-$KVIST_ROOT/packages}"
fi

KVIST_BIN="$KVIST_BIN" \
KVIST_REPO_DIR="${KVIST_ROOT:-}" \
"$REPO_ROOT/scripts/build_c_abi.sh" >/dev/null

mkdir -p "$REPO_ROOT/build/bench"
clang \
  -I"$REPO_ROOT/include" \
  "$REPO_ROOT/bench/c_abi.c" \
  -L"$REPO_ROOT/build/lib" \
  -lvev \
  -Wl,-rpath,"$REPO_ROOT/build/lib" \
  -o "$REPO_ROOT/build/bench/c_abi"

NATIVE_OUT="$(mktemp)"
C_OUT="$(mktemp)"
trap 'rm -f "$NATIVE_OUT" "$C_OUT"' EXIT

(
  cd "$KVIST_WORKDIR"
  "$KVIST_BIN" run "$REPO_ROOT/bench/abi_native.kvist"
) > "$NATIVE_OUT"

"$REPO_ROOT/build/bench/c_abi" > "$C_OUT"

cat "$NATIVE_OUT"
cat "$C_OUT"

awk '
function field_value(prefix,    i) {
  for (i = 1; i <= NF; i++) {
    if (index($i, prefix "=") == 1) {
      return substr($i, length(prefix) + 2)
    }
  }
  return ""
}

/^engine=vev-native / {
  workload = field_value("workload")
  native[workload] = field_value("median_us") + 0
}

/^engine=c-abi / {
  workload = field_value("workload")
  order[++count] = workload
  cabi[workload] = field_value("median_us") + 0
}

END {
  for (i = 1; i <= count; i++) {
    workload = order[i]
    if (native[workload] > 0 && cabi[workload] > 0) {
      printf "comparison workload=%s c_abi_over_native=%.2fx\n", workload, cabi[workload] / native[workload]
    }
  }
}
' "$NATIVE_OUT" "$C_OUT"
