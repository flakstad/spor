#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/smoke_c_package.sh"
"$ROOT/scripts/smoke_jvm_package.sh"
"$ROOT/scripts/smoke_python_package.sh"
"$ROOT/scripts/smoke_node_package.sh"
"$ROOT/scripts/smoke_go_package.sh"
"$ROOT/scripts/smoke_rust_package.sh"
"$ROOT/scripts/smoke_odin_package.sh"
"$ROOT/scripts/smoke_kvist_package.sh"
