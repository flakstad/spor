// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

export class Conn {
  close(): void;
  transact(tx: string): string;
  queryText(query: string, inputs?: string): string;
  q(query: string, inputs?: string): unknown[][];
  prepare(query: string): PreparedQuery;
  db(): DB;
}

export class DurableConn {
  constructor(uri: string);
  close(): void;
  transact(tx: string): string;
  q(query: string, inputs?: string): unknown[][];
  db(): DB;
  backend(): string;
  path(): string;
  basisT(): number;
  txCount(): number;
}

export class DB {
  close(): void;
  query(query: PreparedQuery, inputs?: string): string;
  rows(query: PreparedQuery, inputs?: string): unknown[][];
  q(query: string, inputs?: string): unknown[][];
  withReport(tx: string): { edn: string; dbBefore: DB; dbAfter: DB };
  asOf(timePoint: number | bigint | Date): DB;
  since(timePoint: number | bigint | Date): DB;
  history(): DB;
  pull(pattern: string, entity: number): unknown;
  pullLookupRefString(pattern: string, attr: string, value: string): unknown;
  pullMany(pattern: string, entities: number[]): unknown[];
}

export class PreparedQuery {
  close(): void;
  query(conn: Conn, inputs?: string): string;
  rows(conn: Conn, inputs?: string): unknown[][];
}

export function connect(uri: string): DurableConn;
export function createConn(): Conn;
/** Compatibility alias for createConn(). */
export function openMemory(): Conn;
export function q(query: string, source: Conn | DurableConn | DB, inputs?: string): unknown;
