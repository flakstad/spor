#!/usr/bin/env python3
"""Run and budget the deterministic resident durable transaction benchmark."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BINARY = ROOT / "build" / "bench" / "resident-small-transactions"
DEFAULT_BUDGET = ROOT / "bench" / "resident_small_transactions_budget.json"


def build(binary: Path) -> None:
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "kvist",
            "build",
            "bench/resident_small_transactions.kvist",
            "--out",
            str(binary),
        ],
        cwd=ROOT,
        check=True,
    )


def parse_value(value: str) -> object:
    try:
        return float(value) if "." in value else int(value)
    except ValueError:
        return value


def run(binary: Path, mode: str, samples: int) -> list[dict[str, object]]:
    completed = subprocess.run(
        [str(binary), "--mode", mode, "--samples", str(samples)],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    results: list[dict[str, object]] = []
    for line in completed.stdout.splitlines():
        if not line.startswith("engine=vev-resident "):
            continue
        row: dict[str, object] = {}
        for field in line.split():
            key, value = field.split("=", maxsplit=1)
            row[key] = parse_value(value)
        results.append(row)
    return results


def budget_failures(
    results: list[dict[str, object]], budget: dict[str, object]
) -> list[str]:
    indexed = {
        f"{row['database']}/{row['workload']}": row
        for row in results
        if row["mode"] == budget["mode"]
    }
    failures: list[str] = []
    for workload, limits in budget["workloads"].items():
        if workload not in indexed:
            failures.append(f"missing benchmark result: {workload}")
            continue
        for metric, limit in limits.items():
            actual = float(indexed[workload][metric])
            if actual > float(limit):
                failures.append(
                    f"{workload}: {metric}={actual:g} exceeds {float(limit):g}"
                )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--samples", type=int, default=40)
    parser.add_argument("--mode", choices=("incremental", "full", "both"), default="incremental")
    parser.add_argument("--budget", type=Path, default=DEFAULT_BUDGET)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--no-build", action="store_true")
    arguments = parser.parse_args()
    binary = arguments.binary.resolve()
    if not arguments.no_build:
        build(binary)
    modes = ("full", "incremental") if arguments.mode == "both" else (arguments.mode,)
    results = [row for mode in modes for row in run(binary, mode, arguments.samples)]
    document = {"format": "vev-resident-small-transactions-v1", "results": results}
    rendered = json.dumps(document, indent=2, sort_keys=True)
    print(rendered)
    if arguments.json_output:
        arguments.json_output.write_text(rendered + "\n")
    if "incremental" not in modes:
        return 0
    budget = json.loads(arguments.budget.read_text())
    failures = budget_failures(results, budget)
    for failure in failures:
        print(f"budget failure: {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
