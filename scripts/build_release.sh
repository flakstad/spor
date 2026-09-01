#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) NATIVE_LIBRARY="libvev.dylib" ;;
  Linux) NATIVE_LIBRARY="libvev.so" ;;
  MINGW*|MSYS*|CYGWIN*) NATIVE_LIBRARY="vev.dll" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

release_step() {
  local name="$1"
  shift
  echo "release-stage=$name" >&2
  "$@"
}

release_step environment "$ROOT/scripts/check_release_environment.sh" >/dev/null
release_step cli-api-manifest "$ROOT/scripts/check_cli_api_manifest.sh" >/dev/null
release_step native-library "$ROOT/scripts/build_native_library.sh"
release_step native-self-contained "$ROOT/scripts/check_self_contained_native.sh" "$ROOT/build/lib/$NATIVE_LIBRARY" >/dev/null
release_step sqlite-c-applications "$ROOT/scripts/test_sqlite_applications_c.sh"
release_step sqlite-kvist-applications "$ROOT/scripts/test_sqlite_applications_kvist.sh"
release_step sqlite-clojure-applications "$ROOT/scripts/test_sqlite_applications_clojure.sh"
release_step cli "$ROOT/scripts/package_cli.sh" >/dev/null
release_step cli-smoke "$ROOT/scripts/smoke_cli_package.sh" >/dev/null
release_step cli-parity "$ROOT/scripts/test_cli_parity.sh" >/dev/null
release_step native-bundle "$ROOT/scripts/package_native_bundle.sh" >/dev/null
release_step native-bundle-smoke "$ROOT/scripts/smoke_native_bundle.sh" >/dev/null
release_step odin-bundle "$ROOT/scripts/package_odin_bundle.sh" >/dev/null
release_step odin-bundle-smoke "$ROOT/scripts/smoke_odin_bundle.sh" >/dev/null
release_step kvist-bundle "$ROOT/scripts/package_kvist_bundle.sh" >/dev/null
release_step kvist-bundle-smoke "$ROOT/scripts/smoke_kvist_bundle.sh" >/dev/null
release_step source-archives "$ROOT/scripts/package_source_archives.sh" >/dev/null
release_step jvm-packages "$ROOT/scripts/package_jvm.sh" >/dev/null
release_step jvm-reproducibility "$ROOT/scripts/verify_jvm_reproducibility.sh" >/dev/null
release_step package-smokes "$ROOT/scripts/smoke_packages.sh"
release_step manifest "$ROOT/scripts/release_manifest.sh"
