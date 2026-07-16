#!/usr/bin/env python3
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

import pathlib
import sys
from datetime import datetime

import vev


def remove_sqlite_files(path: pathlib.Path) -> None:
    for suffix in ("", "-wal", "-shm"):
        try:
            pathlib.Path(f"{path}{suffix}").unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    with vev.create_conn() as conn:
        with conn.transact_report(
            """
            [{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
             {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}]
            """
        ) as tx:
            tx_value = tx.value()
            print(f"tx: {tx.edn()}")
            tx_data = tx_value.get(":tx-data", [])
            tx_instants = [
                datom
                for datom in tx_data
                if datom.get(":a") == ":db/txInstant"
            ]
            if not tx_value.get(":ok") or len(tx_data) != 5:
                raise RuntimeError("unexpected typed transaction report")
            if len(tx_instants) != 1 or not isinstance(
                tx_instants[0].get(":v"), datetime
            ):
                raise RuntimeError("transaction report did not expose a native instant")

        conn.transact(
            """
            [[:db/add 90 :db/ident :user/email]
             [:db/add 90 :db/unique :db.unique/identity]]
            """
        )

        collection = conn.query_text(
            """
            [:find ?name
             :in $ [?email ...]
             :where [?e :user/email ?email]
                    [?e :user/name ?name]]
            """,
            '[["ada@example.com" "grace@example.com"]]',
        )
        print(f"input-collection: {collection}")
        if '"Ada"' not in collection or '"Grace"' not in collection:
            raise RuntimeError("unexpected collection query output")

        one_shot_rows = vev.q(
            '[:find ?name :where [?e :user/name ?name]]',
            conn,
        )
        if sorted(row[0] for row in one_shot_rows) != ["Ada", "Grace"]:
            raise RuntimeError("unexpected one-shot query rows")

        conn.transact(
            """
            [[:db/add 100 :db/ident :user/friend]
             [:db/add 100 :db/valueType :db.type/ref]
             [:db/add 1 :user/friend 2]]
            """
        )

        try:
            conn.prepare("[:find ?e :where [?e")
            raise RuntimeError("invalid query unexpectedly prepared")
        except vev.VevError as error:
            if not str(error):
                raise RuntimeError("invalid query did not expose an error") from error

        email_query = conn.prepare(
            """
            [:find ?e ?email
             :in $ ?needle
             :where [?e :user/email ?email]
                    [(= ?email ?needle)]]
            """
        )
        try:
            prepared_ast = email_query.edn()
            if ":clauses" not in prepared_ast or ":input-specs" not in prepared_ast:
                raise RuntimeError("prepared query AST did not expose parser keys")
            clause_ast = vev.parse_clause_edn("[?e :user/email ?email]")
            if ":clauses" not in clause_ast or ":user/email" not in clause_ast:
                raise RuntimeError("parse-clause AST did not expose parser keys")

            with email_query.statement() as stmt:
                rows = stmt.bind("grace@example.com").rows(conn)
                print(f"statement rows: {rows}")
                if rows != [[vev.Entity(2), "grace@example.com"]]:
                    raise RuntimeError("unexpected statement rows")

                streamed = stmt.stream_rows(conn)
                print(f"streamed statement rows: {streamed}")
                if streamed != rows:
                    raise RuntimeError("unexpected streamed statement rows")

                try:
                    stmt.visit(conn, lambda event, row, index, value: False)
                    raise RuntimeError("cancelled visitor unexpectedly succeeded")
                except vev.VevError as error:
                    if "cancelled" not in str(error):
                        raise RuntimeError("unexpected visitor cancellation error") from error

                rows = stmt.bind("ada@example.com").rows(conn)
                print(f"statement rebound rows: {rows}")
                if rows != [[vev.Entity(1), "ada@example.com"]]:
                    raise RuntimeError("unexpected rebound statement rows")

            collection_query = conn.prepare(
                """
                [:find ?name
                 :in $ [?email ...]
                 :where [?e :user/email ?email]
                        [?e :user/name ?name]]
                """
            )
            try:
                with collection_query.statement() as stmt:
                    rows = stmt.bind(["ada@example.com", "grace@example.com"]).rows(conn)
                    names = sorted(row[0] for row in rows)
                    print(f"statement collection names: {names}")
                    if names != ["Ada", "Grace"]:
                        raise RuntimeError("unexpected collection statement rows")
                with collection_query.statement() as stmt:
                    rows = stmt.bind(vev.TypedCollection("string")).rows(conn)
                    if rows != []:
                        raise RuntimeError("unexpected empty typed collection rows")
            finally:
                collection_query.close()

            all_emails_query = conn.prepare(
                """
                [:find ?email
                 :where [?e :user/email ?email]]
                """
            )
            try:
                with conn.db() as db:
                    columns = db.query_columns(all_emails_query)
                    if columns is None:
                        raise RuntimeError("expected string column batch")
                    emails = sorted(row[0] for row in columns.rows())
                    print(f"column batch emails: {emails}")
                    if columns.kinds != (vev.VEV_COLUMN_STRING,):
                        raise RuntimeError("unexpected column batch kind")
                    if emails != ["ada@example.com", "grace@example.com"]:
                        raise RuntimeError("unexpected column batch rows")

                with all_emails_query.statement() as stmt:
                    columns = stmt.columns(conn)
                    if columns is None:
                        raise RuntimeError("expected live statement column batch")
                    emails = sorted(row[0] for row in columns.rows())
                    if columns.kinds != (vev.VEV_COLUMN_STRING,):
                        raise RuntimeError("unexpected live statement column batch kind")
                    if emails != ["ada@example.com", "grace@example.com"]:
                        raise RuntimeError("unexpected live statement column batch rows")

                    with conn.db() as db:
                        columns = stmt.columns(db)
                        if columns is None:
                            raise RuntimeError("expected snapshot statement column batch")
                        emails = sorted(row[0] for row in columns.rows())
                        if columns.kinds != (vev.VEV_COLUMN_STRING,):
                            raise RuntimeError(
                                "unexpected snapshot statement column batch kind"
                            )
                        if emails != ["ada@example.com", "grace@example.com"]:
                            raise RuntimeError(
                                "unexpected snapshot statement column batch rows"
                            )
            finally:
                all_emails_query.close()

            tuple_query = conn.prepare(
                """
                [:find ?e
                 :in $ [?name ?email]
                 :where [?e :user/name ?name]
                        [?e :user/email ?email]]
                """
            )
            try:
                with tuple_query.statement() as stmt:
                    rows = stmt.bind(vev.TupleInput(("Ada", "ada@example.com"))).rows(conn)
                    print(f"tuple statement rows: {rows}")
                    if rows != [[vev.Entity(1)]]:
                        raise RuntimeError("unexpected tuple statement rows")
            finally:
                tuple_query.close()

            relation_query = conn.prepare(
                """
                [:find ?name ?label
                 :in $ [[?email ?label]]
                 :where [?e :user/email ?email]
                        [?e :user/name ?name]]
                """
            )
            try:
                with relation_query.statement() as stmt:
                    rows = stmt.bind(
                        vev.Relation(
                            (
                                ("ada@example.com", "primary"),
                                ("missing@example.com", "missing"),
                            )
                        )
                    ).rows(conn)
                    print(f"relation statement rows: {rows}")
                    if rows != [["Ada", "primary"]]:
                        raise RuntimeError("unexpected relation statement rows")
            finally:
                relation_query.close()

            lookup_query = conn.prepare(
                """
                [:find ?name
                 :in $ ?person
                 :where [?person :user/name ?name]]
                """
            )
            try:
                with lookup_query.statement() as stmt:
                    rows = stmt.bind(vev.LookupRef(":user/email", "ada@example.com")).rows(conn)
                    print(f"lookup-ref statement rows: {rows}")
                    if rows != [["Ada"]]:
                        raise RuntimeError("unexpected lookup-ref statement rows")
            finally:
                lookup_query.close()

            conn.transact(
                """
                [[:db/add 91 :db/ident :user/code]
                 [:db/add 91 :db/unique :db.unique/identity]
                 [:db/add 1 :user/code 101]
                 [:db/add 2 :user/code 202]]
                """
            )

            lookup_collection_query = conn.prepare(
                """
                [:find ?name
                 :in $ [?person ...]
                 :where [?person :user/name ?name]]
                """
            )
            try:
                with lookup_collection_query.statement() as stmt:
                    rows = stmt.bind(
                        [
                            vev.LookupRef(":user/email", "ada@example.com"),
                            vev.LookupRef(":user/email", "grace@example.com"),
                        ]
                    ).rows(conn)
                    names = sorted(row[0] for row in rows)
                    print(f"lookup-ref collection statement names: {names}")
                    if names != ["Ada", "Grace"]:
                        raise RuntimeError("unexpected lookup-ref collection statement rows")
                with lookup_collection_query.statement() as stmt:
                    rows = stmt.bind(
                        [
                            vev.LookupRef(":user/code", 101),
                            vev.LookupRef(":user/code", 202),
                        ]
                    ).rows(conn)
                    names = sorted(row[0] for row in rows)
                    if names != ["Ada", "Grace"]:
                        raise RuntimeError("unexpected int lookup-ref collection rows")
            finally:
                lookup_collection_query.close()

            pull_query = conn.prepare(
                """
                [:find (pull ?e [:user/name {:user/friend [:user/name]}])
                 :where [?e :user/name "Ada"]]
                """
            )
            try:
                pulled = pull_query.scalar(conn)
                print(f"pull: {pulled}")
                if (
                    pulled.get(":user/name") != "Ada"
                    or pulled.get(":user/friend", {}).get(":user/name") != "Grace"
                ):
                    raise RuntimeError("unexpected pull result")

                with pull_query.statement() as stmt:
                    columns = stmt.columns(conn)
                print(f"pull column batch: {columns}")
                if (
                    columns is None
                    or columns.kinds != (vev.VEV_COLUMN_VALUE,)
                    or columns.rows()
                    != [[{":user/name": "Ada", ":user/friend": {":user/name": "Grace"}}]]
                ):
                    raise RuntimeError("unexpected pull column batch")
            finally:
                pull_query.close()

            with conn.db() as pull_db:
                direct_pull = pull_db.pull(
                    "[:user/name {:user/friend [:user/name]}]", vev.Entity(1)
                )
                print(f"direct pull: {direct_pull}")
                if (
                    direct_pull.get(":user/name") != "Ada"
                    or direct_pull.get(":user/friend", {}).get(":user/name") != "Grace"
                ):
                    raise RuntimeError("unexpected direct pull")

                lookup_pull = pull_db.pull_lookup_ref(
                    "[:user/name]",
                    vev.LookupRef(":user/email", "ada@example.com"),
                )
                print(f"lookup pull: {lookup_pull}")
                if lookup_pull.get(":user/name") != "Ada":
                    raise RuntimeError("unexpected lookup-ref pull")

                many_pull = pull_db.pull_many("[:user/name]", [vev.Entity(1), vev.Entity(2)])
                print(f"pull many: {many_pull}")
                names = sorted(item.get(":user/name") for item in many_pull)
                if names != ["Ada", "Grace"]:
                    raise RuntimeError("unexpected pull-many")

                with pull_db.entity(1) as ada, ada.ref(":user/friend") as friend:
                    lookup = pull_db.entity_lookup_ref(":user/email", "ada@example.com")
                    try:
                        print(f"entity view: {ada.touch()}")
                        if (
                            not ada.found()
                            or ada.id != 1
                            or ada[":user/name"] != "Ada"
                            or ada.values(":user/name") != ["Ada"]
                            or friend.id != 2
                            or friend.get(":user/name") != "Grace"
                            or ada.refs(":user/friend") != [vev.Entity(2)]
                            or lookup.id != 1
                            or lookup.get(":user/name") != "Ada"
                            or ada.touch().get(":user/name") != "Ada"
                        ):
                            raise RuntimeError("unexpected entity view output")
                    finally:
                        lookup.close()

                many_lookup_pull = pull_db.pull_many_lookup_ref(
                    "[:user/name]",
                    [
                        vev.LookupRef(":user/email", "ada@example.com"),
                        vev.LookupRef(":user/email", "missing@example.com"),
                        vev.LookupRef(":user/email", "grace@example.com"),
                    ],
                )
                if (
                    len(many_lookup_pull) != 3
                    or many_lookup_pull[0].get(":user/name") != "Ada"
                    or many_lookup_pull[1] is not None
                    or many_lookup_pull[2].get(":user/name") != "Grace"
                ):
                    raise RuntimeError("unexpected pull-many lookup-ref")

                with vev.prepare_pull_pattern("[:user/name]") as prepared_pattern:
                    prepared_pattern_ast = prepared_pattern.edn()
                    if (
                        ":pattern" not in prepared_pattern_ast
                        or ":attr" not in prepared_pattern_ast
                    ):
                        raise RuntimeError(
                            "prepared pull pattern AST did not expose parser keys"
                        )
                    prepared_pull = pull_db.pull(prepared_pattern, vev.Entity(1))
                    prepared_many = pull_db.pull_many(
                        prepared_pattern, [vev.Entity(1), vev.Entity(2)]
                    )
                    prepared_many_lookup = pull_db.pull_many_lookup_ref(
                        prepared_pattern,
                        [
                            vev.LookupRef(":user/email", "ada@example.com"),
                            vev.LookupRef(":user/email", "grace@example.com"),
                        ],
                    )
                    print(f"prepared direct pull: {prepared_pull}")
                    if prepared_pull.get(":user/name") != "Ada":
                        raise RuntimeError("unexpected prepared pull")
                    prepared_names = sorted(item.get(":user/name") for item in prepared_many)
                    if prepared_names != ["Ada", "Grace"]:
                        raise RuntimeError("unexpected prepared pull-many")
                    prepared_lookup_names = sorted(
                        item.get(":user/name") for item in prepared_many_lookup
                    )
                    if prepared_lookup_names != ["Ada", "Grace"]:
                        raise RuntimeError("unexpected prepared pull-many lookup-ref")

            with conn.prepare(
                "[:find ?name :in $ % :where (named ?e ?name)]"
            ) as rules_query, conn.db() as rules_db:
                rules_rows = rules_query.rows_with_rules(
                    rules_db,
                    "[[(named ?e ?name) [?e :user/name ?name]]]",
                )
                rule_names = sorted(row[0] for row in rules_rows)
                print(f"snapshot rules rows: {rule_names}")
                if rule_names != ["Ada", "Grace"]:
                    raise RuntimeError("unexpected snapshot rules rows")

            pull_pattern_query = conn.prepare(
                """
                [:find (pull ?e ?pattern)
                 :in $ ?pattern ?name
                 :where [?e :user/name ?name]]
                """
            )
            try:
                with pull_pattern_query.statement() as stmt:
                    pulled = stmt.bind(
                        vev.PullPattern("[:user/name {:user/friend [:user/name]}]"),
                        "Ada",
                    ).scalar(conn)
                    print(f"statement pull pattern: {pulled}")
                    if (
                        pulled.get(":user/name") != "Ada"
                        or pulled.get(":user/friend", {}).get(":user/name") != "Grace"
                    ):
                        raise RuntimeError("unexpected statement pull pattern")
            finally:
                pull_pattern_query.close()

            with vev.create_conn() as right_conn:
                right_conn.transact(
                    """
                    [{:db/id 1 :user/name "Ada Right"}
                     {:db/id 2 :user/name "Grace Right"}]
                    """
                )
                with conn.db() as left_db, right_conn.db() as right_db:
                    source_query = conn.prepare(
                        """
                        [:find ?e ?left-name ?right-name
                         :in $left $right [?e ...]
                         :where [$left ?e :user/name ?left-name]
                                [$right ?e :user/name ?right-name]]
                        """,
                        ["$left", "$right"],
                    )
                    try:
                        with source_query.statement() as stmt:
                            rows = stmt.bind(
                                vev.DBSource("$left", left_db),
                                vev.DBSource("$right", right_db),
                                [vev.Entity(1), vev.Entity(2)],
                            ).rows(conn)
                            print(f"statement DB sources: {rows}")
                            first = rows[0]
                            if (
                                len(rows) != 2
                                or first[1] != "Ada"
                                or first[2] != "Ada Right"
                            ):
                                raise RuntimeError("unexpected statement DB sources")
                    finally:
                        source_query.close()

            all_emails = conn.prepare(
                "[:find ?e ?email :where [?e :user/email ?email]]"
            )
            try:
                with conn.db() as snapshot:
                    conn.transact(
                        '[{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}]'
                    )

                    current_rows = len(all_emails.rows(conn))
                    snapshot_rows = len(all_emails.rows(snapshot))
                    print(f"current-db rows: {current_rows}")
                    print(f"snapshot-db rows: {snapshot_rows}")
                    if current_rows != 3 or snapshot_rows != 2:
                        raise RuntimeError("unexpected snapshot row counts")

                    with conn.prepare(
                        '[:find ?e :where [?e :user/name "Barbara"]]'
                    ) as barbara_query, conn.prepare(
                        '[:find ?e :where [?e :user/name "Dorothy"]]'
                    ) as dorothy_query:
                        with snapshot.with_report(
                            '[{:db/id 4 :user/name "Barbara"}]'
                        ) as report:
                            report_value = report.value()
                            print(f"with-db: {report.edn()}")
                            if not report_value.get(":ok"):
                                raise RuntimeError("unexpected with report")
                            with report.db_before() as before_db, report.db_after() as after_db:
                                if len(barbara_query.rows(before_db)) != 0:
                                    raise RuntimeError("with report db-before contains new fact")
                                if len(barbara_query.rows(after_db)) != 1:
                                    raise RuntimeError("with report db-after missing new fact")
                        with snapshot.db_with(
                            '[{:db/id 4 :user/name "Barbara"}]'
                        ) as next_db:
                            if len(barbara_query.rows(snapshot)) != 0:
                                raise RuntimeError("db-with mutated source DB")
                            if len(barbara_query.rows(next_db)) != 1:
                                raise RuntimeError("db-with missing new fact")
                            with vev.Connection.from_db(next_db) as derived:
                                derived.transact(
                                    '[{:db/id 5 :user/name "Dorothy"}]'
                                )
                                if (
                                    len(barbara_query.rows(derived)) != 1
                                    or len(dorothy_query.rows(derived)) != 1
                                ):
                                    raise RuntimeError(
                                        "conn-from-db did not initialize from DB"
                                    )
            finally:
                all_emails.close()
        finally:
            email_query.close()

    sqlite_path = pathlib.Path("tmp.vev.python.sqlite")
    remove_sqlite_files(sqlite_path)
    first_durable_basis = 0
    try:
        with vev.connect(sqlite_path) as durable:
            if durable.backend() != "sqlite" or durable.path() != str(sqlite_path):
                raise RuntimeError("unexpected durable connection metadata")
            if durable.basis_t() != 0:
                raise RuntimeError("unexpected initial durable basis")
            if durable.tx_count() != 0:
                raise RuntimeError("unexpected initial durable tx count")
            if durable.tx_ids() != []:
                raise RuntimeError("unexpected initial durable tx ids")
            info = durable.info_edn()
            if (
                ":backend :sqlite" not in info
                or ":basis-t 0" not in info
                or ":tx-count 0" not in info
            ):
                raise RuntimeError("unexpected durable connection info")
            with durable.transact_report(
                '[{:db/id 1 :user/name "Durable Ada" :user/email "durable-ada@example.com"}]'
            ) as report:
                if not report.value().get(":ok"):
                    raise RuntimeError("unexpected SQLite transaction report")
            first_durable_basis = durable.basis_t()
            if first_durable_basis == 0:
                raise RuntimeError("unexpected durable basis after first tx")
            if durable.tx_count() != 1:
                raise RuntimeError("unexpected durable tx count after first tx")
            if durable.tx_ids() != [first_durable_basis]:
                raise RuntimeError("unexpected durable tx ids after first tx")
            with vev.tx_builder(1) as bulk_a, vev.tx_builder(1) as bulk_b:
                bulk_a.add_string(2, ":user/name", "Durable Grace")
                bulk_b.add_string(3, ":user/name", "Durable Hedy")
                with durable.transact_bulk([bulk_a, bulk_b]) as report:
                    if not report.value().get(":ok"):
                        raise RuntimeError("unexpected SQLite bulk transaction report")
            if durable.basis_t() != first_durable_basis + 1:
                raise RuntimeError("unexpected durable basis after bulk tx")
            if durable.tx_count() != 2:
                raise RuntimeError("unexpected durable tx count after bulk tx")
            if durable.tx_ids() != [first_durable_basis, first_durable_basis + 1]:
                raise RuntimeError("unexpected durable tx ids after bulk tx")
            with vev.tx_builder(1) as logical_a, vev.tx_builder(1) as logical_b:
                logical_a.add_string(4, ":user/name", "Durable Ada")
                logical_b.add_string(5, ":user/name", "Durable Dorothy")
                with durable.transact_logical_bulk([logical_a, logical_b]) as reports:
                    values = reports.values()
                    if len(values) != 2 or not all(value.get(":ok") for value in values):
                        raise RuntimeError("unexpected SQLite logical group transaction reports")
            with durable.transact_logical_bulk([]) as reports:
                if reports.values() != []:
                    raise RuntimeError("unexpected empty logical group transaction reports")
            with durable.transact_logical(
                [
                    '[{:db/id 6 :user/name "Durable Katherine"}]',
                    '[{:db/id 7 :user/name "Durable Mary"}]',
                ]
            ) as reports:
                values = reports.values()
                if len(values) != 2 or not all(value.get(":ok") for value in values):
                    raise RuntimeError(
                        "unexpected SQLite logical EDN group transaction reports"
                    )
            if durable.basis_t() != first_durable_basis + 5:
                raise RuntimeError("unexpected durable basis after logical group tx")
            if durable.tx_count() != 6:
                raise RuntimeError("unexpected durable tx count after logical group tx")
            if durable.tx_ids() != [first_durable_basis + offset for offset in range(6)]:
                raise RuntimeError("unexpected durable tx ids after logical group tx")
            with durable.prepare(
                "[:find ?e ?email :where [?e :user/email ?email]]"
            ) as all_emails, durable.db() as db:
                rows = all_emails.rows(db)
                print(f"sqlite-live rows: {rows}")
                if len(rows) != 1:
                    raise RuntimeError("unexpected SQLite live row count")

        with vev.connect(sqlite_path) as durable:
            if durable.basis_t() != first_durable_basis + 5:
                raise RuntimeError("unexpected reopened durable basis")
            if durable.tx_count() != 6:
                raise RuntimeError("unexpected reopened durable tx count")
            if durable.tx_ids() != [first_durable_basis + offset for offset in range(6)]:
                raise RuntimeError("unexpected reopened durable tx ids")
            with durable.prepare(
                "[:find ?e ?email :where [?e :user/email ?email]]"
            ) as all_emails, durable.db() as db:
                rows = all_emails.rows(db)
                print(f"sqlite-reopened rows: {rows}")
                if len(rows) != 1:
                    raise RuntimeError("unexpected SQLite reopened row count")
            with durable.prepare(
                "[:find ?email :where [?e :user/email ?email]]"
            ) as email_column_query, durable.db() as db:
                column_rows = db.query_columns(email_column_query)
                if column_rows is None or column_rows.rows() != [
                    ["durable-ada@example.com"]
                ]:
                    raise RuntimeError("unexpected SQLite DB column batch rows")
            with vev.prepare_pull_pattern("[:user/name :user/email]") as pattern:
                with durable.db() as db:
                    pulled = db.pull(pattern, vev.Entity(1))
                    pulled_many = db.pull_many(pattern, [vev.Entity(1)])
                    with db.entity(1) as entity:
                        entity_name = entity[":user/name"]
                        entity_email = entity.get(":user/email")
                if (
                    pulled.get(":user/name") != "Durable Ada"
                    or pulled.get(":user/email") != "durable-ada@example.com"
                ):
                    raise RuntimeError("unexpected SQLite prepared pull")
                if pulled_many != [pulled]:
                    raise RuntimeError("unexpected SQLite prepared pull-many")
                if (
                    entity_name != "Durable Ada"
                    or entity_email != "durable-ada@example.com"
                ):
                    raise RuntimeError("unexpected SQLite entity view")
            with durable.prepare(
                "[:find ?email :in $snap :where [$snap 1 :user/email ?email]]",
                ["$snap"],
            ) as snapshot_source_query, durable.db() as db:
                with snapshot_source_query.statement() as stmt:
                    rows = stmt.bind(vev.DBSource("$snap", db)).rows(db)
                print(f"sqlite-db-source rows: {rows}")
                if rows != [["durable-ada@example.com"]]:
                    raise RuntimeError("unexpected SQLite DB source statement rows")
            with durable.prepare(
                "[:find ?name :in $ % :where (named ?e ?name)]"
            ) as rules_query, durable.db() as db:
                rows = rules_query.rows_with_rules(
                    db,
                    "[[(named ?e ?name) [?e :user/name ?name]]]",
                )
                print(f"sqlite-rules rows: {rows}")
                if rows != [
                    ["Durable Ada"],
                    ["Durable Grace"],
                    ["Durable Hedy"],
                    ["Durable Dorothy"],
                    ["Durable Katherine"],
                    ["Durable Mary"],
                ]:
                    raise RuntimeError("unexpected SQLite rules rows")
    finally:
        remove_sqlite_files(sqlite_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
