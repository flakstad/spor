#!/usr/bin/env python3
"""Deterministic durable-storage amplification benchmark for VevDB."""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SHAPES = ((1, 1000), (10, 100), (100, 10), (500, 2), (1000, 1))
COUNT_TABLES = (
    "vev_datoms",
    "vev_transactions",
    "vev_index_roots",
    "vev_index_root_pages",
    "vev_index_run_manifests",
    "vev_index_run_manifest_runs",
    "vev_index_run_manifest_attr_ranges",
    "vev_index_run_manifest_entity_attr_ranges",
    "vev_index_chunks",
    "vev_index_chunk_edges",
    "vev_index_chunk_entries",
)


def logical_transactions(transaction_count: int, assertions_per_transaction: int) -> str:
    transactions: list[str] = []
    assertion = 0
    for _ in range(transaction_count):
        facts: list[str] = []
        for local_id in range(1, assertions_per_transaction + 1):
            facts.append(
                f'{{:db/id -{local_id} :user/name "user-{assertion}"}}'
            )
            assertion += 1
        transactions.append("[" + " ".join(facts) + "]")
    return "[" + "".join(transactions) + "]"


def run_cli(cli: Path, arguments: list[str], stdin: str | None = None) -> str:
    completed = subprocess.run(
        [str(cli), *arguments],
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{' '.join(arguments)} failed ({completed.returncode}): "
            f"{completed.stderr.strip()}"
        )
    return completed.stdout


def median_cli_ms(cli: Path, arguments: list[str], repetitions: int) -> float:
    run_cli(cli, arguments)
    samples: list[float] = []
    for _ in range(repetitions):
        started = time.perf_counter_ns()
        run_cli(cli, arguments)
        samples.append((time.perf_counter_ns() - started) / 1_000_000.0)
    return statistics.median(samples)


def scalar(connection: sqlite3.Connection, sql: str) -> int:
    row = connection.execute(sql).fetchone()
    if row is None:
        raise RuntimeError(f"query returned no row: {sql}")
    return int(row[0])


def storage_metrics(database: Path) -> dict[str, object]:
    connection = sqlite3.connect(database)
    try:
        connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        metrics: dict[str, object] = {
            "file_bytes": scalar(
                connection,
                "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()",
            ),
            "freelist_bytes": scalar(
                connection,
                "SELECT freelist_count * page_size FROM pragma_freelist_count(), pragma_page_size()",
            ),
        }
        metrics["live_bytes"] = int(metrics["file_bytes"]) - int(metrics["freelist_bytes"])
        for table in COUNT_TABLES:
            metrics[table.removeprefix("vev_") + "_rows"] = scalar(
                connection, f"SELECT count(*) FROM {table}"
            )
        dbstat: dict[str, int] = {}
        sqlite_cli = shutil.which("sqlite3")
        if sqlite_cli:
            completed = subprocess.run(
                [
                    sqlite_cli,
                    "-separator",
                    "\t",
                    str(database),
                    "SELECT name, sum(pgsize) FROM dbstat GROUP BY name ORDER BY name",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if completed.returncode == 0:
                for line in completed.stdout.splitlines():
                    name, size = line.split("\t", maxsplit=1)
                    dbstat[name] = int(size)
        metrics["dbstat_bytes"] = dbstat
        head_basis, indexed_basis, tail_transactions, tail_datoms = connection.execute(
            """
            WITH indexed(basis) AS (
              SELECT COALESCE(MAX(basis_tx), 0) FROM vev_index_roots
            )
            SELECT COALESCE(MAX(t.tx), 0), indexed.basis,
                   (SELECT count(*) FROM vev_transactions WHERE tx > indexed.basis),
                   (SELECT count(*) FROM vev_datoms WHERE tx > indexed.basis)
            FROM vev_transactions t, indexed
            """
        ).fetchone()
        metrics.update(
            {
                "head_basis": int(head_basis),
                "indexed_basis": int(indexed_basis),
                "tail_transactions": int(tail_transactions),
                "tail_datoms": int(tail_datoms),
            }
        )
        return metrics
    finally:
        connection.close()


def measure_shape(
    cli: Path,
    output_dir: Path,
    transaction_count: int,
    assertions_per_transaction: int,
    latency_repetitions: int,
    mode: str,
) -> dict[str, object]:
    assertion_count = transaction_count * assertions_per_transaction
    database = output_dir / f"{transaction_count}x{assertions_per_transaction}.vev"
    if database.exists():
        raise RuntimeError(f"benchmark database already exists: {database}")
    transaction_edn = logical_transactions(
        transaction_count, assertions_per_transaction
    )
    transaction_path = output_dir / f"{transaction_count}x{assertions_per_transaction}.edn"
    transaction_path.write_text(transaction_edn)
    started = time.perf_counter_ns()
    run_cli(
        cli,
        ["transact-many", str(database), str(transaction_path), "--mode", mode],
    )
    transact_ms = (time.perf_counter_ns() - started) / 1_000_000.0
    metrics = storage_metrics(database)
    datom_count = int(metrics["datoms_rows"])
    metrics.update(
        {
            "shape": f"{transaction_count}x{assertions_per_transaction}",
            "mode": mode,
            "assertions": assertion_count,
            "transactions": transaction_count,
            "assertions_per_transaction": assertions_per_transaction,
            "bytes_per_assertion": float(metrics["file_bytes"]) / assertion_count,
            "bytes_per_datom": float(metrics["file_bytes"]) / datom_count,
            "transact_total_ms": transact_ms,
            "transact_average_ms": transact_ms / transaction_count,
            "open_median_ms": median_cli_ms(
                cli, ["db-info", str(database)], latency_repetitions
            ),
            "query_median_ms": median_cli_ms(
                cli,
                [
                    "query",
                    str(database),
                    "[:find (count ?e) . :where [?e :user/name]]",
                ],
                latency_repetitions,
            ),
        }
    )
    if datom_count != assertion_count + transaction_count:
        raise RuntimeError(
            f"{metrics['shape']}: expected {assertion_count + transaction_count} "
            f"datoms, observed {datom_count}"
        )
    if int(metrics["transactions_rows"]) != transaction_count:
        raise RuntimeError(
            f"{metrics['shape']}: transaction row count did not match workload"
        )
    return metrics


def check_budgets(results: list[dict[str, object]], budget_path: Path) -> list[str]:
    budgets = json.loads(budget_path.read_text())
    failures: list[str] = []
    by_shape = {str(result["shape"]): result for result in results}
    for shape, limits in budgets["shapes"].items():
        if shape not in by_shape:
            failures.append(f"budget shape {shape} was not measured")
            continue
        result = by_shape[shape]
        for metric, limit in limits.items():
            actual = result.get(metric)
            if actual is None:
                failures.append(f"{shape}: unknown budget metric {metric}")
            elif float(actual) > float(limit):
                failures.append(f"{shape}: {metric}={actual} exceeds {limit}")
    return failures


def parse_shape(text: str) -> tuple[int, int]:
    try:
        transactions, assertions = (int(part) for part in text.lower().split("x"))
    except (ValueError, TypeError) as error:
        raise argparse.ArgumentTypeError("shape must be TRANSACTIONSxASSERTIONS") from error
    if transactions <= 0 or assertions <= 0:
        raise argparse.ArgumentTypeError("shape values must be positive")
    return transactions, assertions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, default=ROOT / "build" / "vevdb")
    parser.add_argument("--build", action="store_true", help="build the CLI first")
    parser.add_argument("--shape", action="append", type=parse_shape, dest="shapes")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--budgets", type=Path)
    parser.add_argument("--latency-repetitions", type=int, default=5)
    parser.add_argument(
        "--mode", choices=("committed", "logical"), default="committed",
        help="commit each transaction independently, or use one atomic logical group",
    )
    arguments = parser.parse_args()

    if arguments.build:
        subprocess.run([str(ROOT / "scripts" / "build_cli.sh")], check=True)
    cli = arguments.cli.resolve()
    if not cli.is_file():
        parser.error(f"CLI does not exist: {cli}; pass --build or --cli")
    if arguments.latency_repetitions <= 0:
        parser.error("--latency-repetitions must be positive")

    temporary = arguments.output_dir is None
    output_dir = (
        Path(tempfile.mkdtemp(prefix="vev-storage-amplification-"))
        if temporary
        else arguments.output_dir.resolve()
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        results = [
            measure_shape(
                cli, output_dir, transactions, assertions,
                arguments.latency_repetitions, arguments.mode,
            )
            for transactions, assertions in (arguments.shapes or DEFAULT_SHAPES)
        ]
        baseline_bytes = next(
            (int(result["file_bytes"]) for result in results if result["shape"] == "1x1000"),
            None,
        )
        if baseline_bytes is not None:
            for result in results:
                transaction_count = int(result["transactions"])
                result["extra_bytes_per_transaction"] = (
                    0.0
                    if transaction_count == 1
                    else (int(result["file_bytes"]) - baseline_bytes)
                    / (transaction_count - 1)
                )
        document = {"format": "vev-storage-amplification-v2", "results": results}
        rendered = json.dumps(document, indent=2, sort_keys=True)
        print(rendered)
        if arguments.json_output:
            arguments.json_output.write_text(rendered + "\n")
        if arguments.budgets:
            failures = check_budgets(results, arguments.budgets)
            if failures:
                for failure in failures:
                    print(f"budget failure: {failure}", file=sys.stderr)
                return 1
        return 0
    finally:
        if temporary:
            shutil.rmtree(output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
