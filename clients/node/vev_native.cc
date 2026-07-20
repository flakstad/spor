// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#include "vev.h"
#include <node_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

struct Conn {
  vev_conn_t raw;
};

struct DurableConn {
  vev_connection_t raw;
};

struct DB {
  vev_db_t raw;
};

struct PreparedQuery {
  vev_prepared_query_t raw;
};

void throw_error(napi_env env, const char *message) {
  napi_throw_error(env, nullptr, message);
}

bool ok(napi_env env, napi_status status) {
  if (status == napi_ok) {
    return true;
  }
  const napi_extended_error_info *info = nullptr;
  napi_get_last_error_info(env, &info);
  throw_error(env, info && info->error_message ? info->error_message
                                                : "N-API call failed");
  return false;
}

char *string_arg(napi_env env, napi_callback_info info, size_t index) {
  size_t argc = index + 1;
  napi_value args[4];
  if (!ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) {
    return nullptr;
  }
  if (argc <= index) {
    throw_error(env, "missing argument");
    return nullptr;
  }

  size_t len = 0;
  if (!ok(env, napi_get_value_string_utf8(env, args[index], nullptr, 0, &len))) {
    return nullptr;
  }
  char *out = static_cast<char *>(malloc(len + 1));
  if (!out) {
    throw_error(env, "out of memory");
    return nullptr;
  }
  if (!ok(env, napi_get_value_string_utf8(env, args[index], out, len + 1, &len))) {
    free(out);
    return nullptr;
  }
  return out;
}

template <typename T>
T *external_arg(napi_env env, napi_callback_info info, size_t index) {
  size_t argc = index + 1;
  napi_value args[4];
  if (!ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr))) {
    return nullptr;
  }
  if (argc <= index) {
    throw_error(env, "missing argument");
    return nullptr;
  }
  void *data = nullptr;
  if (!ok(env, napi_get_value_external(env, args[index], &data))) {
    return nullptr;
  }
  return static_cast<T *>(data);
}

bool uint64_arg(napi_env env, napi_value value, unsigned long long *out) {
  napi_valuetype type;
  if (!ok(env, napi_typeof(env, value, &type))) {
    return false;
  }
  if (type == napi_bigint) {
    bool lossless = false;
    if (!ok(env, napi_get_value_bigint_uint64(env, value, out, &lossless))) {
      return false;
    }
    if (!lossless) {
      throw_error(env, "transaction id is outside the unsigned 64-bit range");
      return false;
    }
    return true;
  }
  double number = 0;
  if (!ok(env, napi_get_value_double(env, value, &number)) || number < 0) {
    return false;
  }
  *out = static_cast<unsigned long long>(number);
  return true;
}

bool int64_arg(napi_env env, napi_value value, long long *out) {
  napi_valuetype type;
  if (!ok(env, napi_typeof(env, value, &type))) {
    return false;
  }
  if (type != napi_number ||
      !ok(env, napi_get_value_int64(env, value, out))) {
    throw_error(env, "instant must be Unix milliseconds");
    return false;
  }
  return true;
}

napi_value owned_string(napi_env env, const char *text) {
  napi_value out;
  const char *safe = text ? text : "";
  napi_status status = napi_create_string_utf8(env, safe, NAPI_AUTO_LENGTH, &out);
  if (text) {
    vev_string_free(text);
  }
  if (!ok(env, status)) {
    return nullptr;
  }
  return out;
}

napi_value borrowed_string(napi_env env, const char *text) {
  napi_value out;
  if (!ok(env, napi_create_string_utf8(env, text ? text : "", NAPI_AUTO_LENGTH, &out))) {
    return nullptr;
  }
  return out;
}

napi_value js_value(napi_env env, vev_value_t value);

napi_value owned_text_value(napi_env env, const char *text) {
  napi_value out = borrowed_string(env, text);
  if (text) {
    vev_string_free(text);
  }
  return out;
}

napi_value map_key_string(napi_env env, vev_value_t value) {
  int kind = vev_value_kind(value);
  if (kind == VEV_VALUE_STRING || kind == VEV_VALUE_KEYWORD || kind == VEV_VALUE_SYMBOL ||
      kind == VEV_VALUE_UUID) {
    return owned_text_value(env, vev_value_text(value));
  }
  return owned_text_value(env, vev_value_edn(value));
}

napi_value js_entity(napi_env env, unsigned long long id) {
  napi_value out;
  napi_value id_value;
  if (!ok(env, napi_create_object(env, &out)) ||
      !ok(env, napi_create_double(env, static_cast<double>(id), &id_value)) ||
      !ok(env, napi_set_named_property(env, out, "id", id_value))) {
    return nullptr;
  }
  return out;
}

napi_value js_value(napi_env env, vev_value_t value) {
  napi_value out;
  switch (vev_value_kind(value)) {
  case VEV_VALUE_NIL:
    ok(env, napi_get_null(env, &out));
    return out;
  case VEV_VALUE_ENTITY:
    return js_entity(env, vev_value_entity(value));
  case VEV_VALUE_STRING:
    return owned_text_value(env, vev_value_text(value));
  case VEV_VALUE_INT:
    ok(env, napi_create_int64(env, vev_value_int(value), &out));
    return out;
  case VEV_VALUE_INSTANT:
    ok(env, napi_create_date(env, static_cast<double>(vev_value_int(value)), &out));
    return out;
  case VEV_VALUE_FLOAT:
    ok(env, napi_create_double(env, vev_value_float(value), &out));
    return out;
  case VEV_VALUE_BOOL:
    ok(env, napi_get_boolean(env, vev_value_bool(value), &out));
    return out;
  case VEV_VALUE_KEYWORD:
  case VEV_VALUE_SYMBOL:
  case VEV_VALUE_UUID:
    return owned_text_value(env, vev_value_text(value));
  case VEV_VALUE_VECTOR: {
    int count = vev_value_item_count(value);
    if (!ok(env, napi_create_array_with_length(env, count, &out))) {
      return nullptr;
    }
    for (int i = 0; i < count; i++) {
      napi_value item = js_value(env, vev_value_item(value, i));
      if (!item || !ok(env, napi_set_element(env, out, i, item))) {
        return nullptr;
      }
    }
    return out;
  }
  case VEV_VALUE_SET: {
    napi_value global;
    napi_value set_constructor;
    if (!ok(env, napi_get_global(env, &global)) ||
        !ok(env, napi_get_named_property(env, global, "Set", &set_constructor)) ||
        !ok(env, napi_new_instance(env, set_constructor, 0, nullptr, &out))) {
      return nullptr;
    }
    napi_value add;
    if (!ok(env, napi_get_named_property(env, out, "add", &add))) {
      return nullptr;
    }
    int count = vev_value_item_count(value);
    for (int i = 0; i < count; i++) {
      napi_value item = js_value(env, vev_value_item(value, i));
      napi_value ignored;
      if (!item || !ok(env, napi_call_function(env, out, add, 1, &item, &ignored))) {
        return nullptr;
      }
    }
    return out;
  }
  case VEV_VALUE_MAP: {
    int count = vev_value_map_count(value);
    if (!ok(env, napi_create_object(env, &out))) {
      return nullptr;
    }
    for (int i = 0; i < count; i++) {
      napi_value key = map_key_string(env, vev_value_map_key(value, i));
      napi_value item = js_value(env, vev_value_map_value(value, i));
      if (!key || !item || !ok(env, napi_set_property(env, out, key, item))) {
        return nullptr;
      }
    }
    return out;
  }
  default:
    return owned_text_value(env, vev_value_edn(value));
  }
}

void finalize_conn(napi_env, void *data, void *) {
  Conn *conn = static_cast<Conn *>(data);
  if (conn) {
    if (conn->raw) {
      vev_conn_close(conn->raw);
    }
    delete conn;
  }
}

void finalize_durable_conn(napi_env, void *data, void *) {
  DurableConn *conn = static_cast<DurableConn *>(data);
  if (conn) {
    if (conn->raw) {
      vev_connection_close(conn->raw);
    }
    delete conn;
  }
}

void finalize_db(napi_env, void *data, void *) {
  DB *db = static_cast<DB *>(data);
  if (db) {
    if (db->raw) {
      vev_db_release(db->raw);
    }
    delete db;
  }
}

napi_value wrap_db(napi_env env, vev_db_t raw) {
  if (!raw) {
    throw_error(env, "failed to retain DB snapshot");
    return nullptr;
  }
  DB *snapshot = new DB{raw};
  napi_value out;
  if (!ok(env, napi_create_external(env, snapshot, finalize_db, nullptr, &out))) {
    finalize_db(env, snapshot, nullptr);
    return nullptr;
  }
  return out;
}

void finalize_prepared_query(napi_env, void *data, void *) {
  PreparedQuery *query = static_cast<PreparedQuery *>(data);
  if (query) {
    if (query->raw) {
      vev_prepared_query_free(query->raw);
    }
    delete query;
  }
}

napi_value open_memory(napi_env env, napi_callback_info) {
  Conn *conn = new Conn{vev_conn_open_memory()};
  if (!conn->raw) {
    delete conn;
    throw_error(env, "failed to open Vev connection");
    return nullptr;
  }
  napi_value out;
  if (!ok(env, napi_create_external(env, conn, finalize_conn, nullptr, &out))) {
    finalize_conn(env, conn, nullptr);
    return nullptr;
  }
  return out;
}

napi_value connect(napi_env env, napi_callback_info info) {
  char *uri = string_arg(env, info, 0);
  if (!uri) {
    return nullptr;
  }
  DurableConn *conn = new DurableConn{vev_connect(uri)};
  free(uri);
  if (!conn->raw) {
    delete conn;
    throw_error(env, "failed to connect Vev durable connection");
    return nullptr;
  }
  if (!vev_connection_ok(conn->raw)) {
    const char *error = vev_connection_error(conn->raw);
    char *copy = error ? strdup(error) : strdup("failed to connect Vev durable connection");
    if (error) {
      vev_string_free(error);
    }
    finalize_durable_conn(env, conn, nullptr);
    throw_error(env, copy);
    free(copy);
    return nullptr;
  }
  napi_value out;
  if (!ok(env, napi_create_external(env, conn, finalize_durable_conn, nullptr, &out))) {
    finalize_durable_conn(env, conn, nullptr);
    return nullptr;
  }
  return out;
}

napi_value db(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed connection");
    return nullptr;
  }
  return wrap_db(env, vev_conn_db(conn->raw));
}

napi_value durable_db(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed durable connection");
    return nullptr;
  }
  return wrap_db(env, vev_connection_db(conn->raw));
}

napi_value close_conn(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  if (conn && conn->raw) {
    vev_conn_close(conn->raw);
    conn->raw = nullptr;
  }
  return nullptr;
}

napi_value close_durable_conn(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (conn && conn->raw) {
    vev_connection_close(conn->raw);
    conn->raw = nullptr;
  }
  return nullptr;
}

napi_value close_db(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  if (snapshot && snapshot->raw) {
    vev_db_release(snapshot->raw);
    snapshot->raw = nullptr;
  }
  return nullptr;
}

napi_value close_prepared_query(napi_env env, napi_callback_info info) {
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 0);
  if (query && query->raw) {
    vev_prepared_query_free(query->raw);
    query->raw = nullptr;
  }
  return nullptr;
}

napi_value transact(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  char *tx = string_arg(env, info, 1);
  if (!conn || !conn->raw || !tx) {
    free(tx);
    throw_error(env, "invalid transact arguments");
    return nullptr;
  }
  const char *result = vev_transact_edn(conn->raw, tx);
  free(tx);
  return owned_string(env, result);
}

napi_value durable_transact(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  char *tx = string_arg(env, info, 1);
  if (!conn || !conn->raw || !tx) {
    free(tx);
    throw_error(env, "invalid durable transact arguments");
    return nullptr;
  }
  vev_tx_report_t report = vev_connection_transact_edn_report(conn->raw, tx);
  free(tx);
  if (!report) {
    throw_error(env, "failed to transact durable connection");
    return nullptr;
  }
  const char *text = vev_tx_report_edn(report);
  vev_tx_report_free(report);
  return owned_string(env, text);
}

napi_value durable_backend(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed durable connection");
    return nullptr;
  }
  return owned_string(env, vev_connection_backend(conn->raw));
}

napi_value durable_path(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed durable connection");
    return nullptr;
  }
  return owned_string(env, vev_connection_path(conn->raw));
}

napi_value durable_basis_t(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed durable connection");
    return nullptr;
  }
  napi_value out;
  ok(env, napi_create_double(env, static_cast<double>(vev_connection_basis_t(conn->raw)), &out));
  return out;
}

napi_value durable_tx_count(napi_env env, napi_callback_info info) {
  DurableConn *conn = external_arg<DurableConn>(env, info, 0);
  if (!conn || !conn->raw) {
    throw_error(env, "closed durable connection");
    return nullptr;
  }
  napi_value out;
  ok(env, napi_create_double(env, static_cast<double>(vev_connection_tx_count(conn->raw)), &out));
  return out;
}

napi_value query_text(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  char *query = string_arg(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!conn || !conn->raw || !query || !inputs) {
    free(query);
    free(inputs);
    throw_error(env, "invalid query arguments");
    return nullptr;
  }
  const char *result = vev_query_edn_with_inputs(conn->raw, query, inputs);
  free(query);
  free(inputs);
  return owned_string(env, result);
}

napi_value prepare(napi_env env, napi_callback_info info) {
  char *query_text = string_arg(env, info, 0);
  if (!query_text) {
    return nullptr;
  }
  vev_prepared_query_t raw = vev_prepare_query_edn(query_text);
  free(query_text);
  if (!raw) {
    throw_error(env, "failed to prepare query");
    return nullptr;
  }
  if (!vev_prepared_query_ok(raw)) {
    const char *error = vev_prepared_query_error(raw);
    char *copy = error ? strdup(error) : strdup("failed to prepare query");
    if (error) {
      vev_string_free(error);
    }
    vev_prepared_query_free(raw);
    throw_error(env, copy);
    free(copy);
    return nullptr;
  }

  PreparedQuery *query = new PreparedQuery{raw};
  napi_value out;
  if (!ok(env, napi_create_external(env, query, finalize_prepared_query, nullptr, &out))) {
    finalize_prepared_query(env, query, nullptr);
    return nullptr;
  }
  return out;
}

napi_value query_prepared(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!conn || !conn->raw || !query || !query->raw || !inputs) {
    free(inputs);
    throw_error(env, "invalid prepared query arguments");
    return nullptr;
  }
  const char *result = vev_query_prepared_with_inputs(conn->raw, query->raw, inputs);
  free(inputs);
  return owned_string(env, result);
}

napi_value prepared_query_edn(napi_env env, napi_callback_info info) {
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 0);
  if (!query || !query->raw) {
    throw_error(env, "invalid prepared query");
    return nullptr;
  }
  return owned_string(env, vev_prepared_query_edn(query->raw));
}

napi_value result_rows(napi_env env, vev_result_t result) {
  if (!result) {
    throw_error(env, "query returned null result");
    return nullptr;
  }
  if (!vev_result_ok(result)) {
    const char *error = vev_result_error(result);
    char *copy = error ? strdup(error) : strdup("query failed");
    if (error) {
      vev_string_free(error);
    }
    vev_result_free(result);
    throw_error(env, copy);
    free(copy);
    return nullptr;
  }

  int row_count = vev_result_row_count(result);
  napi_value rows;
  if (!ok(env, napi_create_array_with_length(env, row_count, &rows))) {
    vev_result_free(result);
    return nullptr;
  }
  for (int row = 0; row < row_count; row++) {
    int value_count = vev_result_value_count(result, row);
    int pull_count = vev_result_pull_count(result, row);
    napi_value row_values;
    if (!ok(env, napi_create_array_with_length(env, value_count + pull_count, &row_values))) {
      vev_result_free(result);
      return nullptr;
    }
    int out_index = 0;
    for (int col = 0; col < value_count; col++) {
      napi_value item = js_value(env, vev_result_value(result, row, col));
      if (!item || !ok(env, napi_set_element(env, row_values, out_index++, item))) {
        vev_result_free(result);
        return nullptr;
      }
    }
    for (int pull = 0; pull < pull_count; pull++) {
      napi_value item = js_value(env, vev_result_pull(result, row, pull));
      if (!item || !ok(env, napi_set_element(env, row_values, out_index++, item))) {
        vev_result_free(result);
        return nullptr;
      }
    }
    if (!ok(env, napi_set_element(env, rows, row, row_values))) {
      vev_result_free(result);
      return nullptr;
    }
  }
  vev_result_free(result);
  return rows;
}

napi_value query_prepared_rows(napi_env env, napi_callback_info info) {
  Conn *conn = external_arg<Conn>(env, info, 0);
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!conn || !conn->raw || !query || !query->raw || !inputs) {
    free(inputs);
    throw_error(env, "invalid prepared row query arguments");
    return nullptr;
  }
  vev_result_t result = vev_query_prepared_result_with_inputs(conn->raw, query->raw, inputs);
  free(inputs);
  return result_rows(env, result);
}

napi_value db_query_prepared(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!snapshot || !snapshot->raw || !query || !query->raw || !inputs) {
    free(inputs);
    throw_error(env, "invalid DB prepared query arguments");
    return nullptr;
  }
  const char *result = vev_query_db_prepared_with_inputs(snapshot->raw, query->raw, inputs);
  free(inputs);
  return owned_string(env, result);
}

napi_value db_query_prepared_rows(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  PreparedQuery *query = external_arg<PreparedQuery>(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!snapshot || !snapshot->raw || !query || !query->raw || !inputs) {
    free(inputs);
    throw_error(env, "invalid DB prepared row query arguments");
    return nullptr;
  }
  vev_result_t result = vev_query_db_prepared_result_with_inputs(snapshot->raw, query->raw, inputs);
  free(inputs);
  return result_rows(env, result);
}

napi_value db_q(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  char *query = string_arg(env, info, 1);
  char *inputs = string_arg(env, info, 2);
  if (!snapshot || !snapshot->raw || !query || !inputs) {
    free(query);
    free(inputs);
    throw_error(env, "invalid DB query arguments");
    return nullptr;
  }
  vev_value_handle_t handle =
      vev_db_query_value_with_inputs(snapshot->raw, query, inputs);
  free(query);
  free(inputs);
  if (!handle) {
    throw_error(env, "query failed");
    return nullptr;
  }
  napi_value out = js_value(env, vev_value_handle_value(handle));
  vev_value_handle_free(handle);
  return out;
}

napi_value db_with_report(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  char *tx = string_arg(env, info, 1);
  if (!snapshot || !snapshot->raw || !tx) {
    free(tx);
    throw_error(env, "invalid DB with report arguments");
    return nullptr;
  }
  vev_tx_report_t report = vev_with_edn_report(snapshot->raw, tx);
  free(tx);
  if (!report) {
    throw_error(env, "with report returned null report");
    return nullptr;
  }
  const char *edn_text = vev_tx_report_edn(report);
  vev_db_t before = vev_tx_report_db_before(report);
  vev_db_t after = vev_tx_report_db_after(report);

  napi_value out;
  napi_value edn;
  napi_value db_before;
  napi_value db_after;
  if (!ok(env, napi_create_object(env, &out)) ||
      !ok(env, napi_create_string_utf8(env, edn_text ? edn_text : "", NAPI_AUTO_LENGTH, &edn))) {
    if (edn_text) {
      vev_string_free(edn_text);
    }
    if (before) {
      vev_db_release(before);
    }
    if (after) {
      vev_db_release(after);
    }
    vev_tx_report_free(report);
    return nullptr;
  }
  if (edn_text) {
    vev_string_free(edn_text);
  }

  db_before = wrap_db(env, before);
  if (!db_before) {
    if (after) {
      vev_db_release(after);
    }
    vev_tx_report_free(report);
    return nullptr;
  }
  db_after = wrap_db(env, after);
  if (!db_after) {
    vev_tx_report_free(report);
    return nullptr;
  }
  vev_tx_report_free(report);

  ok(env, napi_set_named_property(env, out, "edn", edn));
  ok(env, napi_set_named_property(env, out, "dbBefore", db_before));
  ok(env, napi_set_named_property(env, out, "dbAfter", db_after));
  return out;
}

napi_value db_as_of(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  size_t argc = 2;
  napi_value args[2];
  unsigned long long tx = 0;
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  if (argc < 2 || !snapshot || !snapshot->raw ||
      !uint64_arg(env, args[1], &tx)) {
    throw_error(env, "invalid as-of arguments");
    return nullptr;
  }
  return wrap_db(env, vev_db_as_of(snapshot->raw, tx));
}

napi_value db_as_of_instant_millis(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  size_t argc = 2;
  napi_value args[2];
  long long unix_millis = 0;
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  if (argc < 2 || !snapshot || !snapshot->raw ||
      !int64_arg(env, args[1], &unix_millis)) {
    throw_error(env, "invalid as-of instant arguments");
    return nullptr;
  }
  return wrap_db(env,
                 vev_db_as_of_instant_millis(snapshot->raw, unix_millis));
}

napi_value db_since(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  size_t argc = 2;
  napi_value args[2];
  unsigned long long tx = 0;
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  if (argc < 2 || !snapshot || !snapshot->raw ||
      !uint64_arg(env, args[1], &tx)) {
    throw_error(env, "invalid since arguments");
    return nullptr;
  }
  return wrap_db(env, vev_db_since(snapshot->raw, tx));
}

napi_value db_since_instant_millis(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  size_t argc = 2;
  napi_value args[2];
  long long unix_millis = 0;
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  if (argc < 2 || !snapshot || !snapshot->raw ||
      !int64_arg(env, args[1], &unix_millis)) {
    throw_error(env, "invalid since instant arguments");
    return nullptr;
  }
  return wrap_db(env,
                 vev_db_since_instant_millis(snapshot->raw, unix_millis));
}

napi_value db_history(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  if (!snapshot || !snapshot->raw) {
    throw_error(env, "invalid history arguments");
    return nullptr;
  }
  return wrap_db(env, vev_db_history(snapshot->raw));
}

napi_value pull(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  char *pattern = string_arg(env, info, 1);
  double entity = 0;
  size_t argc = 3;
  napi_value args[3];
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  if (argc < 3 || !ok(env, napi_get_value_double(env, args[2], &entity)) ||
      !snapshot || !snapshot->raw || !pattern) {
    free(pattern);
    throw_error(env, "invalid pull arguments");
    return nullptr;
  }
  vev_value_handle_t handle = vev_pull_edn(snapshot->raw, pattern, static_cast<unsigned long long>(entity));
  free(pattern);
  if (!handle) {
    throw_error(env, "pull returned null value handle");
    return nullptr;
  }
  napi_value out = js_value(env, vev_value_handle_value(handle));
  vev_value_handle_free(handle);
  return out;
}

napi_value pull_lookup_ref_string(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  char *pattern = string_arg(env, info, 1);
  char *attr = string_arg(env, info, 2);
  char *value = string_arg(env, info, 3);
  if (!snapshot || !snapshot->raw || !pattern || !attr || !value) {
    free(pattern);
    free(attr);
    free(value);
    throw_error(env, "invalid lookup-ref pull arguments");
    return nullptr;
  }
  vev_value_handle_t handle = vev_pull_lookup_ref_string_edn(snapshot->raw, pattern, attr, value);
  free(pattern);
  free(attr);
  free(value);
  if (!handle) {
    throw_error(env, "lookup-ref pull returned null value handle");
    return nullptr;
  }
  napi_value out = js_value(env, vev_value_handle_value(handle));
  vev_value_handle_free(handle);
  return out;
}

napi_value pull_many(napi_env env, napi_callback_info info) {
  DB *snapshot = external_arg<DB>(env, info, 0);
  char *pattern = string_arg(env, info, 1);
  size_t argc = 3;
  napi_value args[3];
  ok(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
  bool is_array = false;
  if (argc < 3 || !ok(env, napi_is_array(env, args[2], &is_array)) || !is_array ||
      !snapshot || !snapshot->raw || !pattern) {
    free(pattern);
    throw_error(env, "invalid pull-many arguments");
    return nullptr;
  }
  uint32_t count = 0;
  ok(env, napi_get_array_length(env, args[2], &count));
  unsigned long long *entities =
      static_cast<unsigned long long *>(malloc(sizeof(unsigned long long) * count));
  if (!entities && count > 0) {
    free(pattern);
    throw_error(env, "out of memory");
    return nullptr;
  }
  for (uint32_t i = 0; i < count; i++) {
    napi_value item;
    double entity = 0;
    if (!ok(env, napi_get_element(env, args[2], i, &item)) ||
        !ok(env, napi_get_value_double(env, item, &entity))) {
      free(pattern);
      free(entities);
      return nullptr;
    }
    entities[i] = static_cast<unsigned long long>(entity);
  }
  vev_value_handle_t handle = vev_pull_many_edn(snapshot->raw, pattern, entities, count);
  free(pattern);
  free(entities);
  if (!handle) {
    throw_error(env, "pull-many returned null value handle");
    return nullptr;
  }
  napi_value out = js_value(env, vev_value_handle_value(handle));
  vev_value_handle_free(handle);
  return out;
}

napi_value init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"openMemory", nullptr, open_memory, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"connect", nullptr, connect, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"closeConn", nullptr, close_conn, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"closeDurableConn", nullptr, close_durable_conn, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"closeDb", nullptr, close_db, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"closePreparedQuery", nullptr, close_prepared_query, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"db", nullptr, db, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durableDb", nullptr, durable_db, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"transact", nullptr, transact, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durableTransact", nullptr, durable_transact, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durableBackend", nullptr, durable_backend, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durablePath", nullptr, durable_path, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durableBasisT", nullptr, durable_basis_t, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"durableTxCount", nullptr, durable_tx_count, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"queryText", nullptr, query_text, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"prepare", nullptr, prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"preparedQueryEdn", nullptr, prepared_query_edn, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"queryPrepared", nullptr, query_prepared, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"queryPreparedRows", nullptr, query_prepared_rows, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbQueryPrepared", nullptr, db_query_prepared, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbQueryPreparedRows", nullptr, db_query_prepared_rows, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbQ", nullptr, db_q, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbWithReport", nullptr, db_with_report, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbAsOf", nullptr, db_as_of, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbAsOfInstantMillis", nullptr, db_as_of_instant_millis, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbSince", nullptr, db_since, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbSinceInstantMillis", nullptr, db_since_instant_millis, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dbHistory", nullptr, db_history, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"pull", nullptr, pull, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"pullLookupRefString", nullptr, pull_lookup_ref_string, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"pullMany", nullptr, pull_many, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  ok(env, napi_define_properties(env, exports,
                                 sizeof(properties) / sizeof(properties[0]),
                                 properties));
  return exports;
}

} // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, init)
