#!/usr/bin/env python3
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Combine verified platform release manifests."
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("manifests", nargs="+", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifests = [json.loads(path.read_text()) for path in args.manifests]
    first = manifests[0]
    version = first["version"]
    git_commit = first["git_commit"]
    platforms: list[str] = []
    artifacts: dict[str, dict] = {}

    for manifest in manifests:
        if manifest["version"] != version:
            raise SystemExit("cannot combine manifests with different versions")
        if manifest["git_commit"] != git_commit:
            raise SystemExit("cannot combine manifests from different commits")

        platform = manifest["platform"]
        if platform in platforms:
            raise SystemExit(f"duplicate release platform: {platform}")
        platforms.append(platform)

        for artifact in manifest["artifacts"]:
            name = artifact["name"]
            previous = artifacts.get(name)
            if previous is not None:
                if previous["sha256"] != artifact["sha256"]:
                    raise SystemExit(
                        f"platform-independent artifact differs: {name}"
                    )
                continue
            entry = dict(artifact)
            if (
                name.startswith(("vev-native-", "vevdb-cli-"))
                and platform in name
            ):
                entry["platform"] = platform
            artifacts[name] = entry

    combined = {
        "schema_version": 2,
        "version": version,
        "git_commit": git_commit,
        "platforms": sorted(platforms),
        "artifacts": [artifacts[name] for name in sorted(artifacts)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(combined, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
