#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/check_release_environment.sh" >/dev/null
"$ROOT/scripts/build_native_library.sh"
"$ROOT/scripts/package_native_bundle.sh" >/dev/null
"$ROOT/scripts/smoke_native_bundle.sh" >/dev/null
"$ROOT/scripts/package_source_archives.sh" >/dev/null
"$ROOT/scripts/package_jvm.sh" >/dev/null
"$ROOT/scripts/verify_jvm_reproducibility.sh" >/dev/null
"$ROOT/scripts/smoke_packages.sh"
"$ROOT/scripts/release_manifest.sh"
