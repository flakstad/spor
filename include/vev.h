// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

#ifndef VEV_H
#define VEV_H

#include <stdbool.h>

#define VEV_ABI_VERSION 1u

#ifdef __cplusplus
extern "C" {
#endif

typedef void *vev_conn_t;
typedef void *vev_connection_t;
typedef void *vev_sqlite_conn_t;
typedef void *vev_db_t;
typedef void *vev_entity_t;
typedef void *vev_prepared_query_t;
typedef void *vev_prepared_pull_pattern_t;
typedef void *vev_result_t;
typedef void *vev_u64_array_t;
typedef void *vev_string_array_t;
typedef void *vev_entity_int_pairs_t;
typedef void *vev_entity_string_int_triples_t;
typedef void *vev_column_batch_t;
typedef void *vev_stmt_t;
typedef void *vev_tx_report_t;
typedef void *vev_tx_report_array_t;
typedef void *vev_tx_builder_t;
typedef void *vev_tx_fn_registry_t;
typedef const void *vev_tx_fn_args_t;
typedef void *vev_value_handle_t;
typedef const void *vev_value_t;

enum {
    VEV_VALUE_NIL = 0,
    VEV_VALUE_ENTITY = 1,
    VEV_VALUE_STRING = 2,
    VEV_VALUE_INT = 3,
    VEV_VALUE_FLOAT = 4,
    VEV_VALUE_BOOL = 5,
    VEV_VALUE_KEYWORD = 6,
    VEV_VALUE_SYMBOL = 7,
    VEV_VALUE_VECTOR = 8,
    VEV_VALUE_MAP = 9,
    VEV_VALUE_UUID = 10,
    VEV_VALUE_SET = 11,
    VEV_VALUE_INSTANT = 12,
};

enum {
    VEV_VALUE_VISIT_VALUE = 1,
    VEV_VALUE_VISIT_END = 2,
};

enum {
    VEV_RESULT_VISIT_ROW_BEGIN = 1,
    VEV_RESULT_VISIT_VALUE = 2,
    VEV_RESULT_VISIT_PULL = 3,
    VEV_RESULT_VISIT_ROW_END = 4,
};

enum {
    VEV_COLUMN_BATCH_NONE = 0,
    VEV_COLUMN_BATCH_ENTITY = 1,
    VEV_COLUMN_BATCH_STRING = 2,
    VEV_COLUMN_BATCH_ENTITY_INT = 3,
    VEV_COLUMN_BATCH_ENTITY_STRING_INT = 4,
    VEV_COLUMN_BATCH_INT = 5,
    VEV_COLUMN_BATCH_ENTITY_STRING = 6,
    VEV_COLUMN_BATCH_STRING_INT = 7,
    VEV_COLUMN_BATCH_STRING_STRING = 8,
};

enum {
    VEV_COLUMN_KIND_NONE = 0,
    VEV_COLUMN_KIND_ENTITY = 1,
    VEV_COLUMN_KIND_STRING = 2,
    VEV_COLUMN_KIND_INT = 3,
    VEV_COLUMN_KIND_MIXED = 4,
    VEV_COLUMN_KIND_BOOL = 5,
    VEV_COLUMN_KIND_FLOAT = 6,
    VEV_COLUMN_KIND_VALUE = 7,
    VEV_COLUMN_KIND_KEYWORD = 8,
    VEV_COLUMN_KIND_SYMBOL = 9,
    VEV_COLUMN_KIND_UUID = 10,
};

typedef bool (*vev_value_visit_fn)(void *user, int event, vev_value_t value);
typedef bool (*vev_result_visit_fn)(
    void *user,
    int event,
    int row,
    int index,
    vev_value_t value);
typedef const char *(*vev_tx_fn_edn_callback)(
    void *user,
    vev_db_t db,
    int argc,
    vev_tx_fn_args_t args);
typedef void (*vev_tx_report_listener_callback)(void *user, vev_tx_report_t report);

const char *vev_version(void);
unsigned int vev_abi_version(void);

vev_conn_t vev_conn_open_memory(void);
void vev_conn_close(vev_conn_t conn);
vev_connection_t vev_connect(const char *uri);
bool vev_connection_ok(vev_connection_t conn);
const char *vev_connection_error(vev_connection_t conn);
const char *vev_connection_backend(vev_connection_t conn);
const char *vev_connection_path(vev_connection_t conn);
unsigned long long vev_connection_basis_t(vev_connection_t conn);
unsigned long long vev_connection_tx_count(vev_connection_t conn);
vev_u64_array_t vev_connection_tx_ids(vev_connection_t conn);
const char *vev_connection_info_edn(vev_connection_t conn);
void vev_connection_close(vev_connection_t conn);
vev_db_t vev_connection_db(vev_connection_t conn);
const char *vev_connection_query_edn(
    vev_connection_t conn,
    const char *query_text);
const char *vev_connection_query_edn_with_inputs(
    vev_connection_t conn,
    const char *query_text,
    const char *inputs_text);
vev_value_handle_t vev_connection_query_value(
    vev_connection_t conn,
    const char *query_text);
vev_value_handle_t vev_connection_query_value_with_inputs(
    vev_connection_t conn,
    const char *query_text,
    const char *inputs_text);
vev_tx_report_t vev_connection_transact_edn_report(
    vev_connection_t conn,
    const char *tx_text);
vev_tx_report_t vev_connection_transact_edn_report_with_tx_fns(
    vev_connection_t conn,
    const char *tx_text,
    vev_tx_fn_registry_t registry);
vev_tx_report_t vev_connection_tx_commit_report(
    vev_connection_t conn,
    vev_tx_builder_t builder);
vev_tx_report_t vev_connection_tx_commit_many_report(
    vev_connection_t conn,
    vev_tx_builder_t *builders,
    int builder_count);
vev_tx_report_array_t vev_connection_tx_commit_logical_many_reports(
    vev_connection_t conn,
    vev_tx_builder_t *builders,
    int builder_count);
vev_tx_report_array_t vev_connection_transact_many_edn_reports(
    vev_connection_t conn,
    const char **tx_texts,
    int tx_count);
bool vev_connection_compact_indexes(vev_connection_t conn);
bool vev_connection_listen_tx_report(
    vev_connection_t conn,
    const char *name,
    vev_tx_report_listener_callback callback,
    void *user);
bool vev_connection_unlisten_tx_report(vev_connection_t conn, const char *name);
vev_sqlite_conn_t vev_sqlite_conn_open(const char *path);
bool vev_sqlite_conn_ok(vev_sqlite_conn_t conn);
const char *vev_sqlite_conn_error(vev_sqlite_conn_t conn);
void vev_sqlite_conn_close(vev_sqlite_conn_t conn);
vev_db_t vev_sqlite_conn_db(vev_sqlite_conn_t conn);
vev_tx_report_t vev_sqlite_conn_transact_edn_report(
    vev_sqlite_conn_t conn,
    const char *tx_text);
vev_tx_report_t vev_sqlite_conn_transact_edn_report_with_tx_fns(
    vev_sqlite_conn_t conn,
    const char *tx_text,
    vev_tx_fn_registry_t registry);
vev_tx_report_t vev_sqlite_conn_tx_commit_report(
    vev_sqlite_conn_t conn,
    vev_tx_builder_t builder);
vev_tx_report_t vev_sqlite_conn_tx_commit_many_report(
    vev_sqlite_conn_t conn,
    vev_tx_builder_t *builders,
    int builder_count);
vev_tx_report_array_t vev_sqlite_conn_tx_commit_logical_many_reports(
    vev_sqlite_conn_t conn,
    vev_tx_builder_t *builders,
    int builder_count);
vev_tx_report_array_t vev_sqlite_conn_transact_many_edn_reports(
    vev_sqlite_conn_t conn,
    const char **tx_texts,
    int tx_count);
bool vev_sqlite_conn_compact_indexes(vev_sqlite_conn_t conn);
bool vev_sqlite_conn_listen_tx_report(
    vev_sqlite_conn_t conn,
    const char *name,
    vev_tx_report_listener_callback callback,
    void *user);
bool vev_sqlite_conn_unlisten_tx_report(vev_sqlite_conn_t conn, const char *name);
bool vev_conn_listen_tx_report(
    vev_conn_t conn,
    const char *name,
    vev_tx_report_listener_callback callback,
    void *user);
bool vev_conn_unlisten_tx_report(vev_conn_t conn, const char *name);
vev_db_t vev_conn_db(vev_conn_t conn);
/* Resident/in-memory compatibility only. Durable DB handles are immutable
   values; use vev_db_with_edn, vev_with_edn_report, query, and pull on
   vev_db_t instead of converting them back into mutable connections. */
vev_conn_t vev_conn_from_db(vev_db_t db);
vev_db_t vev_db_retain(vev_db_t db);
void vev_db_release(vev_db_t db);
unsigned long long vev_db_basis_t(vev_db_t db);
unsigned long long vev_db_next_t(vev_db_t db);
bool vev_db_has_as_of_t(vev_db_t db);
unsigned long long vev_db_as_of_t(vev_db_t db);
bool vev_db_has_since_t(vev_db_t db);
unsigned long long vev_db_since_t(vev_db_t db);
bool vev_db_is_history(vev_db_t db);
vev_db_t vev_db_as_of(vev_db_t db, unsigned long long tx);
vev_db_t vev_db_as_of_instant_millis(vev_db_t db, long long unix_millis);
vev_db_t vev_db_since(vev_db_t db, unsigned long long tx);
vev_db_t vev_db_since_instant_millis(vev_db_t db, long long unix_millis);
vev_db_t vev_db_history(vev_db_t db);
/* tx-range bound kinds: 0 = open, 1 = t or transaction id, 2 = Unix
   milliseconds. The start is inclusive and the end is exclusive. */
vev_value_handle_t vev_db_tx_range_value(
    vev_db_t db,
    int start_kind,
    long long start_value,
    int end_kind,
    long long end_value);
const char *vev_with_edn(vev_db_t db, const char *tx_text);
vev_tx_report_t vev_with_edn_report(vev_db_t db, const char *tx_text);
vev_db_t vev_db_with_edn(vev_db_t db, const char *tx_text);
vev_entity_t vev_db_entity(vev_db_t db, unsigned long long entity);
vev_entity_t vev_db_entity_lookup_ref_string(vev_db_t db, const char *attr, const char *value);
vev_entity_t vev_db_entity_ident(vev_db_t db, const char *ident);
/* mode: 0 = exact datoms, 1 = forward seek, 2 = reverse seek. */
vev_value_handle_t vev_db_datoms_value(
    vev_db_t db, int mode, const char *index, const char *components_edn);
vev_value_handle_t vev_db_index_range_value(
    vev_db_t db, const char *attr, const char *start_edn, const char *end_edn);
void vev_entity_free(vev_entity_t entity);
bool vev_entity_found(vev_entity_t entity);
unsigned long long vev_entity_id(vev_entity_t entity);
bool vev_entity_contains(vev_entity_t entity, const char *attr);
int vev_entity_attr_flags(vev_entity_t entity, const char *attr);
vev_value_handle_t vev_entity_get(vev_entity_t entity, const char *attr);
vev_value_handle_t vev_entity_values(vev_entity_t entity, const char *attr);
vev_entity_t vev_entity_ref(vev_entity_t entity, const char *attr);
vev_u64_array_t vev_entity_refs(vev_entity_t entity, const char *attr);
vev_value_handle_t vev_entity_touch(vev_entity_t entity);

void vev_string_free(const char *text);

const char *vev_transact_edn(vev_conn_t conn, const char *tx_text);
vev_tx_report_t vev_transact_edn_report(vev_conn_t conn, const char *tx_text);
vev_tx_report_t vev_transact_edn_report_with_tx_fns(
    vev_conn_t conn,
    const char *tx_text,
    vev_tx_fn_registry_t registry);
vev_tx_report_t vev_with_edn_report_with_tx_fns(
    vev_db_t db,
    const char *tx_text,
    vev_tx_fn_registry_t registry);
void vev_tx_report_free(vev_tx_report_t report);
void vev_tx_report_array_free(vev_tx_report_array_t reports);
int vev_tx_report_array_count(vev_tx_report_array_t reports);
vev_tx_report_t vev_tx_report_array_get(vev_tx_report_array_t reports, int index);
vev_value_t vev_tx_report_value(vev_tx_report_t report);
const char *vev_tx_report_edn(vev_tx_report_t report);
vev_db_t vev_tx_report_db_before(vev_tx_report_t report);
vev_db_t vev_tx_report_db_after(vev_tx_report_t report);
vev_tx_builder_t vev_tx_create(int capacity);
void vev_tx_free(vev_tx_builder_t builder);
bool vev_tx_add_string(vev_tx_builder_t builder, unsigned long long e, const char *attr, const char *value);
bool vev_tx_add_keyword(vev_tx_builder_t builder, unsigned long long e, const char *attr, const char *value);
bool vev_tx_add_symbol(vev_tx_builder_t builder, unsigned long long e, const char *attr, const char *value);
bool vev_tx_add_entity(vev_tx_builder_t builder, unsigned long long e, const char *attr, unsigned long long value);
bool vev_tx_add_int(vev_tx_builder_t builder, unsigned long long e, const char *attr, long long value);
bool vev_tx_add_bool(vev_tx_builder_t builder, unsigned long long e, const char *attr, bool value);
vev_tx_report_t vev_tx_commit_report(vev_conn_t conn, vev_tx_builder_t builder);
vev_db_t vev_tx_db_with(vev_db_t db, vev_tx_builder_t builder);
vev_tx_fn_registry_t vev_tx_fn_registry_create(void);
void vev_tx_fn_registry_free(vev_tx_fn_registry_t registry);
bool vev_tx_fn_registry_register_edn(
    vev_tx_fn_registry_t registry,
    const char *ident,
    vev_tx_fn_edn_callback callback,
    void *user);
vev_value_t vev_tx_fn_arg(vev_tx_fn_args_t args, int index);
const char *vev_query_edn(vev_conn_t conn, const char *query_text);
const char *vev_query_edn_with_inputs(
    vev_conn_t conn,
    const char *query_text,
    const char *inputs_text);
vev_value_handle_t vev_query_value(
    vev_conn_t conn,
    const char *query_text);
vev_value_handle_t vev_query_value_with_inputs(
    vev_conn_t conn,
    const char *query_text,
    const char *inputs_text);

vev_prepared_query_t vev_prepare_query_edn(const char *query_text);
vev_prepared_query_t vev_prepare_query_edn_with_sources(
    const char *query_text,
    const char **source_names,
    int source_count);
bool vev_prepared_query_ok(vev_prepared_query_t query);
const char *vev_prepared_query_error(vev_prepared_query_t query);
const char *vev_prepared_query_edn(vev_prepared_query_t query);
const char *vev_parse_clause_edn(const char *clause_text);
void vev_prepared_query_free(vev_prepared_query_t query);
vev_stmt_t vev_stmt_create(vev_prepared_query_t query);
void vev_stmt_clear(vev_stmt_t stmt);
void vev_stmt_free(vev_stmt_t stmt);
const char *vev_stmt_error(vev_stmt_t stmt);
bool vev_stmt_bind_string(vev_stmt_t stmt, const char *value);
bool vev_stmt_bind_keyword(vev_stmt_t stmt, const char *value);
bool vev_stmt_bind_symbol(vev_stmt_t stmt, const char *value);
bool vev_stmt_bind_entity(vev_stmt_t stmt, unsigned long long value);
bool vev_stmt_bind_int(vev_stmt_t stmt, long long value);
bool vev_stmt_bind_bool(vev_stmt_t stmt, bool value);
bool vev_stmt_bind_lookup_ref_string(vev_stmt_t stmt, const char *attr, const char *value);
bool vev_stmt_bind_lookup_ref_keyword(vev_stmt_t stmt, const char *attr, const char *value);
bool vev_stmt_bind_lookup_ref_entity(vev_stmt_t stmt, const char *attr, unsigned long long value);
bool vev_stmt_bind_lookup_ref_int(vev_stmt_t stmt, const char *attr, long long value);
bool vev_stmt_bind_string_collection(vev_stmt_t stmt, const char **values, int value_count);
bool vev_stmt_bind_entity_collection(vev_stmt_t stmt, const unsigned long long *values, int value_count);
bool vev_stmt_bind_int_collection(vev_stmt_t stmt, const long long *values, int value_count);
bool vev_stmt_bind_bool_collection(vev_stmt_t stmt, const bool *values, int value_count);
bool vev_stmt_bind_string_tuple(vev_stmt_t stmt, const char **values, int value_count);
bool vev_stmt_bind_entity_tuple(vev_stmt_t stmt, const unsigned long long *values, int value_count);
bool vev_stmt_bind_int_tuple(vev_stmt_t stmt, const long long *values, int value_count);
bool vev_stmt_bind_bool_tuple(vev_stmt_t stmt, const bool *values, int value_count);
bool vev_stmt_bind_string_relation(vev_stmt_t stmt, const char **values, int value_count, int width);
bool vev_stmt_bind_entity_relation(vev_stmt_t stmt, const unsigned long long *values, int value_count, int width);
bool vev_stmt_bind_int_relation(vev_stmt_t stmt, const long long *values, int value_count, int width);
bool vev_stmt_bind_bool_relation(vev_stmt_t stmt, const bool *values, int value_count, int width);
bool vev_stmt_bind_lookup_ref_string_collection(
    vev_stmt_t stmt,
    const char *attr,
    const char **values,
    int value_count);
bool vev_stmt_bind_lookup_ref_keyword_collection(
    vev_stmt_t stmt,
    const char *attr,
    const char **values,
    int value_count);
bool vev_stmt_bind_lookup_ref_entity_collection(
    vev_stmt_t stmt,
    const char *attr,
    const unsigned long long *values,
    int value_count);
bool vev_stmt_bind_lookup_ref_int_collection(
    vev_stmt_t stmt,
    const char *attr,
    const long long *values,
    int value_count);
bool vev_stmt_bind_pull_pattern_edn(vev_stmt_t stmt, const char *pattern_text);
bool vev_stmt_bind_db_source(vev_stmt_t stmt, const char *name, vev_db_t db);
const char *vev_query_prepared(vev_conn_t conn, vev_prepared_query_t query);
const char *vev_query_prepared_with_inputs(
    vev_conn_t conn,
    vev_prepared_query_t query,
    const char *inputs_text);

vev_result_t vev_query_stmt_result(vev_conn_t conn, vev_stmt_t stmt);
vev_result_t vev_query_db_stmt_result(vev_db_t db, vev_stmt_t stmt);
vev_column_batch_t vev_query_stmt_column_batch(vev_conn_t conn, vev_stmt_t stmt);
vev_column_batch_t vev_query_prepared_column_batch_with_inputs(
    vev_conn_t conn,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_column_batch_t vev_connection_prepared_column_batch_with_inputs(
    vev_connection_t conn,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_column_batch_t vev_sqlite_conn_prepared_column_batch_with_inputs(
    vev_sqlite_conn_t conn,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_column_batch_t vev_query_db_stmt_column_batch(vev_db_t db, vev_stmt_t stmt);
bool vev_query_stmt_visit(
    vev_conn_t conn,
    vev_stmt_t stmt,
    vev_result_visit_fn visitor,
    void *user);
bool vev_query_db_stmt_visit(
    vev_db_t db,
    vev_stmt_t stmt,
    vev_result_visit_fn visitor,
    void *user);
vev_result_t vev_query_prepared_result_with_inputs(
    vev_conn_t conn,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_result_t vev_query_prepared_result_with_rules_text_and_inputs(
    vev_conn_t conn,
    vev_prepared_query_t query,
    const char *rules_text,
    const char *inputs_text);
const char *vev_query_db_prepared_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_value_handle_t vev_db_query_value(
    vev_db_t db,
    const char *query_text);
vev_value_handle_t vev_db_query_value_with_inputs(
    vev_db_t db,
    const char *query_text,
    const char *inputs_text);
vev_result_t vev_query_db_prepared_result_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_result_t vev_query_db_prepared_result_with_rules_text_and_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *rules_text,
    const char *inputs_text);
vev_u64_array_t vev_query_db_prepared_entity_column_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_string_array_t vev_query_db_prepared_string_column_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
void vev_u64_array_free(vev_u64_array_t array);
int vev_u64_array_count(vev_u64_array_t array);
unsigned long long vev_u64_array_value(vev_u64_array_t array, int index);
const unsigned long long *vev_u64_array_data(vev_u64_array_t array);
void vev_string_array_free(vev_string_array_t array);
int vev_string_array_count(vev_string_array_t array);
const void *const *vev_string_array_data_array(vev_string_array_t array);
const int *vev_string_array_lengths_data(vev_string_array_t array);
vev_entity_int_pairs_t vev_query_db_prepared_entity_int_pairs_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
void vev_entity_int_pairs_free(vev_entity_int_pairs_t pairs);
int vev_entity_int_pairs_count(vev_entity_int_pairs_t pairs);
unsigned long long vev_entity_int_pairs_entity(vev_entity_int_pairs_t pairs, int index);
long long vev_entity_int_pairs_value(vev_entity_int_pairs_t pairs, int index);
const unsigned long long *vev_entity_int_pairs_entities_data(vev_entity_int_pairs_t pairs);
const long long *vev_entity_int_pairs_values_data(vev_entity_int_pairs_t pairs);
vev_entity_string_int_triples_t vev_query_db_prepared_entity_string_int_triples_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
vev_column_batch_t vev_query_db_prepared_column_batch_with_inputs(
    vev_db_t db,
    vev_prepared_query_t query,
    const char *inputs_text);
void vev_column_batch_free(vev_column_batch_t batch);
int vev_column_batch_kind(vev_column_batch_t batch);
int vev_column_batch_count(vev_column_batch_t batch);
int vev_column_batch_column_count(vev_column_batch_t batch);
int vev_column_batch_column_kind(vev_column_batch_t batch, int column);
const unsigned long long *vev_column_batch_entities_data(vev_column_batch_t batch);
const long long *vev_column_batch_ints_data(vev_column_batch_t batch);
const void *const *vev_column_batch_string_data_array(vev_column_batch_t batch);
const int *vev_column_batch_string_lengths_data(vev_column_batch_t batch);
const void *const *vev_column_batch_second_string_data_array(vev_column_batch_t batch);
const int *vev_column_batch_second_string_lengths_data(vev_column_batch_t batch);
const unsigned long long *vev_column_batch_column_entities_data(vev_column_batch_t batch, int column);
const long long *vev_column_batch_column_ints_data(vev_column_batch_t batch, int column);
const double *vev_column_batch_column_floats_data(vev_column_batch_t batch, int column);
const bool *vev_column_batch_column_bools_data(vev_column_batch_t batch, int column);
const int *vev_column_batch_column_value_kinds_data(vev_column_batch_t batch, int column);
const vev_value_t *vev_column_batch_column_values_data(vev_column_batch_t batch, int column);
const void *const *vev_column_batch_column_string_data_array(vev_column_batch_t batch, int column);
const int *vev_column_batch_column_string_lengths_data(vev_column_batch_t batch, int column);
int vev_column_batch_string_dictionary_count(vev_column_batch_t batch);
const void *const *vev_column_batch_string_dictionary_data_array(vev_column_batch_t batch);
const int *vev_column_batch_string_dictionary_lengths_data(vev_column_batch_t batch);
const int *vev_column_batch_string_indices_data(vev_column_batch_t batch);
void vev_entity_string_int_triples_free(vev_entity_string_int_triples_t triples);
int vev_entity_string_int_triples_count(vev_entity_string_int_triples_t triples);
const unsigned long long *vev_entity_string_int_triples_entities_data(vev_entity_string_int_triples_t triples);
const long long *vev_entity_string_int_triples_ints_data(vev_entity_string_int_triples_t triples);
const void *const *vev_entity_string_int_triples_string_data_array(vev_entity_string_int_triples_t triples);
const int *vev_entity_string_int_triples_string_lengths_data(vev_entity_string_int_triples_t triples);
int vev_entity_string_int_triples_string_dictionary_count(vev_entity_string_int_triples_t triples);
const void *const *vev_entity_string_int_triples_string_dictionary_data_array(vev_entity_string_int_triples_t triples);
const int *vev_entity_string_int_triples_string_dictionary_lengths_data(vev_entity_string_int_triples_t triples);
const int *vev_entity_string_int_triples_string_indices_data(vev_entity_string_int_triples_t triples);
const char *vev_entity_string_int_triples_string(vev_entity_string_int_triples_t triples, int index);
const void *vev_entity_string_int_triples_string_data(vev_entity_string_int_triples_t triples, int index);
int vev_entity_string_int_triples_string_len(vev_entity_string_int_triples_t triples, int index);

vev_value_handle_t vev_pull_edn(vev_db_t db, const char *pattern_text, unsigned long long entity);
vev_prepared_pull_pattern_t vev_prepare_pull_pattern_edn(const char *pattern_text);
bool vev_prepared_pull_pattern_ok(vev_prepared_pull_pattern_t pattern);
const char *vev_prepared_pull_pattern_error(vev_prepared_pull_pattern_t pattern);
const char *vev_prepared_pull_pattern_edn(vev_prepared_pull_pattern_t pattern);
void vev_prepared_pull_pattern_free(vev_prepared_pull_pattern_t pattern);
vev_value_handle_t vev_pull_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    unsigned long long entity);
vev_value_handle_t vev_pull_lookup_ref_string_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_string_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_keyword_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_keyword_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_uuid_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_uuid_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    const char *value);
vev_value_handle_t vev_pull_lookup_ref_entity_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    unsigned long long value);
vev_value_handle_t vev_pull_lookup_ref_entity_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    unsigned long long value);
vev_value_handle_t vev_pull_lookup_ref_int_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    long long value);
vev_value_handle_t vev_pull_lookup_ref_int_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    long long value);
vev_value_handle_t vev_pull_many_edn(
    vev_db_t db,
    const char *pattern_text,
    const unsigned long long *entities,
    int entity_count);
vev_value_handle_t vev_pull_many_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const unsigned long long *entities,
    int entity_count);
vev_value_handle_t vev_pull_many_lookup_ref_string_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    const char **values,
    int value_count);
vev_value_handle_t vev_pull_many_lookup_ref_string_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    const char **values,
    int value_count);
vev_value_handle_t vev_pull_many_lookup_ref_uuid_edn(
    vev_db_t db,
    const char *pattern_text,
    const char *attr,
    const char **values,
    int value_count);
vev_value_handle_t vev_pull_many_lookup_ref_uuid_prepared(
    vev_db_t db,
    vev_prepared_pull_pattern_t pattern,
    const char *attr,
    const char **values,
    int value_count);
void vev_value_handle_free(vev_value_handle_t handle);
vev_value_t vev_value_handle_value(vev_value_handle_t handle);
const char *vev_value_handle_edn(vev_value_handle_t handle);

void vev_result_free(vev_result_t result);
bool vev_result_ok(vev_result_t result);
const char *vev_result_error(vev_result_t result);
int vev_result_row_count(vev_result_t result);
int vev_result_value_count(vev_result_t result, int row);
int vev_result_value_kind(vev_result_t result, int row, int column);
vev_value_t vev_result_value(vev_result_t result, int row, int column);
int vev_result_pull_count(vev_result_t result, int row);
vev_value_t vev_result_pull(vev_result_t result, int row, int pull);
bool vev_result_visit(vev_result_t result, vev_result_visit_fn visitor, void *user);
unsigned long long vev_result_value_entity(vev_result_t result, int row, int column);
long long vev_result_value_int(vev_result_t result, int row, int column);
bool vev_result_value_bool(vev_result_t result, int row, int column);
const char *vev_result_value_text(vev_result_t result, int row, int column);
const void *vev_result_value_text_data(vev_result_t result, int row, int column);
int vev_result_value_text_len(vev_result_t result, int row, int column);
const char *vev_result_value_edn(vev_result_t result, int row, int column);

int vev_value_kind(vev_value_t value);
unsigned long long vev_value_entity(vev_value_t value);
long long vev_value_int(vev_value_t value);
double vev_value_float(vev_value_t value);
bool vev_value_bool(vev_value_t value);
const char *vev_value_text(vev_value_t value);
const void *vev_value_text_data(vev_value_t value);
int vev_value_text_len(vev_value_t value);
const char *vev_value_edn(vev_value_t value);
int vev_value_item_count(vev_value_t value);
vev_value_t vev_value_item(vev_value_t value, int index);
int vev_value_map_count(vev_value_t value);
vev_value_t vev_value_map_key(vev_value_t value, int index);
vev_value_t vev_value_map_value(vev_value_t value, int index);
bool vev_value_text_equals(vev_value_t value, const char *expected);
vev_value_t vev_value_map_get(vev_value_t value, const char *key);
bool vev_value_visit(vev_value_t value, vev_value_visit_fn visitor, void *user);

#ifdef __cplusplus
}
#endif

#endif
