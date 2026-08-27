#!/usr/bin/env python3
"""Build, run, and budget the public Kvist transaction boundary benchmark."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BINARY = ROOT / "build" / "bench" / "kvist-transaction-boundary"
DEFAULT_BUDGET = ROOT / "bench" / "kvist_transaction_boundary_budget.json"
BOUNDARY_PHASES = (
    "kvist-edn-write",
    "abi-input-copy",
    "vev-edn-parse",
    "native-report-handle",
    "native-listener",
    "native-cleanup",
    "db-before-retain",
    "db-after-retain",
    "report-value-materialize",
)


def build(binary: Path) -> Path:
    binary.parent.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        [str(ROOT / "scripts" / "build_native_library.sh"), "--if-needed"],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    library = Path(completed.stdout.strip()).resolve()
    subprocess.run(
        [
            "kvist",
            "build",
            "bench/kvist_transaction_boundary.kvist",
            "--out",
            str(binary),
        ],
        cwd=ROOT,
        check=True,
    )
    return library


def parse_output(output: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line in output.splitlines():
        if not line.startswith("engine=vev-kvist-boundary "):
            continue
        row: dict[str, object] = {}
        for field in line.split():
            key, value = field.split("=", maxsplit=1)
            try:
                row[key] = float(value) if "." in value else int(value)
            except ValueError:
                row[key] = value
        rows.append(row)
    return rows


def summarized(rows: list[dict[str, object]]) -> dict[str, dict[str, float]]:
    phases: dict[str, dict[str, dict[str, float]]] = {}
    for row in rows:
        key = f"{row['database']}/{row['workload']}"
        phases.setdefault(key, {})[str(row["phase"])] = {
            "median_us": float(row["median_us"]),
            "p95_us": float(row["p95_us"]),
        }
    out: dict[str, dict[str, float]] = {}
    for key, values in phases.items():
        missing = [phase for phase in BOUNDARY_PHASES if phase not in values]
        if missing:
            raise RuntimeError(f"{key}: missing phases: {', '.join(missing)}")
        out[key] = {
            "public_median_us": values["public-total"]["median_us"],
            "public_p95_us": values["public-total"]["p95_us"],
            "resolution_median_us": values["resolution"]["median_us"],
            "planning_median_us": values["planning"]["median_us"],
            "effective_datoms": values["effective-datoms"]["median_us"],
            "report_value_materialize_p95_us": values[
                "report-value-materialize"
            ]["p95_us"],
            # A deliberately conservative budget: summing phase p95 values is
            # no smaller than a paired end-to-end percentile and remains valid
            # even though engine profiling runs in a separate pass.
            "structured_boundary_p95_us": sum(
                values[phase]["p95_us"] for phase in BOUNDARY_PHASES
            ),
        }
    return out


def budget_failures(
    results: dict[str, dict[str, float]], budget: dict[str, object]
) -> list[str]:
    failures: list[str] = []
    workloads = budget.get("workloads", {})
    if not isinstance(workloads, dict):
        return ["budget workloads must be an object"]
    for workload, limits in workloads.items():
        if workload not in results:
            failures.append(f"missing benchmark result: {workload}")
            continue
        if not isinstance(limits, dict):
            failures.append(f"{workload}: limits must be an object")
            continue
        for metric, limit in limits.items():
            actual = results[workload].get(metric)
            if actual is None:
                failures.append(f"{workload}: missing metric {metric}")
            elif actual > float(limit):
                failures.append(
                    f"{workload}: {metric}={actual:g} exceeds {float(limit):g}"
                )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--budget", type=Path, default=DEFAULT_BUDGET)
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--ro-public-db", default="")
    parser.add_argument("--ro-native-db", default="")
    parser.add_argument("--ro-only", action="store_true")
    arguments = parser.parse_args()

    binary = arguments.binary.resolve()
    if arguments.no_build:
        library_name = (
            "libvev.dylib"
            if sys.platform == "darwin"
            else "vev.dll"
            if sys.platform == "win32"
            else "libvev.so"
        )
        library = (ROOT / "build" / "lib" / library_name).resolve()
    else:
        library = build(binary)

    command = [str(binary), "--samples", str(arguments.samples)]
    if arguments.ro_only:
        command.extend(["--database", "none", "--workload", "none"])
    if arguments.ro_public_db or arguments.ro_native_db:
        if not arguments.ro_public_db or not arguments.ro_native_db:
            parser.error("--ro-public-db and --ro-native-db must be supplied together")
        command.extend(
            [
                "--ro-public-db",
                arguments.ro_public_db,
                "--ro-native-db",
                arguments.ro_native_db,
            ]
        )

    environment = os.environ.copy()
    environment["VEV_LIB"] = str(library)
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=environment,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    results = summarized(parse_output(completed.stdout))
    document = {
        "format": "vev-kvist-transaction-boundary-v1",
        "results": results,
    }
    rendered = json.dumps(document, indent=2, sort_keys=True)
    print(rendered)
    if arguments.json_output:
        arguments.json_output.write_text(rendered + "\n")

    budget = json.loads(arguments.budget.read_text())
    configured_workloads = budget.get("workloads", {})
    required_workloads = (
        ["ro-demo/ro-demo"]
        if arguments.ro_only
        else ["large/ro-like"]
        + (["ro-demo/ro-demo"] if arguments.ro_public_db else [])
    )
    selected_budget = {
        "workloads": {
            workload: configured_workloads[workload]
            for workload in required_workloads
            if workload in configured_workloads
        }
    }
    missing_configuration = [
        workload
        for workload in required_workloads
        if workload not in configured_workloads
    ]
    failures = [
        f"budget has no configuration for {workload}"
        for workload in missing_configuration
    ]
    failures.extend(budget_failures(results, selected_budget))
    for failure in failures:
        print(f"budget failure: {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
