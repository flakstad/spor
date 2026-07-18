#!/usr/bin/env python3
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

from __future__ import annotations

import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "clients" / "python"))

import vevdb


SCHEMA = """
[[:db/add 10 :db/ident :contact/email]
 [:db/add 10 :db/unique :db.unique/identity]
 [:db/add 11 :db/ident :contact/knows]
 [:db/add 11 :db/valueType :db.type/ref]]
"""

DATA = """
[{:db/id 1
  :contact/name "Ada Lovelace"
  :contact/email "ada@example.com"
  :contact/company "Analytical Engines"}
 {:db/id 2
  :contact/name "Grace Hopper"
  :contact/email "grace@example.com"
  :contact/company "Compilers"}
 [:db/add 1 :contact/knows 2]]
"""

KATHERINE = """
[{:db/id 3
  :contact/name "Katherine Johnson"
  :contact/email "katherine@example.com"
  :contact/company "NASA"}]
"""


def remove_store(path: pathlib.Path) -> None:
    for suffix in ("", "-wal", "-shm"):
        try:
            pathlib.Path(f"{path}{suffix}").unlink()
        except FileNotFoundError:
            pass


def seed(conn: vevdb.Connection | vevdb.DurableConnection) -> None:
    conn.transact(SCHEMA)
    conn.transact(DATA)


def contact_names(source: vevdb.Connection | vevdb.DurableConnection | vevdb.DB) -> list[str]:
    rows = vevdb.q(
        '[:find ?name :where [?e :contact/name ?name]]',
        source,
    )
    return sorted(row[0] for row in rows)


def assert_base_contacts(db: vevdb.DB) -> None:
    if contact_names(db) != ["Ada Lovelace", "Grace Hopper"]:
        raise RuntimeError("unexpected contact names")

    rows = vevdb.q(
        """
        [:find ?name
         :in $ ?email
         :where [?e :contact/email ?email]
                [?e :contact/name ?name]]
        """,
        db,
        '["ada@example.com"]',
    )
    if rows != [["Ada Lovelace"]]:
        raise RuntimeError("lookup query returned the wrong contact")

    profile = db.pull(
        "[:contact/name :contact/email {:contact/knows [:contact/name]}]",
        vevdb.Entity(1),
    )
    if profile.get(":contact/name") != "Ada Lovelace":
        raise RuntimeError("pull returned the wrong contact")
    if profile.get(":contact/knows", {}).get(":contact/name") != "Grace Hopper":
        raise RuntimeError("pull returned the wrong related contact")


def run_in_memory() -> None:
    with vevdb.create_conn() as conn:
        seed(conn)
        with conn.db() as db:
            assert_base_contacts(db)
            with db.db_with(KATHERINE) as next_db:
                if "Katherine Johnson" not in contact_names(next_db):
                    raise RuntimeError("db_with did not add the hypothetical contact")
                if "Katherine Johnson" in contact_names(db):
                    raise RuntimeError("db_with mutated the original DB value")


def run_durable(path: pathlib.Path) -> None:
    remove_store(path)

    with vevdb.connect(path) as conn:
        seed(conn)
        with conn.db() as db:
            assert_base_contacts(db)

    with vevdb.connect(path) as conn:
        if contact_names(conn) != ["Ada Lovelace", "Grace Hopper"]:
            raise RuntimeError("reopened durable store did not preserve contacts")
        conn.transact(KATHERINE)
        if "Katherine Johnson" not in contact_names(conn):
            raise RuntimeError("durable transaction did not update the connection DB")

    with vevdb.connect(path) as conn:
        if "Katherine Johnson" not in contact_names(conn):
            raise RuntimeError("reopened durable store did not preserve the update")

    remove_store(path)


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        durable_path = pathlib.Path(argv[1])
    else:
        durable_path = pathlib.Path(tempfile.gettempdir()) / "vev-contact-book.vev"

    run_in_memory()
    run_durable(durable_path)
    print("contact-book: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
