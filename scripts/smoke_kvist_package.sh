#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE="$ROOT/build/release/source/vev-kvist-$VERSION.tar.gz"

if ! command -v kvist >/dev/null 2>&1; then
  echo "kvist not found; skipping Kvist package smoke"
  exit 0
fi

if [[ ! -f "$ARCHIVE" ]]; then
  "$ROOT/scripts/package_source_archives.sh" >/dev/null
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-kvist-package.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
PACKAGE_ROOT="$TMP_DIR/vev-kvist-$VERSION"
SQLITE_LIB_DIR="${VEV_SQLITE_LIB_DIR:-$("$ROOT/scripts/build_sqlite.sh")}"

cat > "$PACKAGE_ROOT/smoke.kvist" <<'EOF'
(package main)

(import d "./src/vev_app")
(import kdata "kvist:data")

(defn main []
  (let [conn (d.create-conn)
        _ (d.transact conn '[{:db/id 1 :user/name "Ada"}])
        db (d.db conn)
        names (d.q '[:find ?name :where [?e :user/name ?name]] db)]
    (when (not (= (kdata.count names) 1))
      (panic "unexpected packaged Kvist query result"))))
EOF

(
  cd "$PACKAGE_ROOT"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      BINARY="$PACKAGE_ROOT/smoke.exe"
      WINDOWS_GENERATED="$(cygpath -m "$PACKAGE_ROOT/smoke.odin")"
      WINDOWS_BINARY="$(cygpath -m "$BINARY")"
      WINDOWS_SQLITE_LIB_DIR="$(cygpath -w "$SQLITE_LIB_DIR")"
      ;;
    *)
      BINARY="$PACKAGE_ROOT/smoke"
      ;;
  esac
  kvist compile smoke.kvist -o "$PACKAGE_ROOT/smoke.odin" >/dev/null
  if [[ -n "${WINDOWS_GENERATED:-}" ]]; then
    COLLECTION_ARGS=()
    while IFS= read -r drive; do
      COLLECTION_ARGS+=("-collection:$drive=$drive:/")
    done < <(
      sed -nE 's/^import .*"([A-Za-z]):[\\/].*/\1/p' "$PACKAGE_ROOT/smoke.odin" |
        tr '[:lower:]' '[:upper:]' |
        sort -u
    )
    if (( ${#COLLECTION_ARGS[@]} == 0 )); then
      echo "generated Kvist package has no Windows import collections" >&2
      exit 1
    fi
      MSYS2_ARG_CONV_EXCL="*" odin build "$WINDOWS_GENERATED" -file \
      "${COLLECTION_ARGS[@]}" \
      "-extra-linker-flags:/LIBPATH:$WINDOWS_SQLITE_LIB_DIR" \
      -out:"$WINDOWS_BINARY"
  else
    odin build "$PACKAGE_ROOT/smoke.odin" -file \
      "-extra-linker-flags:-L$SQLITE_LIB_DIR" \
      -out:"$BINARY"
  fi
  if ! "$BINARY"; then
    if command -v objdump >/dev/null 2>&1; then
      objdump -p "$BINARY" | grep "DLL Name" >&2 || true
    fi
    echo "packaged Kvist executable failed" >&2
    exit 1
  fi
)

echo ":vev-kvist-package-ok"
