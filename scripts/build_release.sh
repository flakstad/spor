#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

release_step() {
  local name="$1"
  shift
  echo "release-stage=$name" >&2
  "$@"
}

release_step environment "$ROOT/scripts/check_release_environment.sh" >/dev/null
release_step native-library "$ROOT/scripts/build_native_library.sh"
release_step native-bundle "$ROOT/scripts/package_native_bundle.sh" >/dev/null
release_step native-bundle-smoke "$ROOT/scripts/smoke_native_bundle.sh" >/dev/null
release_step source-archives "$ROOT/scripts/package_source_archives.sh" >/dev/null
release_step jvm-packages "$ROOT/scripts/package_jvm.sh" >/dev/null
release_step jvm-reproducibility "$ROOT/scripts/verify_jvm_reproducibility.sh" >/dev/null
release_step package-smokes "$ROOT/scripts/smoke_packages.sh"
release_step manifest "$ROOT/scripts/release_manifest.sh"
