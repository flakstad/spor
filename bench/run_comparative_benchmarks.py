#!/usr/bin/env python3
"""Run reproducible DataScript/Datalevin/Datomic/Vev query comparisons.

The adapters expose every timed-window sample. This runner reports median/p95
across those samples and can optionally restart each engine for additional
outer samples. Raw stdout and stderr are retained in the JSON artifact so the
result can be audited without re-running the campaign.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import pathlib
import platform
import statistics
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_QUERIES = ["q1", "q2", "q2-switch", "q3", "q4", "qpred1", "qpred2"]
TRACKS = {
    "current": {
        "datascript": "1.7.8",
        "datalevin": "0.10.7",
        "datomic": "1.0.7705",
    },
    "historical": {
        "datascript": "1.7.4",
        "datalevin": "0.10.5",
        "datomic": "1.0.7277",
    },
}


def command_output(*command: str) -> str:
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.stdout.strip()


def percentile(values: list[float], quantile: float) -> float:
    """Nearest-rank percentile, matching the benchmark's simple semantics."""
    ordered = sorted(values)
    rank = max(1, math.ceil(quantile * len(ordered)))
    return ordered[rank - 1]


def parse_table(stdout: str) -> dict[str, dict[str, float]]:
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    header_index = next(
        (index for index, line in enumerate(lines) if line.startswith("query\t")),
        None,
    )
    if header_index is None:
        raise ValueError(f"comparison output contains no result table:\n{stdout}")

    columns = lines[header_index].split("\t")
    engines = [column for column in columns[1:] if "/" not in column]
    parsed: dict[str, dict[str, float]] = {}
    for line in lines[header_index + 1 :]:
        cells = line.split("\t")
        if len(cells) < 1 + len(engines):
            continue
        query = cells[0]
        try:
            parsed[query] = {
                engine: float(cells[index + 1])
                for index, engine in enumerate(engines)
            }
        except ValueError:
            continue
    if not parsed:
        raise ValueError(f"comparison result table has no numeric rows:\n{stdout}")
    return parsed


def parse_sample_logs(
    stderr: str, queries: list[str]
) -> dict[str, dict[str, list[float]]]:
    grouped: dict[str, list[list[float]]] = {}
    for line in stderr.splitlines():
        fields = line.strip().split()
        if len(fields) != 3 or fields[0] != "benchmark_samples":
            continue
        grouped.setdefault(fields[1], []).append(
            [float(value) for value in fields[2].split(",")]
        )
    parsed: dict[str, dict[str, list[float]]] = {}
    for engine, groups in grouped.items():
        if len(groups) != len(queries):
            raise ValueError(
                f"expected {len(queries)} sample groups for {engine}, got {len(groups)}"
            )
        parsed[engine] = dict(zip(queries, groups, strict=True))
    return parsed


def summarize(
    samples: list[dict[str, dict[str, float]]],
    timed_samples: dict[str, dict[str, list[float]]],
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    queries = samples[0].keys()
    for query in queries:
        result[query] = {}
        for engine in samples[0][query]:
            values = timed_samples.get(engine, {}).get(
                query, [sample[query][engine] for sample in samples]
            )
            result[query][engine] = {
                "median_ms": statistics.median(values),
                "p95_ms": percentile(values, 0.95),
                "samples_ms": values,
            }
    return result


def run_track(args: argparse.Namespace, track: str) -> dict[str, Any]:
    versions = TRACKS[track]
    samples: list[dict[str, dict[str, float]]] = []
    timed_samples: dict[str, dict[str, list[float]]] = {}
    raw_runs: list[dict[str, Any]] = []
    orders = ["datascript datalevin", "datalevin datascript"]

    for index in range(args.runs):
        env = os.environ.copy()
        env.update(
            {
                "DATALEVIN_BENCH": str(args.datalevin_bench),
                "DATASCRIPT_VERSION": versions["datascript"],
                "DATALEVIN_VERSION": versions["datalevin"],
                "DATOMIC_VERSION": versions["datomic"],
                "VEV_COMPARE_DATOMIC": "1",
                "VEV_COMPARE_BASELINES": orders[index % len(orders)],
                "VEV_COMPARE_VEV_FIRST": str(index % 2),
                "VEV_BENCH_PEOPLE": str(args.people),
                "VEV_BENCH_WARMUP_MS": str(args.warmup_ms),
                "VEV_BENCH_MS": str(args.measure_ms),
                "VEV_BENCH_REPEATS": str(args.inner_repeats),
                "VEV_BENCH_STEP": str(args.step),
                "VEV_BENCH_SAMPLE_LOG": "1",
                # The DB is immutable and every query has its own warmup. Reusing
                # the fixture removes minutes of untimed setup per process.
                "VEV_BENCH_ISOLATED_DBS": "false",
            }
        )
        command = [
            str(ROOT / "bench/datascript_bench/run_compare.sh"),
            *args.queries,
        ]
        print(
            f"[{track} {index + 1}/{args.runs}] "
            f"order={env['VEV_COMPARE_BASELINES']} "
            f"vev_first={env['VEV_COMPARE_VEV_FIRST']}",
            file=sys.stderr,
            flush=True,
        )
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
        raw_runs.append(
            {
                "index": index + 1,
                "started_at": started.isoformat(),
                "duration_seconds": (ended - started).total_seconds(),
                "baseline_order": env["VEV_COMPARE_BASELINES"].split(),
                "vev_first": env["VEV_COMPARE_VEV_FIRST"] == "1",
                "exit_code": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
            }
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"comparison run failed ({track}, sample {index + 1}):\n"
                f"{completed.stderr}\n{completed.stdout}"
            )
        parsed = parse_table(completed.stdout)
        logged = parse_sample_logs(completed.stderr, args.queries)
        missing = set(args.queries) - set(parsed)
        if missing:
            raise RuntimeError(f"missing result rows: {sorted(missing)}")
        samples.append(parsed)
        for engine, query_samples in logged.items():
            destination = timed_samples.setdefault(engine, {})
            for query, values in query_samples.items():
                destination.setdefault(query, []).extend(values)

    return {
        "versions": versions,
        "summary": summarize(samples, timed_samples),
        "raw_runs": raw_runs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--track",
        choices=["current", "historical", "both"],
        default="both",
    )
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--people", type=int, default=20_000)
    parser.add_argument("--warmup-ms", type=int, default=250)
    parser.add_argument("--measure-ms", type=int, default=500)
    parser.add_argument("--inner-repeats", type=int, default=5)
    parser.add_argument("--step", type=int, default=10)
    parser.add_argument("--queries", nargs="+", default=DEFAULT_QUERIES)
    parser.add_argument(
        "--datalevin-bench",
        type=pathlib.Path,
        default=pathlib.Path(
            os.environ.get(
                "DATALEVIN_BENCH",
                pathlib.Path.home() / "Projects/datalevin/benchmarks/datascript-bench",
            )
        ),
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=ROOT
        / "bench/results"
        / f"{dt.date.today().isoformat()}-comparative-queries.json",
    )
    args = parser.parse_args()
    if args.runs < 1 or args.inner_repeats < 1:
        parser.error("repeat counts must be positive")
    if not args.datalevin_bench.is_dir():
        parser.error(f"Datalevin benchmark directory not found: {args.datalevin_bench}")

    selected_tracks = ["current", "historical"] if args.track == "both" else [args.track]
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "git_revision": command_output("git", "rev-parse", "HEAD"),
        "system": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "python": platform.python_version(),
            "java": command_output("java", "-version"),
        },
        "methodology": {
            "fixture_seed": 42,
            "insertion_order_seed": 43,
            "people": args.people,
            "queries": args.queries,
            "outer_process_samples": args.runs,
            "warmup_ms": args.warmup_ms,
            "measurement_window_ms": args.measure_ms,
            "inner_samples": args.inner_repeats,
            "step": args.step,
            "vev_fixture_instances": "one shared immutable DB",
            "reported_unit": "milliseconds per query",
            "summary": "median and nearest-rank p95 across timed-window samples",
        },
        "tracks": {},
    }
    for track in selected_tracks:
        artifact["tracks"][track] = run_track(args, track)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
