// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package com.vevdb.examples;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Arrays;
import java.util.Map;
import com.vevdb.Vev;

public final class Smoke {
    private static void deleteSqliteFiles(Path path) throws Exception {
        Files.deleteIfExists(path);
        Files.deleteIfExists(Path.of(path.toString() + "-wal"));
        Files.deleteIfExists(Path.of(path.toString() + "-shm"));
    }

    public static void main(String[] args) throws Throwable {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: Smoke <path-to-native-library>");
        }

        Vev vev = Vev.load(Path.of(args[0]));
        try (Vev.Connection conn = vev.createConn()) {
            String tx = conn.transact("""
                [{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
                 {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}]
                """);
            System.out.println("tx: " + tx);

            String collectionText = conn.queryText("""
                [:find ?name
                 :in $ [?email ...]
                 :where [?e :user/email ?email]
                        [?e :user/name ?name]]
                """, "[[\"ada@example.com\" \"grace@example.com\"]]");
            System.out.println("input-collection: " + collectionText);
            if (!collectionText.contains("\"Ada\"") || !collectionText.contains("\"Grace\"")) {
                throw new IllegalStateException("unexpected collection query output");
            }

            try (Vev.DB db = conn.db()) {
                List<List<Object>> requestRows = vev.queryRows(Map.of(
                    "query", """
                        [:find ?name
                         :in $ ?email
                         :where [?e :user/email ?email]
                                [?e :user/name ?name]]
                        """,
                    "args", List.of(db, "ada@example.com")));
                System.out.println("query request rows: " + requestRows);
                if (!requestRows.equals(List.of(List.of("Ada")))) {
                    throw new IllegalStateException("unexpected query request rows");
                }

                List<Map<Object, Object>> requestMaps = vev.queryMaps(Map.of(
                    "query", """
                        [:find ?name ?email
                         :keys name email
                         :in $ ?email
                         :where [?e :user/email ?email]
                                [?e :user/name ?name]]
                        """,
                    "args", List.of(db, "ada@example.com")));
                System.out.println("query request maps: " + requestMaps);
                if (!requestMaps.equals(List.of(Map.of(
                        new Vev.Keyword(":name"), "Ada",
                        new Vev.Keyword(":email"), "ada@example.com")))) {
                    throw new IllegalStateException("unexpected query request maps");
                }
            }

            conn.transact("""
                [[:db/add 90 :db/ident :user/email]
                 [:db/add 90 :db/unique :db.unique/identity]]
                """);

            conn.transact("""
                [[:db/add 91 :db/ident :user/status]
                 [:db/add 91 :db/unique :db.unique/identity]
                 [:db/add 92 :db/ident :user/code]
                 [:db/add 92 :db/unique :db.unique/identity]
                 [:db/add 1 :user/status :active]
                 [:db/add 2 :user/status :inactive]
                 [:db/add 1 :user/code 1001]
                 [:db/add 2 :user/code 1002]]
                """);

            conn.transact("""
                [[:db/add 100 :db/ident :user/friend]
                 [:db/add 100 :db/valueType :db.type/ref]
                 [:db/add 1 :user/friend 2]]
                """);

            try (Vev.PreparedQuery emailQuery = vev.prepare("""
                    [:find ?e ?email
                     :in $ ?needle
                     :where [?e :user/email ?email]
                            [(= ?email ?needle)]]
                    """);
                 Vev.Statement stmt = emailQuery.statement()) {
                String preparedAst = emailQuery.edn();
                if (!preparedAst.contains(":clauses") || !preparedAst.contains(":input-specs")) {
                    throw new IllegalStateException("prepared query AST did not expose parser keys");
                }
                String clauseAst = vev.parseClauseEdn("[?e :user/email ?email]");
                if (!clauseAst.contains(":clauses") || !clauseAst.contains(":user/email")) {
                    throw new IllegalStateException("parse-clause AST did not expose parser keys");
                }

                try (Vev.ResultSet result = conn.query(stmt.bindString("grace@example.com"))) {
                    List<List<Object>> rows = result.rows();
                    System.out.println("statement rows: " + rows);
                    if (!rows.equals(List.of(List.of(new Vev.Entity(2), "grace@example.com")))) {
                        throw new IllegalStateException("unexpected statement rows");
                    }
                }

                try (Vev.PreparedQuery collectionQuery = vev.prepare("""
                        [:find ?name
                         :in $ [?email ...]
                         :where [?e :user/email ?email]
                                [?e :user/name ?name]]
                        """);
                     Vev.Statement collectionStmt = collectionQuery.statement()) {
                    try (Vev.ResultSet result = conn
                            .query(collectionStmt.bindStringCollection("ada@example.com", "grace@example.com"))) {
                        List<List<Object>> collectionRows = result.rows();
                        List<String> names = new ArrayList<>();
                        for (List<Object> row : collectionRows) {
                            names.add((String) row.get(0));
                        }
                        Collections.sort(names);
                        System.out.println("statement collection names: " + names);
                        if (!names.equals(List.of("Ada", "Grace"))) {
                            throw new IllegalStateException("unexpected collection statement rows");
                        }
                    }
                }

                try (Vev.PreparedQuery nameQuery = vev.prepare("""
                        [:find ?name
                         :in $ ?email
                         :where [?e :user/email ?email]
                                [?e :user/name ?name]]
                        """);
                     Vev.Statement nameStmt = nameQuery.statement();
                     Vev.DB snapshot = conn.db()) {
                    Vev.ColumnResult nameColumns = snapshot.queryColumns(nameStmt.bindString("grace@example.com"));
                    if (nameColumns == null
                            || nameColumns.rowCount() != 1
                            || !Arrays.equals(nameColumns.kinds(), new int[] { Vev.COLUMN_STRING })
                            || !Arrays.equals((String[]) nameColumns.columns()[0], new String[] { "Grace" })) {
                        throw new IllegalStateException("unexpected statement column batch");
                    }
                }

                try (Vev.PreparedQuery pullQuery = vev.prepare("""
                        [:find (pull ?e [:user/name {:user/friend [:user/name]}])
                         :where [?e :user/name "Ada"]]
                        """)) {
                    try (Vev.ResultSet result = conn.query(pullQuery, "[]")) {
                        Vev.MapValue pulled = (Vev.MapValue) result.scalar();
                        System.out.println("pull: " + pulled);
                        Object friend = pulled.get(":user/friend");
                        if (!"Ada".equals(pulled.get(":user/name"))
                            || !(friend instanceof Vev.MapValue friendMap)
                            || !"Grace".equals(friendMap.get(":user/name"))) {
                            throw new IllegalStateException("unexpected pull result");
                        }
                    }
                    try (Vev.DB snapshot = conn.db()) {
                        Vev.ColumnResult pullColumns = snapshot.queryColumns(pullQuery, "[]");
                        if (pullColumns == null
                                || pullColumns.rowCount() != 1
                                || !Arrays.equals(pullColumns.kinds(), new int[] { Vev.COLUMN_VALUE })) {
                            throw new IllegalStateException("unexpected pull column batch shape");
                        }
                        Object[] pulledValues = (Object[]) pullColumns.columns()[0];
                        if (!(pulledValues[0] instanceof Vev.MapValue pulled)
                                || !"Ada".equals(pulled.get(":user/name"))
                                || !(pulled.get(":user/friend") instanceof Vev.MapValue friendMap)
                                || !"Grace".equals(friendMap.get(":user/name"))) {
                            throw new IllegalStateException("unexpected pull column batch");
                        }
                    }
                }

                try (Vev.DB pullDb = conn.db()) {
                    Vev.MapValue directPull = (Vev.MapValue) pullDb.pull(
                        "[:user/name {:user/friend [:user/name]}]",
                        1);
                    System.out.println("direct pull: " + directPull);
                    Object friend = directPull.get(":user/friend");
                    if (!"Ada".equals(directPull.get(":user/name"))
                        || !(friend instanceof Vev.MapValue friendMap)
                        || !"Grace".equals(friendMap.get(":user/name"))) {
                        throw new IllegalStateException("unexpected direct pull");
                    }

                    Vev.MapValue lookupPull = (Vev.MapValue) pullDb.pullLookupRefString(
                        "[:user/name]",
                        ":user/email",
                        "ada@example.com");
                    System.out.println("lookup pull: " + lookupPull);
                    if (!"Ada".equals(lookupPull.get(":user/name"))) {
                        throw new IllegalStateException("unexpected lookup-ref pull");
                    }

                    Vev.MapValue keywordLookupPull = (Vev.MapValue) pullDb.pullLookupRefKeyword(
                        "[:user/name]",
                        ":user/status",
                        ":active");
                    Vev.MapValue intLookupPull = (Vev.MapValue) pullDb.pullLookupRefInt(
                        "[:user/name]",
                        ":user/code",
                        1001);
                    if (!"Ada".equals(keywordLookupPull.get(":user/name"))
                        || !"Ada".equals(intLookupPull.get(":user/name"))) {
                        throw new IllegalStateException("unexpected typed lookup-ref pull");
                    }

                    @SuppressWarnings("unchecked")
                    List<Object> manyPull = (List<Object>) pullDb.pullMany("[:user/name]", 1, 2);
                    List<String> pullNames = new ArrayList<>();
                    for (Object item : manyPull) {
                        pullNames.add((String) ((Vev.MapValue) item).get(":user/name"));
                    }
                    Collections.sort(pullNames);
                    System.out.println("pull many: " + manyPull);
                    if (!pullNames.equals(List.of("Ada", "Grace"))) {
                        throw new IllegalStateException("unexpected pull-many");
                    }

                    @SuppressWarnings("unchecked")
                    List<Object> manyLookupPull = (List<Object>) pullDb.pullManyLookupRefString(
                        "[:user/name]",
                        ":user/email",
                        "ada@example.com",
                        "missing@example.com",
                        "grace@example.com");
                    if (manyLookupPull.size() != 3
                        || !"Ada".equals(((Vev.MapValue) manyLookupPull.get(0)).get(":user/name"))
                        || manyLookupPull.get(1) != null
                        || !"Grace".equals(((Vev.MapValue) manyLookupPull.get(2)).get(":user/name"))) {
                        throw new IllegalStateException("unexpected pull-many lookup-ref");
                    }
                }

                try (Vev.PreparedQuery pullPatternQuery = vev.prepare("""
                        [:find (pull ?e ?pattern)
                         :in $ ?pattern ?name
                         :where [?e :user/name ?name]]
                        """);
                     Vev.PreparedPullPattern preparedPattern =
                         vev.preparePullPattern("[:user/name {:user/friend [:user/name]}]");
                     Vev.Statement pullPatternStmt = pullPatternQuery.statement();
                     Vev.ResultSet result = conn.query(
                         pullPatternStmt.bindPullPatternAndString(
                             "[:user/name {:user/friend [:user/name]}]",
                             "Ada"))) {
                    String preparedPatternEdn = preparedPattern.edn();
                    if (!preparedPatternEdn.contains(":pattern")
                        || !preparedPatternEdn.contains(":attr")
                        || !preparedPatternEdn.contains(":nested-count")) {
                        throw new IllegalStateException("unexpected prepared pull pattern EDN: " + preparedPatternEdn);
                    }
                    Vev.MapValue pulled = (Vev.MapValue) result.scalar();
                    System.out.println("statement pull pattern: " + pulled);
                    Object friend = pulled.get(":user/friend");
                    if (!"Ada".equals(pulled.get(":user/name"))
                        || !(friend instanceof Vev.MapValue friendMap)
                        || !"Grace".equals(friendMap.get(":user/name"))) {
                        throw new IllegalStateException("unexpected statement pull pattern");
                    }
                }

                try (Vev.PreparedQuery allEmails = vev.prepare("[:find ?e ?email :where [?e :user/email ?email]]");
                     Vev.DB snapshot = conn.db()) {
                    long snapshotBasis = snapshot.basisT();
                    if (snapshotBasis == 0
                        || snapshot.nextT() != snapshotBasis + 1
                        || snapshot.asOfT() != null
                        || snapshot.sinceT() != null
                        || snapshot.isHistory()) {
                        throw new IllegalStateException("unexpected current DB metadata");
                    }
                    try (Vev.DB earlier = snapshot.asOf(1);
                         Vev.DB recent = snapshot.since(1);
                         Vev.DB audit = snapshot.history()) {
                        if (earlier.basisT() != snapshotBasis
                            || !Long.valueOf(1).equals(earlier.asOfT())
                            || !Long.valueOf(1).equals(recent.sinceT())
                            || !audit.isHistory()) {
                            throw new IllegalStateException("unexpected filtered DB metadata");
                        }
                    }
                    try (Vev.Log log = conn.log()) {
                        Object range = log.txRange(null, null);
                        if (!(range instanceof List<?> transactions)
                            || transactions.size() != snapshotBasis) {
                            throw new IllegalStateException("unexpected resident transaction range");
                        }
                    }
                    conn.transact("[{:db/id 3 :user/name \"Alan\" :user/email \"alan@example.com\"}]");
                    try (Vev.ResultSet current = conn.query(allEmails, "[]");
                         Vev.ResultSet old = snapshot.query(allEmails, "[]")) {
                        int currentRows = current.rowCount();
                        int snapshotRows = old.rowCount();
                        System.out.println("current-db rows: " + currentRows);
                        System.out.println("snapshot-db rows: " + snapshotRows);
                        if (currentRows != 3 || snapshotRows != 2) {
                            throw new IllegalStateException("unexpected snapshot row counts");
                        }
                    }

                    try (Vev.ResultSet result = snapshot.query(stmt.bindString("ada@example.com"))) {
                        List<List<Object>> snapshotStmtRows = result.rows();
                        if (!snapshotStmtRows.equals(List.of(List.of(new Vev.Entity(1), "ada@example.com")))) {
                            throw new IllegalStateException("unexpected snapshot statement rows");
                        }
                    }
                }
            }

            Path sqlitePath = Path.of("tmp.vev.java.sqlite");
            deleteSqliteFiles(sqlitePath);
            long firstDurableBasis = 0;
            try {
                try (Vev.DurableConnection durable = vev.connect(sqlitePath)) {
                    if (!"sqlite".equals(durable.backend()) || !sqlitePath.toString().equals(durable.path())) {
                        throw new IllegalStateException("unexpected durable connection metadata");
                    }
                    if (durable.basisT() != 0) {
                        throw new IllegalStateException("unexpected initial durable basis");
                    }
                    if (durable.txCount() != 0) {
                        throw new IllegalStateException("unexpected initial durable tx count");
                    }
                    if (!Arrays.equals(durable.txIds(), new long[]{})) {
                        throw new IllegalStateException("unexpected initial durable tx ids");
                    }
                    String info = durable.infoEdn();
                    if (!info.contains(":backend :sqlite") || !info.contains(":basis-t 0") || !info.contains(":tx-count 0")) {
                        throw new IllegalStateException("unexpected durable connection info");
                    }
                    try (Vev.TxReport report = durable.transactReport("""
                            [{:db/id 1
                              :user/name "Durable Ada"
                              :user/email "durable-ada@example.com"}]
                            """)) {
                        Vev.MapValue reportValue = (Vev.MapValue) report.value();
                        if (!Boolean.TRUE.equals(reportValue.get(":ok"))) {
                            throw new IllegalStateException("unexpected SQLite transaction report");
                        }
                    }
                    firstDurableBasis = durable.basisT();
                    if (firstDurableBasis == 0) {
                        throw new IllegalStateException("unexpected durable basis after first tx");
                    }
                    if (durable.txCount() != 1) {
                        throw new IllegalStateException("unexpected durable tx count after first tx");
                    }
                    if (!Arrays.equals(durable.txIds(), new long[]{firstDurableBasis})) {
                        throw new IllegalStateException("unexpected durable tx ids after first tx");
                    }
                    try (Vev.TxBuilder bulkA = vev.txBuilder(1);
                         Vev.TxBuilder bulkB = vev.txBuilder(1)) {
                        bulkA.addString(2, ":user/name", "Durable Grace");
                        bulkB.addString(3, ":user/name", "Durable Hedy");
                        try (Vev.TxReport report = durable.transactReport(List.of(bulkA, bulkB))) {
                            Vev.MapValue reportValue = (Vev.MapValue) report.value();
                            if (!Boolean.TRUE.equals(reportValue.get(":ok"))) {
                                throw new IllegalStateException("unexpected durable bulk builder report");
                            }
                        }
                    }
                    if (durable.basisT() != firstDurableBasis + 1) {
                        throw new IllegalStateException("unexpected durable basis after bulk builder tx");
                    }
                    if (durable.txCount() != 2) {
                        throw new IllegalStateException("unexpected durable tx count after bulk builder tx");
                    }
                    if (!Arrays.equals(durable.txIds(), new long[]{firstDurableBasis, firstDurableBasis + 1})) {
                        throw new IllegalStateException("unexpected durable tx ids after bulk builder tx");
                    }
                    try (Vev.TxBuilder logicalA = vev.txBuilder(1);
                         Vev.TxBuilder logicalB = vev.txBuilder(1)) {
                        logicalA.addString(4, ":user/name", "Durable Ada");
                        logicalB.addString(5, ":user/name", "Durable Dorothy");
                        try (Vev.TxReportArray reports = durable.transactLogicalReports(List.of(logicalA, logicalB))) {
                            List<Object> values = reports.values();
                            if (values.size() != 2) {
                                throw new IllegalStateException("unexpected logical group report count");
                            }
                            for (Object value : values) {
                                Vev.MapValue reportValue = (Vev.MapValue) value;
                                if (!Boolean.TRUE.equals(reportValue.get(":ok"))) {
                                    throw new IllegalStateException("unexpected durable logical group report");
                                }
                            }
                        }
                    }
                    try (Vev.TxReportArray reports = durable.transactLogicalReports(List.of())) {
                        if (!reports.values().isEmpty()) {
                            throw new IllegalStateException("unexpected empty logical group reports");
                        }
                    }
                    try (Vev.TxReportArray reports = durable.transactLogicalEdnReports(List.of(
                            "[{:db/id 6 :user/name \"Durable Katherine\"}]",
                            "[{:db/id 7 :user/name \"Durable Mary\"}]"))) {
                        List<Object> values = reports.values();
                        if (values.size() != 2) {
                            throw new IllegalStateException("unexpected logical EDN group report count");
                        }
                        for (Object value : values) {
                            Vev.MapValue reportValue = (Vev.MapValue) value;
                            if (!Boolean.TRUE.equals(reportValue.get(":ok"))) {
                                throw new IllegalStateException("unexpected durable logical EDN group report");
                            }
                        }
                    }
                    if (durable.basisT() != firstDurableBasis + 5) {
                        throw new IllegalStateException("unexpected durable basis after logical group tx");
                    }
                    if (durable.txCount() != 6) {
                        throw new IllegalStateException("unexpected durable tx count after logical group tx");
                    }
                    if (!Arrays.equals(durable.txIds(), new long[]{firstDurableBasis, firstDurableBasis + 1, firstDurableBasis + 2, firstDurableBasis + 3, firstDurableBasis + 4, firstDurableBasis + 5})) {
                        throw new IllegalStateException("unexpected durable tx ids after logical group tx");
                    }
                    if (!durable.compactIndexes()) {
                        throw new IllegalStateException("durable index compaction failed");
                    }
                    try (Vev.PreparedQuery durableQuery = vev.prepare("[:find ?e ?email :where [?e :user/email ?email]]");
                         Vev.DB durableDb = durable.db();
                         Vev.ResultSet rows = durableDb.query(durableQuery, "[]")) {
                        System.out.println("sqlite-live rows: " + rows.rowCount());
                        if (rows.rowCount() != 1) {
                            throw new IllegalStateException("unexpected SQLite live row count");
                        }
                    }
                }

                try (Vev.DurableConnection durable = vev.connect(sqlitePath);
                     Vev.PreparedQuery durableQuery = vev.prepare("[:find ?e ?email :where [?e :user/email ?email]]");
                     Vev.DB durableDb = durable.db();
                     Vev.ResultSet rows = durableDb.query(durableQuery, "[]")) {
                    if (durable.basisT() != firstDurableBasis + 5) {
                        throw new IllegalStateException("unexpected reopened durable basis");
                    }
                    if (durable.txCount() != 6) {
                        throw new IllegalStateException("unexpected reopened durable tx count");
                    }
                    if (!Arrays.equals(durable.txIds(), new long[]{firstDurableBasis, firstDurableBasis + 1, firstDurableBasis + 2, firstDurableBasis + 3, firstDurableBasis + 4, firstDurableBasis + 5})) {
                        throw new IllegalStateException("unexpected reopened durable tx ids");
                    }
                    System.out.println("sqlite-reopened rows: " + rows.rowCount());
                    if (rows.rowCount() != 1) {
                        throw new IllegalStateException("unexpected SQLite reopened row count");
                    }
                }
            } finally {
                deleteSqliteFiles(sqlitePath);
            }
        } finally {
            vev.close();
        }
    }
}
