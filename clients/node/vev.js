// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

"use strict";

const path = require("path");

function platformId() {
  let os;
  if (process.platform === "darwin") {
    os = "darwin";
  } else if (process.platform === "linux") {
    os = "linux";
  } else if (process.platform === "win32") {
    os = "windows";
  } else {
    os = process.platform;
  }

  let arch;
  if (process.arch === "arm64") {
    arch = "aarch64";
  } else if (process.arch === "x64") {
    arch = "x86_64";
  } else {
    arch = process.arch;
  }
  return `${os}-${arch}`;
}

function nativePath() {
  if (process.env.VEV_NODE_NATIVE) {
    return process.env.VEV_NODE_NATIVE;
  }
  const local = path.join(__dirname, "vev_native.node");
  try {
    return require.resolve(local);
  } catch (_error) {
    return path.join(__dirname, "native", platformId(), "vev_native.node");
  }
}

const nativePathValue = nativePath();
const native = require(nativePathValue);

class Conn {
  constructor(handle) {
    this._handle = handle || native.openMemory();
  }

  close() {
    if (this._handle) {
      native.closeConn(this._handle);
      this._handle = null;
    }
  }

  _requireOpen() {
    if (!this._handle) {
      throw new Error("Vev connection is closed");
    }
  }

  transact(tx) {
    this._requireOpen();
    return native.transact(this._handle, String(tx));
  }

  queryText(query, inputs = "[]") {
    this._requireOpen();
    return native.queryText(this._handle, String(query), String(inputs));
  }

  q(query, inputs = "[]") {
    const db = this.db();
    try {
      return db.q(query, inputs);
    } finally {
      db.close();
    }
  }

  prepare(query) {
    this._requireOpen();
    return new PreparedQuery(native.prepare(String(query)));
  }

  db() {
    this._requireOpen();
    return new DB(native.db(this._handle));
  }
}

class DurableConn {
  constructor(uriOrHandle) {
    this._handle = typeof uriOrHandle === "string"
      ? native.connect(uriOrHandle)
      : uriOrHandle;
  }

  close() {
    if (this._handle) {
      native.closeDurableConn(this._handle);
      this._handle = null;
    }
  }

  _requireOpen() {
    if (!this._handle) {
      throw new Error("Vev durable connection is closed");
    }
  }

  transact(tx) {
    this._requireOpen();
    return native.durableTransact(this._handle, String(tx));
  }

  db() {
    this._requireOpen();
    return new DB(native.durableDb(this._handle));
  }

  q(query, inputs = "[]") {
    const db = this.db();
    try {
      return db.q(query, inputs);
    } finally {
      db.close();
    }
  }

  backend() {
    this._requireOpen();
    return native.durableBackend(this._handle);
  }

  path() {
    this._requireOpen();
    return native.durablePath(this._handle);
  }

  basisT() {
    this._requireOpen();
    return native.durableBasisT(this._handle);
  }

  txCount() {
    this._requireOpen();
    return native.durableTxCount(this._handle);
  }
}

class DB {
  constructor(handle) {
    this._handle = handle;
  }

  close() {
    if (this._handle) {
      native.closeDb(this._handle);
      this._handle = null;
    }
  }

  _requireOpen() {
    if (!this._handle) {
      throw new Error("Vev DB snapshot is closed");
    }
  }

  query(query, inputs = "[]") {
    this._requireOpen();
    query._requireOpen();
    return native.dbQueryPrepared(this._handle, query._handle, String(inputs));
  }

  rows(query, inputs = "[]") {
    this._requireOpen();
    query._requireOpen();
    return native.dbQueryPreparedRows(this._handle, query._handle, String(inputs));
  }

  q(query, inputs = "[]") {
    this._requireOpen();
    return native.dbQ(this._handle, String(query), String(inputs));
  }

  withReport(tx) {
    this._requireOpen();
    const report = native.dbWithReport(this._handle, String(tx));
    return {
      edn: report.edn,
      dbBefore: new DB(report.dbBefore),
      dbAfter: new DB(report.dbAfter),
    };
  }

  pull(pattern, entity) {
    this._requireOpen();
    return native.pull(this._handle, String(pattern), Number(entity));
  }

  pullLookupRefString(pattern, attr, value) {
    this._requireOpen();
    return native.pullLookupRefString(
      this._handle,
      String(pattern),
      String(attr),
      String(value),
    );
  }

  pullMany(pattern, entities) {
    this._requireOpen();
    return native.pullMany(this._handle, String(pattern), entities.map(Number));
  }
}

class PreparedQuery {
  constructor(handle) {
    this._handle = handle;
  }

  close() {
    if (this._handle) {
      native.closePreparedQuery(this._handle);
      this._handle = null;
    }
  }

  _requireOpen() {
    if (!this._handle) {
      throw new Error("Vev prepared query is closed");
    }
  }

  query(conn, inputs = "[]") {
    this._requireOpen();
    conn._requireOpen();
    return native.queryPrepared(conn._handle, this._handle, String(inputs));
  }

  rows(conn, inputs = "[]") {
    this._requireOpen();
    conn._requireOpen();
    return native.queryPreparedRows(conn._handle, this._handle, String(inputs));
  }

  edn() {
    this._requireOpen();
    return native.preparedQueryEdn(this._handle);
  }
}

function openMemory() {
  return new Conn();
}

function createConn() {
  return new Conn();
}

function connect(uri) {
  return new DurableConn(String(uri));
}

function q(query, source, inputs = "[]") {
  if (source instanceof DB || source instanceof Conn || source instanceof DurableConn) {
    return source.q(query, inputs);
  }
  throw new Error("vev.q expects a DB, Conn, or DurableConn");
}

module.exports = {
  Conn,
  DurableConn,
  DB,
  PreparedQuery,
  connect,
  createConn,
  openMemory,
  q,
};
