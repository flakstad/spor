#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/build/backup-fixture"
SOURCE="/tmp/vev-backup-fixture-source.sqlite"
SNAPSHOT="/tmp/vev-backup-fixture-snapshot.sqlite"

cleanup() {
  rm -f "$SOURCE" "$SOURCE-wal" "$SOURCE-shm"
  rm -f "$SNAPSHOT" "$SNAPSHOT-wal" "$SNAPSHOT-shm"
}
trap cleanup EXIT
cleanup

mkdir -p "$ROOT/build"
LIB_PATH=$("$ROOT/scripts/build_native_library.sh" --if-needed)
kvist build "$ROOT/src/vev_tests/backup_fixture.kvist" --out "$BIN" >/dev/null
VEV_LIB="$LIB_PATH" "$BIN" create "$SOURCE" "$SNAPSHOT"
VEV_LIB="$LIB_PATH" "$BIN" verify-snapshot "$SOURCE" "$SNAPSHOT"
VEV_LIB="$LIB_PATH" "$BIN" verify-source "$SOURCE" "$SNAPSHOT"
printf '%s\n' "backup separate-process snapshot: ok"
