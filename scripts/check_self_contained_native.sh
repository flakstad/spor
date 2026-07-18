#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/check_self_contained_native.sh <binary-or-library>" >&2
  exit 1
fi

TARGET="$1"
if [[ ! -f "$TARGET" ]]; then
  echo "missing native artifact: $TARGET" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    dependencies="$(otool -L "$TARGET")"
    ;;
  Linux)
    dependencies="$(ldd "$TARGET")"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    dependencies="$(objdump -p "$TARGET" | grep 'DLL Name:' || true)"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

if grep -Eqi '(^|[/\\\\[:space:]])(lib)?sqlite3([.[:space:]]|$)' <<<"$dependencies"; then
  printf '%s\n' "$dependencies" >&2
  echo "$TARGET unexpectedly depends on a SQLite dynamic library" >&2
  exit 1
fi

echo ":vev-self-contained-native-ok"
