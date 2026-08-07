#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

vev_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

vev_version() {
  local root="${1:-$(vev_repo_root)}"
  local version

  version="$(tr -d '[:space:]' < "$root/VERSION")"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid Vev version in $root/VERSION: $version" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

vev_cli_version() {
  local root="${1:-$(vev_repo_root)}"
  local version head tag_commit commit date

  version="$(vev_version "$root")" || return 1
  if ! head="$(git -C "$root" rev-parse --verify HEAD 2>/dev/null)"; then
    printf '%s\n' "$version"
    return
  fi

  tag_commit="$(git -C "$root" rev-parse --verify "refs/tags/v$version^{commit}" 2>/dev/null || true)"
  if [[ "$head" == "$tag_commit" ]]; then
    printf '%s\n' "$version"
    return
  fi

  commit="$(git -C "$root" rev-parse --short=8 HEAD)"
  date="$(git -C "$root" show -s --format=%cs HEAD)"
  printf '%s (%s %s)\n' "$version" "$commit" "$date"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  vev_version
fi
