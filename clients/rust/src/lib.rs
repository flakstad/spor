// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_int, c_longlong, c_ulonglong, c_void};
use std::ptr;
use std::slice;
use std::time::{SystemTime, UNIX_EPOCH};

type VevConn = *mut c_void;
type VevConnection = *mut c_void;
type VevColumnBatch = *mut c_void;
type VevDb = *mut c_void;
type VevEntity = *mut c_void;
type VevPreparedQuery = *mut c_void;
type VevPreparedPullPattern = *mut c_void;
type VevResult = *mut c_void;
type VevStmt = *mut c_void;
type VevTxBuilder = *mut c_void;
type VevTxReport = *mut c_void;
type VevTxReportArray = *mut c_void;
type VevU64Array = *mut c_void;
type VevValue = *const c_void;
type VevValueHandle = *mut c_void;

const VEV_VALUE_NIL: c_int = 0;
const VEV_VALUE_ENTITY: c_int = 1;
const VEV_VALUE_STRING: c_int = 2;
const VEV_VALUE_INT: c_int = 3;
const VEV_VALUE_FLOAT: c_int = 4;
const VEV_VALUE_BOOL: c_int = 5;
const VEV_VALUE_KEYWORD: c_int = 6;
const VEV_VALUE_SYMBOL: c_int = 7;
const VEV_VALUE_VECTOR: c_int = 8;
const VEV_VALUE_MAP: c_int = 9;
const VEV_VALUE_UUID: c_int = 10;
const VEV_VALUE_SET: c_int = 11;
const VEV_VALUE_INSTANT: c_int = 12;

const VEV_COLUMN_BATCH_ENTITY: c_int = 1;
const VEV_COLUMN_BATCH_STRING: c_int = 2;
const VEV_COLUMN_BATCH_ENTITY_INT: c_int = 3;
const VEV_COLUMN_BATCH_ENTITY_STRING_INT: c_int = 4;
const VEV_COLUMN_BATCH_INT: c_int = 5;
const VEV_COLUMN_BATCH_ENTITY_STRING: c_int = 6;
const VEV_COLUMN_BATCH_STRING_INT: c_int = 7;
const VEV_COLUMN_BATCH_STRING_STRING: c_int = 8;

pub const VEV_COLUMN_ENTITY: c_int = 1;
pub const VEV_COLUMN_STRING: c_int = 2;
pub const VEV_COLUMN_INT: c_int = 3;

fn system_time_millis(time_point: SystemTime) -> Result<i64, String> {
    match time_point.duration_since(UNIX_EPOCH) {
        Ok(duration) => i64::try_from(duration.as_millis())
            .map_err(|_| "time point is outside the signed millisecond range".to_string()),
        Err(error) => {
            let nanos = error.duration().as_nanos();
            let millis = i64::try_from((nanos + 999_999) / 1_000_000)
                .map_err(|_| "time point is outside the signed millisecond range".to_string())?;
            Ok(-millis)
        }
    }
}

#[link(name = "vev")]
unsafe extern "C" {
    fn vev_version() -> *const c_char;

    fn vev_conn_open_memory() -> VevConn;
    fn vev_conn_close(conn: VevConn);
    fn vev_conn_db(conn: VevConn) -> VevDb;
    fn vev_conn_from_db(db: VevDb) -> VevConn;
    fn vev_connect(path: *const c_char) -> VevConnection;
    fn vev_connection_ok(conn: VevConnection) -> bool;
    fn vev_connection_error(conn: VevConnection) -> *const c_char;
    fn vev_connection_backend(conn: VevConnection) -> *const c_char;
    fn vev_connection_path(conn: VevConnection) -> *const c_char;
    fn vev_connection_basis_t(conn: VevConnection) -> c_ulonglong;
    fn vev_connection_tx_count(conn: VevConnection) -> c_ulonglong;
    fn vev_connection_tx_ids(conn: VevConnection) -> VevU64Array;
    fn vev_connection_info_edn(conn: VevConnection) -> *const c_char;
    fn vev_connection_close(conn: VevConnection);
    fn vev_connection_db(conn: VevConnection) -> VevDb;
    fn vev_connection_transact_edn_report(
        conn: VevConnection,
        tx_text: *const c_char,
    ) -> VevTxReport;
    fn vev_connection_tx_commit_many_report(
        conn: VevConnection,
        builders: *const VevTxBuilder,
        builder_count: c_int,
    ) -> VevTxReport;
    fn vev_connection_tx_commit_logical_many_reports(
        conn: VevConnection,
        builders: *const VevTxBuilder,
        builder_count: c_int,
    ) -> VevTxReportArray;
    fn vev_connection_transact_many_edn_reports(
        conn: VevConnection,
        tx_texts: *const *const c_char,
        tx_count: c_int,
    ) -> VevTxReportArray;
    fn vev_db_release(db: VevDb);
    fn vev_db_as_of(db: VevDb, tx: c_ulonglong) -> VevDb;
    fn vev_db_as_of_instant_millis(db: VevDb, unix_millis: c_longlong) -> VevDb;
    fn vev_db_since(db: VevDb, tx: c_ulonglong) -> VevDb;
    fn vev_db_since_instant_millis(db: VevDb, unix_millis: c_longlong) -> VevDb;
    fn vev_db_history(db: VevDb) -> VevDb;
    fn vev_u64_array_free(array: VevU64Array);
    fn vev_u64_array_count(array: VevU64Array) -> c_int;
    fn vev_u64_array_value(array: VevU64Array, index: c_int) -> c_ulonglong;
    fn vev_with_edn_report(db: VevDb, tx_text: *const c_char) -> VevTxReport;
    fn vev_db_with_edn(db: VevDb, tx_text: *const c_char) -> VevDb;
    fn vev_db_entity(db: VevDb, entity: c_ulonglong) -> VevEntity;
    fn vev_db_entity_lookup_ref_string(
        db: VevDb,
        attr: *const c_char,
        value: *const c_char,
    ) -> VevEntity;
    fn vev_db_entity_ident(db: VevDb, ident: *const c_char) -> VevEntity;
    fn vev_entity_free(entity: VevEntity);
    fn vev_entity_found(entity: VevEntity) -> bool;
    fn vev_entity_id(entity: VevEntity) -> c_ulonglong;
    fn vev_entity_contains(entity: VevEntity, attr: *const c_char) -> bool;
    fn vev_entity_get(entity: VevEntity, attr: *const c_char) -> VevValueHandle;
    fn vev_entity_values(entity: VevEntity, attr: *const c_char) -> VevValueHandle;
    fn vev_entity_ref(entity: VevEntity, attr: *const c_char) -> VevEntity;
    fn vev_entity_refs(entity: VevEntity, attr: *const c_char) -> VevU64Array;
    fn vev_entity_touch(entity: VevEntity) -> VevValueHandle;

    fn vev_string_free(text: *const c_char);

    fn vev_transact_edn(conn: VevConn, tx_text: *const c_char) -> *const c_char;
    fn vev_transact_edn_report(conn: VevConn, tx_text: *const c_char) -> VevTxReport;
    fn vev_tx_report_free(report: VevTxReport);
    fn vev_tx_report_value(report: VevTxReport) -> VevValue;
    fn vev_tx_report_edn(report: VevTxReport) -> *const c_char;
    fn vev_tx_report_db_before(report: VevTxReport) -> VevDb;
    fn vev_tx_report_db_after(report: VevTxReport) -> VevDb;
    fn vev_tx_report_array_free(array: VevTxReportArray);
    fn vev_tx_report_array_count(array: VevTxReportArray) -> c_int;
    fn vev_tx_report_array_get(array: VevTxReportArray, index: c_int) -> VevTxReport;
    fn vev_tx_create(capacity: c_int) -> VevTxBuilder;
    fn vev_tx_free(builder: VevTxBuilder);
    fn vev_tx_add_string(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: *const c_char,
    ) -> bool;
    fn vev_tx_add_keyword(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: *const c_char,
    ) -> bool;
    fn vev_tx_add_symbol(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: *const c_char,
    ) -> bool;
    fn vev_tx_add_entity(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: c_ulonglong,
    ) -> bool;
    fn vev_tx_add_int(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: c_longlong,
    ) -> bool;
    fn vev_tx_add_bool(
        builder: VevTxBuilder,
        entity: c_ulonglong,
        attr: *const c_char,
        value: bool,
    ) -> bool;
    fn vev_query_edn_with_inputs(
        conn: VevConn,
        query_text: *const c_char,
        inputs_text: *const c_char,
    ) -> *const c_char;

    fn vev_prepare_query_edn(query_text: *const c_char) -> VevPreparedQuery;
    fn vev_prepared_query_edn(query: VevPreparedQuery) -> *const c_char;
    fn vev_parse_clause_edn(clause_text: *const c_char) -> *const c_char;
    fn vev_prepared_query_free(query: VevPreparedQuery);

    fn vev_stmt_create(query: VevPreparedQuery) -> VevStmt;
    fn vev_stmt_clear(stmt: VevStmt);
    fn vev_stmt_free(stmt: VevStmt);
    fn vev_stmt_bind_string(stmt: VevStmt, value: *const c_char) -> bool;
    fn vev_stmt_bind_string_collection(
        stmt: VevStmt,
        values: *const *const c_char,
        value_count: c_int,
    ) -> bool;
    fn vev_stmt_bind_pull_pattern_edn(stmt: VevStmt, pattern_text: *const c_char) -> bool;

    fn vev_query_stmt_result(conn: VevConn, stmt: VevStmt) -> VevResult;
    fn vev_query_db_stmt_result(db: VevDb, stmt: VevStmt) -> VevResult;
    fn vev_query_stmt_column_batch(conn: VevConn, stmt: VevStmt) -> VevColumnBatch;
    fn vev_query_db_stmt_column_batch(db: VevDb, stmt: VevStmt) -> VevColumnBatch;
    fn vev_query_prepared_result_with_inputs(
        conn: VevConn,
        query: VevPreparedQuery,
        inputs_text: *const c_char,
    ) -> VevResult;
    fn vev_query_db_prepared_result_with_inputs(
        db: VevDb,
        query: VevPreparedQuery,
        inputs_text: *const c_char,
    ) -> VevResult;
    fn vev_db_query_value_with_inputs(
        db: VevDb,
        query_text: *const c_char,
        inputs_text: *const c_char,
    ) -> VevValueHandle;
    fn vev_query_db_prepared_column_batch_with_inputs(
        db: VevDb,
        query: VevPreparedQuery,
        inputs_text: *const c_char,
    ) -> VevColumnBatch;
    fn vev_column_batch_free(batch: VevColumnBatch);
    fn vev_column_batch_kind(batch: VevColumnBatch) -> c_int;
    fn vev_column_batch_count(batch: VevColumnBatch) -> c_int;
    fn vev_column_batch_entities_data(batch: VevColumnBatch) -> *const c_ulonglong;
    fn vev_column_batch_ints_data(batch: VevColumnBatch) -> *const i64;
    fn vev_column_batch_string_data_array(batch: VevColumnBatch) -> *const *const c_void;
    fn vev_column_batch_string_lengths_data(batch: VevColumnBatch) -> *const c_int;
    fn vev_column_batch_second_string_data_array(batch: VevColumnBatch) -> *const *const c_void;
    fn vev_column_batch_second_string_lengths_data(batch: VevColumnBatch) -> *const c_int;
    fn vev_column_batch_string_dictionary_count(batch: VevColumnBatch) -> c_int;
    fn vev_column_batch_string_dictionary_data_array(batch: VevColumnBatch)
        -> *const *const c_void;
    fn vev_column_batch_string_dictionary_lengths_data(batch: VevColumnBatch) -> *const c_int;
    fn vev_column_batch_string_indices_data(batch: VevColumnBatch) -> *const c_int;
    fn vev_pull_edn(db: VevDb, pattern_text: *const c_char, entity: c_ulonglong) -> VevValueHandle;
    fn vev_prepare_pull_pattern_edn(pattern_text: *const c_char) -> VevPreparedPullPattern;
    fn vev_prepared_pull_pattern_ok(pattern: VevPreparedPullPattern) -> bool;
    fn vev_prepared_pull_pattern_error(pattern: VevPreparedPullPattern) -> *const c_char;
    fn vev_prepared_pull_pattern_edn(pattern: VevPreparedPullPattern) -> *const c_char;
    fn vev_prepared_pull_pattern_free(pattern: VevPreparedPullPattern);
    fn vev_pull_prepared(
        db: VevDb,
        pattern: VevPreparedPullPattern,
        entity: c_ulonglong,
    ) -> VevValueHandle;
    fn vev_pull_lookup_ref_string_edn(
        db: VevDb,
        pattern_text: *const c_char,
        attr: *const c_char,
        value: *const c_char,
    ) -> VevValueHandle;
    fn vev_pull_many_edn(
        db: VevDb,
        pattern_text: *const c_char,
        entities: *const c_ulonglong,
        entity_count: c_int,
    ) -> VevValueHandle;
    fn vev_pull_many_prepared(
        db: VevDb,
        pattern: VevPreparedPullPattern,
        entities: *const c_ulonglong,
        entity_count: c_int,
    ) -> VevValueHandle;
    fn vev_pull_many_lookup_ref_string_edn(
        db: VevDb,
        pattern_text: *const c_char,
        attr: *const c_char,
        values: *const *const c_char,
        value_count: c_int,
    ) -> VevValueHandle;
    fn vev_pull_many_lookup_ref_string_prepared(
        db: VevDb,
        pattern: VevPreparedPullPattern,
        attr: *const c_char,
        values: *const *const c_char,
        value_count: c_int,
    ) -> VevValueHandle;
    fn vev_value_handle_free(handle: VevValueHandle);
    fn vev_value_handle_value(handle: VevValueHandle) -> VevValue;
    fn vev_value_handle_edn(handle: VevValueHandle) -> *const c_char;

    fn vev_result_free(result: VevResult);
    fn vev_result_ok(result: VevResult) -> bool;
    fn vev_result_error(result: VevResult) -> *const c_char;
    fn vev_result_row_count(result: VevResult) -> c_int;
    fn vev_result_value_count(result: VevResult, row: c_int) -> c_int;
    fn vev_result_value(result: VevResult, row: c_int, column: c_int) -> VevValue;
    fn vev_result_pull_count(result: VevResult, row: c_int) -> c_int;
    fn vev_result_pull(result: VevResult, row: c_int, pull: c_int) -> VevValue;

    fn vev_value_kind(value: VevValue) -> c_int;
    fn vev_value_entity(value: VevValue) -> c_ulonglong;
    fn vev_value_int(value: VevValue) -> i64;
    fn vev_value_float(value: VevValue) -> c_double;
    fn vev_value_bool(value: VevValue) -> bool;
    fn vev_value_text(value: VevValue) -> *const c_char;
    fn vev_value_edn(value: VevValue) -> *const c_char;
    fn vev_value_item_count(value: VevValue) -> c_int;
    fn vev_value_item(value: VevValue, index: c_int) -> VevValue;
    fn vev_value_map_count(value: VevValue) -> c_int;
    fn vev_value_map_key(value: VevValue, index: c_int) -> VevValue;
    fn vev_value_map_value(value: VevValue, index: c_int) -> VevValue;
}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Nil,
    Entity(u64),
    String(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    Keyword(String),
    Symbol(String),
    Uuid(String),
    Instant(i64),
    Vector(Vec<Value>),
    Set(Vec<Value>),
    Map(Vec<(Value, Value)>),
}

impl Value {
    pub fn map_get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Map(items) => items.iter().find_map(|(k, v)| match k {
                Value::Keyword(text)
                | Value::String(text)
                | Value::Symbol(text)
                | Value::Uuid(text)
                    if text == key =>
                {
                    Some(v)
                }
                _ => None,
            }),
            _ => None,
        }
    }
}

struct Library;

impl Library {
    unsafe fn owned_string(ptr: *const c_char) -> String {
        if ptr.is_null() {
            return String::new();
        }
        let out = unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned();
        unsafe { vev_string_free(ptr) };
        out
    }

    unsafe fn borrowed_string(ptr: *const c_char) -> String {
        if ptr.is_null() {
            return String::new();
        }
        unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned()
    }

    unsafe fn borrowed_utf8(ptr: *const c_void, len: c_int) -> String {
        if ptr.is_null() || len <= 0 {
            return String::new();
        }
        let bytes = unsafe { slice::from_raw_parts(ptr as *const u8, len as usize) };
        String::from_utf8_lossy(bytes).into_owned()
    }

    unsafe fn string_column(batch: VevColumnBatch, count: usize) -> Vec<String> {
        let dictionary_count = unsafe { vev_column_batch_string_dictionary_count(batch) };
        let dictionary_data = unsafe { vev_column_batch_string_dictionary_data_array(batch) };
        let dictionary_lengths = unsafe { vev_column_batch_string_dictionary_lengths_data(batch) };
        let string_indices = unsafe { vev_column_batch_string_indices_data(batch) };
        if dictionary_count > 0
            && !dictionary_data.is_null()
            && !dictionary_lengths.is_null()
            && !string_indices.is_null()
        {
            let data = unsafe { slice::from_raw_parts(dictionary_data, dictionary_count as usize) };
            let lengths =
                unsafe { slice::from_raw_parts(dictionary_lengths, dictionary_count as usize) };
            let indices = unsafe { slice::from_raw_parts(string_indices, count) };
            let dictionary: Vec<String> = data
                .iter()
                .zip(lengths.iter())
                .map(|(text, len)| unsafe { Self::borrowed_utf8(*text, *len) })
                .collect();
            return indices
                .iter()
                .map(|index| dictionary[*index as usize].clone())
                .collect();
        }

        let string_data = unsafe { vev_column_batch_string_data_array(batch) };
        let string_lengths = unsafe { vev_column_batch_string_lengths_data(batch) };
        if string_data.is_null() || string_lengths.is_null() {
            return Vec::new();
        }
        let data = unsafe { slice::from_raw_parts(string_data, count) };
        let lengths = unsafe { slice::from_raw_parts(string_lengths, count) };
        data.iter()
            .zip(lengths.iter())
            .map(|(text, len)| unsafe { Self::borrowed_utf8(*text, *len) })
            .collect()
    }

    unsafe fn value_to_rust(value: VevValue) -> Value {
        match unsafe { vev_value_kind(value) } {
            VEV_VALUE_NIL => Value::Nil,
            VEV_VALUE_ENTITY => Value::Entity(unsafe { vev_value_entity(value) } as u64),
            VEV_VALUE_STRING => Value::String(unsafe { Self::owned_string(vev_value_text(value)) }),
            VEV_VALUE_INT => Value::Int(unsafe { vev_value_int(value) }),
            VEV_VALUE_FLOAT => Value::Float(unsafe { vev_value_float(value) }),
            VEV_VALUE_BOOL => Value::Bool(unsafe { vev_value_bool(value) }),
            VEV_VALUE_KEYWORD => {
                Value::Keyword(unsafe { Self::owned_string(vev_value_text(value)) })
            }
            VEV_VALUE_SYMBOL => Value::Symbol(unsafe { Self::owned_string(vev_value_text(value)) }),
            VEV_VALUE_UUID => Value::Uuid(unsafe { Self::owned_string(vev_value_text(value)) }),
            VEV_VALUE_INSTANT => Value::Instant(unsafe { vev_value_int(value) }),
            VEV_VALUE_VECTOR => {
                let count = unsafe { vev_value_item_count(value) };
                let mut out = Vec::with_capacity(count as usize);
                for index in 0..count {
                    out.push(unsafe { Self::value_to_rust(vev_value_item(value, index)) });
                }
                Value::Vector(out)
            }
            VEV_VALUE_SET => {
                let count = unsafe { vev_value_item_count(value) };
                let mut out = Vec::with_capacity(count as usize);
                for index in 0..count {
                    out.push(unsafe { Self::value_to_rust(vev_value_item(value, index)) });
                }
                Value::Set(out)
            }
            VEV_VALUE_MAP => {
                let count = unsafe { vev_value_map_count(value) };
                let mut out = Vec::with_capacity(count as usize);
                for index in 0..count {
                    let key = unsafe { Self::value_to_rust(vev_value_map_key(value, index)) };
                    let value = unsafe { Self::value_to_rust(vev_value_map_value(value, index)) };
                    out.push((key, value));
                }
                Value::Map(out)
            }
            _ => Value::String(unsafe { Self::owned_string(vev_value_edn(value)) }),
        }
    }

    unsafe fn second_string_column(batch: VevColumnBatch, count: usize) -> Vec<String> {
        let string_data = unsafe { vev_column_batch_second_string_data_array(batch) };
        let string_lengths = unsafe { vev_column_batch_second_string_lengths_data(batch) };
        if string_data.is_null() || string_lengths.is_null() {
            return Vec::new();
        }
        let data = unsafe { slice::from_raw_parts(string_data, count) };
        let lengths = unsafe { slice::from_raw_parts(string_lengths, count) };
        data.iter()
            .zip(lengths.iter())
            .map(|(ptr, len)| unsafe { Self::borrowed_utf8(*ptr, *len) })
            .collect()
    }
}

fn cstring(text: &str) -> CString {
    CString::new(text).expect("CString input cannot contain NUL")
}

pub fn version() -> String {
    unsafe { Library::borrowed_string(vev_version()) }
}

pub struct Conn {
    raw: VevConn,
}

impl Conn {
    pub fn open_memory() -> Result<Self, String> {
        let raw = unsafe { vev_conn_open_memory() };
        if raw.is_null() {
            Err("failed to open Vev connection".to_string())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn from_db(db: &Db) -> Result<Self, String> {
        // Resident/in-memory compatibility only. Durable DB handles are
        // immutable values and should be queried directly.
        let raw = unsafe { vev_conn_from_db(db.raw) };
        if raw.is_null() {
            Err("failed to create connection from DB snapshot".to_string())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn transact(&self, tx: &str) -> String {
        let tx = cstring(tx);
        unsafe { Library::owned_string(vev_transact_edn(self.raw, tx.as_ptr())) }
    }

    pub fn transact_report(&self, tx: &str) -> Result<TxReport, String> {
        let tx = cstring(tx);
        let raw = unsafe { vev_transact_edn_report(self.raw, tx.as_ptr()) };
        if raw.is_null() {
            Err("failed to transact".to_string())
        } else {
            Ok(TxReport { raw })
        }
    }

    pub fn query_text_with_inputs(&self, query: &str, inputs: &str) -> String {
        let query = cstring(query);
        let inputs = cstring(inputs);
        unsafe {
            Library::owned_string(vev_query_edn_with_inputs(
                self.raw,
                query.as_ptr(),
                inputs.as_ptr(),
            ))
        }
    }

    pub fn q(&self, query: &str, inputs: &str) -> Result<Value, String> {
        let db = self.db()?;
        db.q(query, inputs)
    }

    pub fn prepare(&self, query: &str) -> Result<PreparedQuery, String> {
        PreparedQuery::new(query)
    }

    pub fn parse_clause_edn(&self, clause: &str) -> String {
        let clause = cstring(clause);
        unsafe { Library::owned_string(vev_parse_clause_edn(clause.as_ptr())) }
    }

    pub fn db(&self) -> Result<Db, String> {
        let raw = unsafe { vev_conn_db(self.raw) };
        if raw.is_null() {
            Err("failed to retain DB snapshot".to_string())
        } else {
            Ok(Db { raw })
        }
    }
}

impl Drop for Conn {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_conn_close(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct DurableConn {
    raw: VevConnection,
}

impl DurableConn {
    pub fn open(path: &str) -> Result<Self, String> {
        let path = cstring(path);
        let raw = unsafe { vev_connect(path.as_ptr()) };
        if raw.is_null() {
            return Err("failed to connect Vev durable connection".to_string());
        }
        if unsafe { vev_connection_ok(raw) } {
            Ok(Self { raw })
        } else {
            let error = unsafe { Library::owned_string(vev_connection_error(raw)) };
            unsafe { vev_connection_close(raw) };
            Err(error)
        }
    }

    pub fn transact_report(&self, tx: &str) -> Result<TxReport, String> {
        let tx = cstring(tx);
        let raw = unsafe { vev_connection_transact_edn_report(self.raw, tx.as_ptr()) };
        if raw.is_null() {
            Err("failed to transact".to_string())
        } else {
            Ok(TxReport { raw })
        }
    }

    pub fn transact(&self, tx: &str) -> Result<String, String> {
        Ok(self.transact_report(tx)?.edn())
    }

    pub fn transact_bulk_report(&self, txs: &[&TxBuilder]) -> Result<TxReport, String> {
        if txs.is_empty() {
            return Err("transact_bulk_report requires at least one builder".to_string());
        }
        let mut raw_builders = Vec::with_capacity(txs.len());
        for tx in txs {
            if tx.raw.is_null() {
                return Err("transaction builder is closed".to_string());
            }
            raw_builders.push(tx.raw);
        }
        let raw = unsafe {
            vev_connection_tx_commit_many_report(
                self.raw,
                raw_builders.as_ptr(),
                raw_builders.len() as c_int,
            )
        };
        if raw.is_null() {
            Err("failed to transact bulk tx builders".to_string())
        } else {
            Ok(TxReport { raw })
        }
    }

    pub fn transact_logical_bulk_reports(
        &self,
        txs: &[&TxBuilder],
    ) -> Result<TxReportArray, String> {
        let mut raw_builders = Vec::with_capacity(txs.len());
        for tx in txs {
            if tx.raw.is_null() {
                return Err("transaction builder is closed".to_string());
            }
            raw_builders.push(tx.raw);
        }
        let raw_builder_ptr = if raw_builders.is_empty() {
            ptr::null()
        } else {
            raw_builders.as_ptr()
        };
        let raw = unsafe {
            vev_connection_tx_commit_logical_many_reports(
                self.raw,
                raw_builder_ptr,
                raw_builders.len() as c_int,
            )
        };
        if raw.is_null() {
            Err("failed to logical-group transact tx builders".to_string())
        } else {
            Ok(TxReportArray { raw })
        }
    }

    pub fn transact_logical_edn_reports(&self, txs: &[&str]) -> Result<TxReportArray, String> {
        let c_strings: Vec<CString> = txs.iter().map(|tx| cstring(tx)).collect();
        let raw_texts: Vec<*const c_char> = c_strings.iter().map(|tx| tx.as_ptr()).collect();
        let raw_text_ptr = if raw_texts.is_empty() {
            ptr::null()
        } else {
            raw_texts.as_ptr()
        };
        let raw = unsafe {
            vev_connection_transact_many_edn_reports(
                self.raw,
                raw_text_ptr,
                raw_texts.len() as c_int,
            )
        };
        if raw.is_null() {
            Err("failed to logical-group transact EDN tx data".to_string())
        } else {
            Ok(TxReportArray { raw })
        }
    }

    pub fn db(&self) -> Result<Db, String> {
        let raw = unsafe { vev_connection_db(self.raw) };
        if raw.is_null() {
            Err("failed to retain DB snapshot".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn q(&self, query: &str, inputs: &str) -> Result<Value, String> {
        let db = self.db()?;
        db.q(query, inputs)
    }

    pub fn backend(&self) -> String {
        unsafe { Library::owned_string(vev_connection_backend(self.raw)) }
    }

    pub fn path(&self) -> String {
        unsafe { Library::owned_string(vev_connection_path(self.raw)) }
    }

    pub fn basis_t(&self) -> u64 {
        unsafe { vev_connection_basis_t(self.raw) as u64 }
    }

    pub fn tx_count(&self) -> u64 {
        unsafe { vev_connection_tx_count(self.raw) as u64 }
    }

    pub fn tx_ids(&self) -> Vec<u64> {
        let raw = unsafe { vev_connection_tx_ids(self.raw) };
        if raw.is_null() {
            return Vec::new();
        }
        let count = unsafe { vev_u64_array_count(raw) };
        let mut out = Vec::with_capacity(count.max(0) as usize);
        for index in 0..count {
            out.push(unsafe { vev_u64_array_value(raw, index) as u64 });
        }
        unsafe { vev_u64_array_free(raw) };
        out
    }

    pub fn info_edn(&self) -> String {
        unsafe { Library::owned_string(vev_connection_info_edn(self.raw)) }
    }
}

impl Drop for DurableConn {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_connection_close(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct TxBuilder {
    raw: VevTxBuilder,
}

impl TxBuilder {
    pub fn new(capacity: i32) -> Result<Self, String> {
        let raw = unsafe { vev_tx_create(capacity as c_int) };
        if raw.is_null() {
            Err("failed to create transaction builder".to_string())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn add_string(&self, entity: u64, attr: &str, value: &str) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        let value = cstring(value);
        if unsafe {
            vev_tx_add_string(
                self.raw,
                entity as c_ulonglong,
                attr.as_ptr(),
                value.as_ptr(),
            )
        } {
            Ok(())
        } else {
            Err("failed to add string datom to transaction builder".to_string())
        }
    }

    pub fn add_keyword(&self, entity: u64, attr: &str, value: &str) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        let value = cstring(value);
        if unsafe {
            vev_tx_add_keyword(
                self.raw,
                entity as c_ulonglong,
                attr.as_ptr(),
                value.as_ptr(),
            )
        } {
            Ok(())
        } else {
            Err("failed to add keyword datom to transaction builder".to_string())
        }
    }

    pub fn add_symbol(&self, entity: u64, attr: &str, value: &str) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        let value = cstring(value);
        if unsafe {
            vev_tx_add_symbol(
                self.raw,
                entity as c_ulonglong,
                attr.as_ptr(),
                value.as_ptr(),
            )
        } {
            Ok(())
        } else {
            Err("failed to add symbol datom to transaction builder".to_string())
        }
    }

    pub fn add_entity(&self, entity: u64, attr: &str, value: u64) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        if unsafe {
            vev_tx_add_entity(
                self.raw,
                entity as c_ulonglong,
                attr.as_ptr(),
                value as c_ulonglong,
            )
        } {
            Ok(())
        } else {
            Err("failed to add entity datom to transaction builder".to_string())
        }
    }

    pub fn add_int(&self, entity: u64, attr: &str, value: i64) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        if unsafe {
            vev_tx_add_int(
                self.raw,
                entity as c_ulonglong,
                attr.as_ptr(),
                value as c_longlong,
            )
        } {
            Ok(())
        } else {
            Err("failed to add int datom to transaction builder".to_string())
        }
    }

    pub fn add_bool(&self, entity: u64, attr: &str, value: bool) -> Result<(), String> {
        if self.raw.is_null() {
            return Err("transaction builder is closed".to_string());
        }
        let attr = cstring(attr);
        if unsafe { vev_tx_add_bool(self.raw, entity as c_ulonglong, attr.as_ptr(), value) } {
            Ok(())
        } else {
            Err("failed to add bool datom to transaction builder".to_string())
        }
    }
}

impl Drop for TxBuilder {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_tx_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct Db {
    raw: VevDb,
}

impl Db {
    pub fn q(&self, query: &str, inputs: &str) -> Result<Value, String> {
        let query = cstring(query);
        let inputs = cstring(inputs);
        let raw =
            unsafe { vev_db_query_value_with_inputs(self.raw, query.as_ptr(), inputs.as_ptr()) };
        Ok(ValueHandle::new(raw)?.value())
    }

    pub fn query_columns(
        &self,
        query: &PreparedQuery,
        inputs: &str,
    ) -> Result<Option<ColumnResult>, String> {
        let inputs = cstring(inputs);
        let raw = unsafe {
            vev_query_db_prepared_column_batch_with_inputs(self.raw, query.raw, inputs.as_ptr())
        };
        if raw.is_null() {
            return Ok(None);
        }
        let result = unsafe { ColumnResult::from_raw(raw) };
        unsafe { vev_column_batch_free(raw) };
        result
    }

    pub fn query_stmt_columns(&self, stmt: &Statement<'_>) -> Result<Option<ColumnResult>, String> {
        let raw = unsafe { vev_query_db_stmt_column_batch(self.raw, stmt.raw) };
        if raw.is_null() {
            return Ok(None);
        }
        let result = unsafe { ColumnResult::from_raw(raw) };
        unsafe { vev_column_batch_free(raw) };
        result
    }

    pub fn with_report(&self, tx: &str) -> Result<TxReport, String> {
        let tx = cstring(tx);
        let raw = unsafe { vev_with_edn_report(self.raw, tx.as_ptr()) };
        if raw.is_null() {
            Err("failed to transact against DB snapshot".to_string())
        } else {
            Ok(TxReport { raw })
        }
    }

    pub fn db_with(&self, tx: &str) -> Result<Db, String> {
        let tx = cstring(tx);
        let raw = unsafe { vev_db_with_edn(self.raw, tx.as_ptr()) };
        if raw.is_null() {
            Err("failed to create DB snapshot".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn as_of(&self, tx: u64) -> Result<Db, String> {
        let raw = unsafe { vev_db_as_of(self.raw, tx as c_ulonglong) };
        if raw.is_null() {
            Err("failed to create as-of DB".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn as_of_instant_millis(&self, unix_millis: i64) -> Result<Db, String> {
        let raw = unsafe { vev_db_as_of_instant_millis(self.raw, unix_millis as c_longlong) };
        if raw.is_null() {
            Err("failed to create as-of DB".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn as_of_time(&self, time_point: SystemTime) -> Result<Db, String> {
        self.as_of_instant_millis(system_time_millis(time_point)?)
    }

    pub fn since(&self, tx: u64) -> Result<Db, String> {
        let raw = unsafe { vev_db_since(self.raw, tx as c_ulonglong) };
        if raw.is_null() {
            Err("failed to create since DB".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn since_instant_millis(&self, unix_millis: i64) -> Result<Db, String> {
        let raw = unsafe { vev_db_since_instant_millis(self.raw, unix_millis as c_longlong) };
        if raw.is_null() {
            Err("failed to create since DB".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn since_time(&self, time_point: SystemTime) -> Result<Db, String> {
        self.since_instant_millis(system_time_millis(time_point)?)
    }

    pub fn history(&self) -> Result<Db, String> {
        let raw = unsafe { vev_db_history(self.raw) };
        if raw.is_null() {
            Err("failed to create history DB".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn entity(&self, entity: u64) -> Result<EntityView, String> {
        let raw = unsafe { vev_db_entity(self.raw, entity as c_ulonglong) };
        if raw.is_null() {
            Err("failed to create entity view".to_string())
        } else {
            Ok(EntityView { raw })
        }
    }

    pub fn entity_lookup_ref_string(&self, attr: &str, value: &str) -> Result<EntityView, String> {
        let attr = cstring(attr);
        let value = cstring(value);
        let raw =
            unsafe { vev_db_entity_lookup_ref_string(self.raw, attr.as_ptr(), value.as_ptr()) };
        if raw.is_null() {
            Err("failed to create lookup-ref entity view".to_string())
        } else {
            Ok(EntityView { raw })
        }
    }

    pub fn entity_ident(&self, ident: &str) -> Result<EntityView, String> {
        let ident = cstring(ident);
        let raw = unsafe { vev_db_entity_ident(self.raw, ident.as_ptr()) };
        if raw.is_null() {
            Err("failed to create ident entity view".to_string())
        } else {
            Ok(EntityView { raw })
        }
    }

    pub fn pull(&self, pattern: &str, entity: u64) -> Result<Value, String> {
        let pattern = cstring(pattern);
        let raw = unsafe { vev_pull_edn(self.raw, pattern.as_ptr(), entity as c_ulonglong) };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_prepared(
        &self,
        pattern: &PreparedPullPattern,
        entity: u64,
    ) -> Result<Value, String> {
        let raw = unsafe { vev_pull_prepared(self.raw, pattern.raw, entity as c_ulonglong) };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_lookup_ref_string(
        &self,
        pattern: &str,
        attr: &str,
        value: &str,
    ) -> Result<Value, String> {
        let pattern = cstring(pattern);
        let attr = cstring(attr);
        let value = cstring(value);
        let raw = unsafe {
            vev_pull_lookup_ref_string_edn(
                self.raw,
                pattern.as_ptr(),
                attr.as_ptr(),
                value.as_ptr(),
            )
        };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_many(&self, pattern: &str, entities: &[u64]) -> Result<Value, String> {
        let pattern = cstring(pattern);
        let raw = unsafe {
            vev_pull_many_edn(
                self.raw,
                pattern.as_ptr(),
                entities.as_ptr(),
                entities.len() as c_int,
            )
        };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_many_prepared(
        &self,
        pattern: &PreparedPullPattern,
        entities: &[u64],
    ) -> Result<Value, String> {
        let raw = unsafe {
            vev_pull_many_prepared(
                self.raw,
                pattern.raw,
                entities.as_ptr(),
                entities.len() as c_int,
            )
        };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_many_lookup_ref_string(
        &self,
        pattern: &str,
        attr: &str,
        values: &[&str],
    ) -> Result<Value, String> {
        let pattern = cstring(pattern);
        let attr = cstring(attr);
        let value_strings: Vec<CString> = values.iter().map(|value| cstring(value)).collect();
        let value_ptrs: Vec<*const c_char> =
            value_strings.iter().map(|value| value.as_ptr()).collect();
        let raw = unsafe {
            vev_pull_many_lookup_ref_string_edn(
                self.raw,
                pattern.as_ptr(),
                attr.as_ptr(),
                value_ptrs.as_ptr(),
                value_ptrs.len() as c_int,
            )
        };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn pull_many_lookup_ref_string_prepared(
        &self,
        pattern: &PreparedPullPattern,
        attr: &str,
        values: &[&str],
    ) -> Result<Value, String> {
        let attr = cstring(attr);
        let value_strings: Vec<CString> = values.iter().map(|value| cstring(value)).collect();
        let value_ptrs: Vec<*const c_char> =
            value_strings.iter().map(|value| value.as_ptr()).collect();
        let raw = unsafe {
            vev_pull_many_lookup_ref_string_prepared(
                self.raw,
                pattern.raw,
                attr.as_ptr(),
                value_ptrs.as_ptr(),
                value_ptrs.len() as c_int,
            )
        };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }
}

pub struct EntityView {
    raw: VevEntity,
}

impl EntityView {
    pub fn found(&self) -> bool {
        unsafe { vev_entity_found(self.raw) }
    }

    pub fn id(&self) -> u64 {
        unsafe { vev_entity_id(self.raw) as u64 }
    }

    pub fn contains(&self, attr: &str) -> bool {
        let attr = cstring(attr);
        unsafe { vev_entity_contains(self.raw, attr.as_ptr()) }
    }

    pub fn get(&self, attr: &str) -> Result<Value, String> {
        let attr = cstring(attr);
        let raw = unsafe { vev_entity_get(self.raw, attr.as_ptr()) };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn values(&self, attr: &str) -> Result<Value, String> {
        let attr = cstring(attr);
        let raw = unsafe { vev_entity_values(self.raw, attr.as_ptr()) };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }

    pub fn ref_entity(&self, attr: &str) -> Result<EntityView, String> {
        let attr = cstring(attr);
        let raw = unsafe { vev_entity_ref(self.raw, attr.as_ptr()) };
        if raw.is_null() {
            Err("failed to create referenced entity view".to_string())
        } else {
            Ok(EntityView { raw })
        }
    }

    pub fn refs(&self, attr: &str) -> Vec<u64> {
        let attr = cstring(attr);
        let raw = unsafe { vev_entity_refs(self.raw, attr.as_ptr()) };
        if raw.is_null() {
            return Vec::new();
        }
        let count = unsafe { vev_u64_array_count(raw) };
        let mut out = Vec::with_capacity(count.max(0) as usize);
        for index in 0..count {
            out.push(unsafe { vev_u64_array_value(raw, index) as u64 });
        }
        unsafe { vev_u64_array_free(raw) };
        out
    }

    pub fn touch(&self) -> Result<Value, String> {
        let raw = unsafe { vev_entity_touch(self.raw) };
        let handle = ValueHandle::new(raw)?;
        Ok(handle.value())
    }
}

impl Drop for EntityView {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_entity_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

impl Drop for Db {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_db_release(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Column {
    Entity(Vec<u64>),
    String(Vec<String>),
    Int(Vec<i64>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ColumnResult {
    count: usize,
    pub kinds: Vec<c_int>,
    columns: Vec<Column>,
}

impl ColumnResult {
    unsafe fn from_raw(raw: VevColumnBatch) -> Result<Option<Self>, String> {
        let kind = unsafe { vev_column_batch_kind(raw) };
        let count = unsafe { vev_column_batch_count(raw) }.max(0) as usize;
        let entities_data = unsafe { vev_column_batch_entities_data(raw) };
        let ints_data = unsafe { vev_column_batch_ints_data(raw) };
        let entities = || {
            if entities_data.is_null() {
                Vec::new()
            } else {
                unsafe { slice::from_raw_parts(entities_data, count) }
                    .iter()
                    .map(|value| *value as u64)
                    .collect()
            }
        };
        let ints = || {
            if ints_data.is_null() {
                Vec::new()
            } else {
                unsafe { slice::from_raw_parts(ints_data, count) }.to_vec()
            }
        };
        let strings = || unsafe { Library::string_column(raw, count) };
        let second_strings = || unsafe { Library::second_string_column(raw, count) };

        match kind {
            VEV_COLUMN_BATCH_ENTITY => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_ENTITY],
                columns: vec![Column::Entity(entities())],
            })),
            VEV_COLUMN_BATCH_STRING => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_STRING],
                columns: vec![Column::String(strings())],
            })),
            VEV_COLUMN_BATCH_INT => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_INT],
                columns: vec![Column::Int(ints())],
            })),
            VEV_COLUMN_BATCH_ENTITY_INT => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_ENTITY, VEV_COLUMN_INT],
                columns: vec![Column::Entity(entities()), Column::Int(ints())],
            })),
            VEV_COLUMN_BATCH_ENTITY_STRING => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_ENTITY, VEV_COLUMN_STRING],
                columns: vec![Column::Entity(entities()), Column::String(strings())],
            })),
            VEV_COLUMN_BATCH_STRING_INT => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_STRING, VEV_COLUMN_INT],
                columns: vec![Column::String(strings()), Column::Int(ints())],
            })),
            VEV_COLUMN_BATCH_STRING_STRING => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_STRING, VEV_COLUMN_STRING],
                columns: vec![Column::String(strings()), Column::String(second_strings())],
            })),
            VEV_COLUMN_BATCH_ENTITY_STRING_INT => Ok(Some(Self {
                count,
                kinds: vec![VEV_COLUMN_ENTITY, VEV_COLUMN_STRING, VEV_COLUMN_INT],
                columns: vec![
                    Column::Entity(entities()),
                    Column::String(strings()),
                    Column::Int(ints()),
                ],
            })),
            _ => Ok(None),
        }
    }

    pub fn rows(&self) -> Vec<Vec<Value>> {
        let mut out = Vec::with_capacity(self.count);
        for row in 0..self.count {
            let mut values = Vec::with_capacity(self.columns.len());
            for column in &self.columns {
                values.push(match column {
                    Column::Entity(values) => Value::Entity(values[row]),
                    Column::String(values) => Value::String(values[row].clone()),
                    Column::Int(values) => Value::Int(values[row]),
                });
            }
            out.push(values);
        }
        out
    }
}

struct ValueHandle {
    raw: VevValueHandle,
}

impl ValueHandle {
    pub fn new(raw: VevValueHandle) -> Result<Self, String> {
        if raw.is_null() {
            Err("pull returned null value handle".to_string())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn value(&self) -> Value {
        unsafe { Library::value_to_rust(vev_value_handle_value(self.raw)) }
    }

    #[allow(dead_code)]
    pub fn edn(&self) -> String {
        unsafe { Library::owned_string(vev_value_handle_edn(self.raw)) }
    }
}

impl Drop for ValueHandle {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_value_handle_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct TxReport {
    raw: VevTxReport,
}

impl TxReport {
    pub fn value(&self) -> Value {
        unsafe { Library::value_to_rust(vev_tx_report_value(self.raw)) }
    }

    pub fn edn(&self) -> String {
        unsafe { Library::owned_string(vev_tx_report_edn(self.raw)) }
    }

    pub fn db_before(&self) -> Result<Db, String> {
        let raw = unsafe { vev_tx_report_db_before(self.raw) };
        if raw.is_null() {
            Err("transaction report has no db-before".to_string())
        } else {
            Ok(Db { raw })
        }
    }

    pub fn db_after(&self) -> Result<Db, String> {
        let raw = unsafe { vev_tx_report_db_after(self.raw) };
        if raw.is_null() {
            Err("transaction report has no db-after".to_string())
        } else {
            Ok(Db { raw })
        }
    }
}

impl Drop for TxReport {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_tx_report_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct BorrowedTxReport {
    raw: VevTxReport,
}

impl BorrowedTxReport {
    pub fn value(&self) -> Value {
        unsafe { Library::value_to_rust(vev_tx_report_value(self.raw)) }
    }
}

pub struct TxReportArray {
    raw: VevTxReportArray,
}

impl TxReportArray {
    pub fn len(&self) -> usize {
        unsafe { vev_tx_report_array_count(self.raw) as usize }
    }

    pub fn get(&self, index: usize) -> Result<BorrowedTxReport, String> {
        let raw = unsafe { vev_tx_report_array_get(self.raw, index as c_int) };
        if raw.is_null() {
            Err("transaction report index out of range".to_string())
        } else {
            Ok(BorrowedTxReport { raw })
        }
    }

    pub fn values(&self) -> Result<Vec<Value>, String> {
        let mut out = Vec::with_capacity(self.len());
        for index in 0..self.len() {
            out.push(self.get(index)?.value());
        }
        Ok(out)
    }
}

impl Drop for TxReportArray {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_tx_report_array_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct PreparedQuery {
    raw: VevPreparedQuery,
}

impl PreparedQuery {
    pub fn new(query: &str) -> Result<Self, String> {
        let query = cstring(query);
        let raw = unsafe { vev_prepare_query_edn(query.as_ptr()) };
        if raw.is_null() {
            Err("failed to prepare query".to_string())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn statement(&self) -> Result<Statement<'_>, String> {
        let raw = unsafe { vev_stmt_create(self.raw) };
        if raw.is_null() {
            Err("failed to create statement".to_string())
        } else {
            Ok(Statement { raw, _query: self })
        }
    }

    pub fn edn(&self) -> String {
        unsafe { Library::owned_string(vev_prepared_query_edn(self.raw)) }
    }

    pub fn query_conn(&self, conn: &Conn, inputs: &str) -> Result<ResultSet, String> {
        let inputs = cstring(inputs);
        let raw =
            unsafe { vev_query_prepared_result_with_inputs(conn.raw, self.raw, inputs.as_ptr()) };
        ResultSet::new(raw)
    }

    pub fn query_db(&self, db: &Db, inputs: &str) -> Result<ResultSet, String> {
        let inputs = cstring(inputs);
        let raw =
            unsafe { vev_query_db_prepared_result_with_inputs(db.raw, self.raw, inputs.as_ptr()) };
        ResultSet::new(raw)
    }
}

impl Drop for PreparedQuery {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_prepared_query_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct PreparedPullPattern {
    raw: VevPreparedPullPattern,
}

impl PreparedPullPattern {
    pub fn new(pattern: &str) -> Result<Self, String> {
        let pattern = cstring(pattern);
        let raw = unsafe { vev_prepare_pull_pattern_edn(pattern.as_ptr()) };
        if raw.is_null() {
            return Err("failed to prepare pull pattern".to_string());
        }
        if !unsafe { vev_prepared_pull_pattern_ok(raw) } {
            let err = unsafe { Library::owned_string(vev_prepared_pull_pattern_error(raw)) };
            unsafe { vev_prepared_pull_pattern_free(raw) };
            return Err(err);
        }
        Ok(Self { raw })
    }

    pub fn edn(&self) -> String {
        unsafe { Library::owned_string(vev_prepared_pull_pattern_edn(self.raw)) }
    }
}

impl Drop for PreparedPullPattern {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_prepared_pull_pattern_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct Statement<'a> {
    raw: VevStmt,
    _query: &'a PreparedQuery,
}

impl Statement<'_> {
    pub fn bind_string(&mut self, value: &str) -> Result<&mut Self, String> {
        unsafe { vev_stmt_clear(self.raw) };
        let value = cstring(value);
        if unsafe { vev_stmt_bind_string(self.raw, value.as_ptr()) } {
            Ok(self)
        } else {
            Err("failed to bind string".to_string())
        }
    }

    pub fn bind_string_collection(&mut self, values: &[&str]) -> Result<&mut Self, String> {
        unsafe { vev_stmt_clear(self.raw) };
        let owned: Vec<CString> = values.iter().map(|value| cstring(value)).collect();
        let ptrs: Vec<*const c_char> = owned.iter().map(|value| value.as_ptr()).collect();
        if unsafe { vev_stmt_bind_string_collection(self.raw, ptrs.as_ptr(), ptrs.len() as c_int) }
        {
            Ok(self)
        } else {
            Err("failed to bind string collection".to_string())
        }
    }

    pub fn bind_pull_pattern_and_string(
        &mut self,
        pattern: &str,
        value: &str,
    ) -> Result<&mut Self, String> {
        unsafe { vev_stmt_clear(self.raw) };
        let pattern = cstring(pattern);
        let value = cstring(value);
        if unsafe {
            vev_stmt_bind_pull_pattern_edn(self.raw, pattern.as_ptr())
                && vev_stmt_bind_string(self.raw, value.as_ptr())
        } {
            Ok(self)
        } else {
            Err("failed to bind pull pattern and string".to_string())
        }
    }

    pub fn query_conn(&self, conn: &Conn) -> Result<ResultSet, String> {
        let raw = unsafe { vev_query_stmt_result(conn.raw, self.raw) };
        ResultSet::new(raw)
    }

    pub fn query_db(&self, db: &Db) -> Result<ResultSet, String> {
        let raw = unsafe { vev_query_db_stmt_result(db.raw, self.raw) };
        ResultSet::new(raw)
    }

    pub fn columns_conn(&self, conn: &Conn) -> Result<Option<ColumnResult>, String> {
        let raw = unsafe { vev_query_stmt_column_batch(conn.raw, self.raw) };
        if raw.is_null() {
            return Ok(None);
        }
        let result = unsafe { ColumnResult::from_raw(raw) };
        unsafe { vev_column_batch_free(raw) };
        result
    }

    pub fn columns_db(&self, db: &Db) -> Result<Option<ColumnResult>, String> {
        db.query_stmt_columns(self)
    }
}

impl Drop for Statement<'_> {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_stmt_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

pub struct ResultSet {
    raw: VevResult,
}

impl ResultSet {
    pub fn new(raw: VevResult) -> Result<Self, String> {
        if raw.is_null() {
            return Err("query returned null result".to_string());
        }
        if unsafe { vev_result_ok(raw) } {
            Ok(Self { raw })
        } else {
            let error = unsafe { Library::owned_string(vev_result_error(raw)) };
            unsafe { vev_result_free(raw) };
            Err(error)
        }
    }

    pub fn row_count(&self) -> usize {
        unsafe { vev_result_row_count(self.raw) as usize }
    }

    pub fn rows(&self) -> Vec<Vec<Value>> {
        let mut out = Vec::with_capacity(self.row_count());
        for row in 0..self.row_count() as c_int {
            let mut values = Vec::new();
            let value_count = unsafe { vev_result_value_count(self.raw, row) };
            for column in 0..value_count {
                values.push(unsafe {
                    Library::value_to_rust(vev_result_value(self.raw, row, column))
                });
            }
            let pull_count = unsafe { vev_result_pull_count(self.raw, row) };
            for pull in 0..pull_count {
                values
                    .push(unsafe { Library::value_to_rust(vev_result_pull(self.raw, row, pull)) });
            }
            out.push(values);
        }
        out
    }

    pub fn scalar(&self) -> Result<Value, String> {
        let rows = self.rows();
        if rows.len() == 1 && rows[0].len() == 1 {
            Ok(rows[0][0].clone())
        } else {
            Err(format!("expected one scalar result, got {rows:?}"))
        }
    }
}

impl Drop for ResultSet {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { vev_result_free(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}
