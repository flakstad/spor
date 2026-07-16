#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream"

fetch() {
  local name="$1"
  local url="$2"
  local revision="$3"
  local target="$UPSTREAM/$name"

  if [[ ! -d "$target/.git" ]]; then
    if [[ -e "$target" ]]; then
      echo "upstream target exists but is not a git checkout: $target" >&2
      exit 1
    fi
    git clone --filter=blob:none --no-checkout "$url" "$target"
  fi

  git -C "$target" fetch --depth 1 origin "$revision"
  git -C "$target" checkout --detach FETCH_HEAD >/dev/null

  if [[ "$(git -C "$target" rev-parse HEAD)" != "$revision" ]]; then
    echo "failed to resolve pinned $name revision $revision" >&2
    exit 1
  fi
}

mkdir -p "$UPSTREAM"
fetch mbrainz-sample https://github.com/Datomic/mbrainz-sample.git a7c0aab6828cfa09d5ff3c6075579673377b4a43
fetch day-of-datomic https://github.com/Datomic/day-of-datomic.git daa457f766e16f55243a95513e759573b8827329
fetch day-of-datomic-conj https://github.com/Datomic/day-of-datomic-conj.git cf1e260cff0aa582fe2ae17bb1fcfaeebb139f80

echo "Workshop sources ready under $UPSTREAM"
