#!/usr/bin/env python3
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

import argparse
import hashlib
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Record cross-platform JVM artifacts in a combined release manifest."
    )
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--jvm-dir", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    manifest = json.loads(args.manifest.read_text())
    version = manifest["version"]
    definitions = (
        ("vev-java", "jvm-jar", f"vev-java-{version}.jar"),
        ("vev-java-pom", "maven-pom", f"vev-java-{version}.pom"),
        ("vev-clj", "clojure-jar", f"vev-clj-{version}.jar"),
        ("vev-clj-pom", "maven-pom", f"vev-clj-{version}.pom"),
    )

    names = {name for name, _, _ in definitions}
    artifacts = [
        artifact
        for artifact in manifest["artifacts"]
        if artifact["name"] not in names
    ]
    for name, kind, filename in definitions:
        path = args.jvm_dir / filename
        if not path.is_file():
            raise SystemExit(f"missing combined JVM artifact: {path}")
        artifacts.append(
            {
                "name": name,
                "kind": kind,
                "path": f"jvm/{filename}",
                "exists": True,
                "sha256": sha256(path),
            }
        )

    manifest["artifacts"] = sorted(artifacts, key=lambda artifact: artifact["name"])
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    print(args.manifest)


if __name__ == "__main__":
    main()
