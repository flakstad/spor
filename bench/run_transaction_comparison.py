#!/usr/bin/env python3
"""Run the common small-transaction matrix across Vev and peer engines."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
VEV_BINARY = ROOT / "build/bench/resident-small-transactions"


def parse_value(value: str) -> object:
    try:
        return float(value) if "." in value else int(value)
    except ValueError:
        return value


def parse_rows(stdout: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line in stdout.splitlines():
        if not line.startswith("engine="):
            continue
        row: dict[str, object] = {}
        for field in line.split():
            if "=" not in field:
                continue
            key, value = field.split("=", maxsplit=1)
            row[key] = parse_value(value)
        if "median_us" in row and "p95_us" in row:
            rows.append(row)
    return rows


def run(
    command: list[str], label: str, env: dict[str, str] | None = None
) -> tuple[list[dict[str, object]], dict[str, Any]]:
    print(f"running {label}", file=sys.stderr, flush=True)
    started = dt.datetime.now(dt.timezone.utc)
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    ended = dt.datetime.now(dt.timezone.utc)
    raw = {
        "label": label,
        "command": command,
        "started_at": started.isoformat(),
        "duration_seconds": (ended - started).total_seconds(),
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }
    if completed.returncode != 0:
        raise RuntimeError(
            f"{label} failed with exit code {completed.returncode}:\n"
            f"{completed.stderr}\n{completed.stdout}"
        )
    rows = parse_rows(completed.stdout)
    if not rows:
        raise RuntimeError(f"{label} emitted no benchmark rows:\n{completed.stdout}")
    return rows, raw


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=40)
    parser.add_argument("--warmups", type=int, default=5)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument(
        "--datomic-uri-prefix",
        help=(
            "also run durable Datomic against this database URI prefix; "
            "for example datomic:dev://localhost:4334/vev-resident-"
        ),
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=ROOT
        / "bench/results"
        / f"{dt.date.today().isoformat()}-comparative-transactions.json",
    )
    args = parser.parse_args()
    if args.samples < 1 or args.warmups < 0:
        parser.error("--samples must be positive and --warmups cannot be negative")

    if not args.no_build:
        VEV_BINARY.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                "kvist",
                "build",
                "bench/resident_small_transactions.kvist",
                "--out",
                str(VEV_BINARY),
            ],
            cwd=ROOT,
            check=True,
        )

    rows: list[dict[str, object]] = []
    raw_runs: list[dict[str, Any]] = []
    for mode in ("incremental", "full"):
        parsed, raw = run(
            [str(VEV_BINARY), "--mode", mode, "--samples", str(args.samples)],
            f"vev-{mode}",
        )
        rows.extend(parsed)
        raw_runs.append(raw)

    if args.datomic_uri_prefix:
        datomic_env = os.environ.copy()
        datomic_env["VEV_BENCH_DATOMIC_URI_PREFIX"] = args.datomic_uri_prefix
        parsed, raw = run(
            [
                str(ROOT / "bench/transaction_comparison/run_engine.sh"),
                "datomic",
                "--samples",
                str(args.samples),
                "--warmups",
                str(args.warmups),
            ],
            "datomic-durable",
            datomic_env,
        )
        rows.extend(parsed)
        raw_runs.append(raw)

    for engine in ("datascript", "datalevin", "datomic"):
        parsed, raw = run(
            [
                str(ROOT / "bench/transaction_comparison/run_engine.sh"),
                engine,
                "--samples",
                str(args.samples),
                "--warmups",
                str(args.warmups),
            ],
            engine,
        )
        rows.extend(parsed)
        raw_runs.append(raw)

    artifact = {
        "format": "vev-small-transaction-comparison-v1",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "versions": {
            "vev": subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
            ).strip(),
            "datascript": os.environ.get("DATASCRIPT_VERSION", "1.7.8"),
            "datalevin": os.environ.get("DATALEVIN_VERSION", "0.10.7"),
            "datomic_peer": os.environ.get("DATOMIC_VERSION", "1.0.7705"),
            "datomic_transactor": "1.0.7277" if args.datomic_uri_prefix else None,
        },
        "methodology": {
            "samples": args.samples,
            "warmups_for_clojure_engines": args.warmups,
            "databases": {"small": 50, "large": 2000},
            "workloads": [
                "append",
                "replacement",
                "explicit-retract",
                "retract-entity",
                "ro-like",
            ],
            "timed_scope": "synchronous transaction call returning its report",
            "durability_warning": (
                "Vev resident and Datalevin WAL strict rows are durable. "
                "DataScript and the Datomic mem peer rows are in-memory references; "
                "Datomic durable-dev rows are durable when present."
            ),
        },
        "results": rows,
        "raw_runs": raw_runs,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
