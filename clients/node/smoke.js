// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

"use strict";

const vev = require("./vev");
const fs = require("fs");

function mustContain(label, text, ...needles) {
  for (const needle of needles) {
    if (!text.includes(needle)) {
      throw new Error(`${label} missing ${needle} in ${text}`);
    }
  }
}

function removeSqliteFiles(path) {
  for (const suffix of ["", "-wal", "-shm"]) {
    try {
      fs.unlinkSync(`${path}${suffix}`);
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }
}

const conn = vev.createConn();

const tx = conn.transact(`
  [{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
   {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}]
`);
console.log("tx:", tx);
mustContain("tx", tx, ":ok true");

const collection = conn.queryText(`
  [:find ?name
   :in $ [?email ...]
   :where [?e :user/email ?email]
          [?e :user/name ?name]]
`, `[["ada@example.com" "grace@example.com"]]`);
console.log("input-collection:", collection);
mustContain("collection query", collection, `"Ada"`, `"Grace"`);

const oneShotRows = conn.q('[:find ?name :where [?e :user/name ?name]]');
if (!(oneShotRows instanceof Set)) {
  throw new Error("one-shot relation query did not return a Set");
}
const oneShotNames = Array.from(oneShotRows, (row) => row[0]).sort();
if (JSON.stringify(oneShotNames) !== JSON.stringify(["Ada", "Grace"])) {
  throw new Error(`unexpected one-shot query rows: ${JSON.stringify(oneShotRows)}`);
}
const scalarName = conn.q('[:find ?name . :where [1 :user/name ?name]]');
if (scalarName !== "Ada") {
  throw new Error(`unexpected scalar query result: ${scalarName}`);
}

const query = conn.prepare(`
  [:find ?e ?email
   :in $ ?needle
   :where [?e :user/email ?email]
          [(= ?email ?needle)]]
`);

mustContain("prepared AST", query.edn(), ":clauses", ":input-specs");

const prepared = query.query(conn, `["grace@example.com"]`);
console.log("prepared:", prepared);
mustContain("prepared query", prepared, "2", `"grace@example.com"`);

const rows = query.rows(conn, `["grace@example.com"]`);
console.log("typed rows:", rows);
if (rows.length !== 1 || rows[0][0].id !== 2 || rows[0][1] !== "grace@example.com") {
  throw new Error(`unexpected typed rows: ${JSON.stringify(rows)}`);
}

conn.transact(`
  [[:db/add 90 :db/ident :user/email]
   [:db/add 90 :db/unique :db.unique/identity]]
`);

conn.transact(`
  [[:db/add 100 :db/ident :user/friend]
   [:db/add 100 :db/valueType :db.type/ref]
   [:db/add 1 :user/friend 2]]
`);

const pullQuery = conn.prepare(`
  [:find (pull ?e [:user/name {:user/friend [:user/name]}])
   :where [?e :user/name "Ada"]]
`);
const pulled = pullQuery.rows(conn, "[]")[0][0];
console.log("pull:", pulled);
if (pulled[":user/name"] !== "Ada" || pulled[":user/friend"][":user/name"] !== "Grace") {
  throw new Error(`unexpected pull: ${JSON.stringify(pulled)}`);
}
pullQuery.close();

const snapshot = conn.db();
const directPull = snapshot.pull("[:user/name {:user/friend [:user/name]}]", 1);
console.log("direct pull:", directPull);
if (directPull[":user/name"] !== "Ada" || directPull[":user/friend"][":user/name"] !== "Grace") {
  throw new Error(`unexpected direct pull: ${JSON.stringify(directPull)}`);
}
const lookupPull = snapshot.pullLookupRefString("[:user/name]", ":user/email", "ada@example.com");
if (lookupPull[":user/name"] !== "Ada") {
  throw new Error(`unexpected lookup pull: ${JSON.stringify(lookupPull)}`);
}
const manyPull = snapshot.pullMany("[:user/name]", [1, 2]);
const manyNames = manyPull.map((item) => item[":user/name"]).sort();
if (JSON.stringify(manyNames) !== JSON.stringify(["Ada", "Grace"])) {
  throw new Error(`unexpected pull-many: ${JSON.stringify(manyPull)}`);
}

conn.transact(`[{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}]`);

const current = query.query(conn, `["alan@example.com"]`);
const old = snapshot.query(query, `["alan@example.com"]`);
console.log("current-db:", current);
console.log("snapshot-db:", old);
mustContain("current DB query", current, "3", `"alan@example.com"`);
if (old.includes("alan@example.com")) {
  throw new Error("snapshot unexpectedly observed later transaction");
}

const currentRows = query.rows(conn, `["alan@example.com"]`);
const oldRows = snapshot.rows(query, `["alan@example.com"]`);
if (currentRows.length !== 1 || oldRows.length !== 0) {
  throw new Error("unexpected typed snapshot row counts");
}

const withReport = snapshot.withReport(
  `[{:db/id 4 :user/name "Barbara" :user/email "barbara@example.com"}]`,
);
if (!withReport.edn.includes(":ok true")) {
  throw new Error(`unexpected with report: ${withReport.edn}`);
}
const reportBeforeRows = withReport.dbBefore.rows(query, `["barbara@example.com"]`);
const reportAfterRows = withReport.dbAfter.rows(query, `["barbara@example.com"]`);
if (reportBeforeRows.length !== 0 || reportAfterRows.length !== 1) {
  throw new Error("unexpected with report DB rows");
}
withReport.dbBefore.close();
withReport.dbAfter.close();
snapshot.close();

const sqlitePath = "tmp.vev.node.sqlite";
removeSqliteFiles(sqlitePath);
try {
  const durable = vev.connect(sqlitePath);
  if (
    durable.backend() !== "sqlite" ||
    durable.path() !== sqlitePath ||
    durable.basisT() !== 0 ||
    durable.txCount() !== 0
  ) {
    throw new Error("unexpected durable metadata");
  }
  durable.transact(`[{:db/id 1 :user/name "Durable Ada" :user/email "durable-ada@example.com"}]`);
  const firstBasis = durable.basisT();
  if (firstBasis === 0 || durable.txCount() !== 1) {
    throw new Error("unexpected durable metadata after transact");
  }
  const durableQuery = conn.prepare(`[:find ?e ?email :in $ ?needle :where [?e :user/email ?email] [(= ?email ?needle)]]`);
  const durableDb = durable.db();
  const durableRows = durableDb.rows(durableQuery, `["durable-ada@example.com"]`);
  if (durableRows.length !== 1 || durableRows[0][0].id !== 1) {
    throw new Error(`unexpected durable rows: ${JSON.stringify(durableRows)}`);
  }
  durableDb.close();
  durableQuery.close();
  durable.close();
} finally {
  removeSqliteFiles(sqlitePath);
}

query.close();
conn.close();
