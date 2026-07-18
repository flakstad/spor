#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/version.sh"
VERSION="$(vev_version "$ROOT")"
ARCHIVE_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
OUT_DIR="$ROOT/build/release/cli"

case "$(uname -s)" in
  Darwin) OS="darwin"; EXE_NAME="vevdb"; FORMAT="tar.gz" ;;
  Linux) OS="linux"; EXE_NAME="vevdb"; FORMAT="tar.gz" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows"; EXE_NAME="vevdb.exe"; FORMAT="zip" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PLATFORM="$OS-$ARCH"
BINARY="$("$ROOT/scripts/build_cli.sh" --if-needed)"
ARCHIVE="$OUT_DIR/vevdb-cli-$PLATFORM-$VERSION.$FORMAT"

mkdir -p "$OUT_DIR"
rm -f "$ARCHIVE"

python3 - "$BINARY" "$ROOT/LICENSE" "$ARCHIVE" "$VERSION" "$ARCHIVE_DATE" "$FORMAT" "$EXE_NAME" <<'PY'
import datetime
import gzip
import io
import pathlib
import sys
import tarfile
import zipfile

binary_name, license_name, archive_name, version, date_text, archive_format, executable = sys.argv[1:]
binary = pathlib.Path(binary_name).read_bytes()
license_text = pathlib.Path(license_name).read_bytes()
archive = pathlib.Path(archive_name)
root = f"vevdb-{version}"
timestamp = int(datetime.datetime.fromisoformat(date_text).timestamp())

if archive_format == "tar.gz":
    with archive.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=timestamp) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as output:
                for name, data, mode in (
                    (f"{root}/bin/{executable}", binary, 0o755),
                    (f"{root}/LICENSE", license_text, 0o644),
                ):
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mode = mode
                    info.mtime = timestamp
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    output.addfile(info, io.BytesIO(data))
else:
    zip_date = datetime.datetime.fromtimestamp(timestamp).timetuple()[:6]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for name, data, mode in (
            (f"{root}/bin/{executable}", binary, 0o755),
            (f"{root}/LICENSE", license_text, 0o644),
        ):
            info = zipfile.ZipInfo(name, zip_date)
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(info, data)
PY

printf '%s\n' "$ARCHIVE"
