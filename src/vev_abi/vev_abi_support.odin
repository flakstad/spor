// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev_abi

import "core:strings"

ABI_Conn :: struct {
    conn: vev__Conn,
    tx_sources: [dynamic]string,
    listeners: [dynamic]ABI_Tx_Listener,
}

ABI_SQLite_Conn :: struct {
    store: vev__SQLite_Conn,
    ok: bool,
    error: string,
    tx_sources: [dynamic]string,
    listeners: [dynamic]ABI_Tx_Listener,
}

ABI_Prepared_Query :: struct {
    source: string,
    query: vev__Prepared_Query,
}

ABI_Prepared_Pull_Pattern :: struct {
    source: string,
    pattern: vev__Prepared_Pull_Pattern,
}

ABI_DB_Storage :: struct {
    store_db: vev__Store_DB,
    refs: int,
}

ABI_DB :: struct {
    storage: ^ABI_DB_Storage,
}

ABI_Entity :: struct {
    entity: vev__Store_Entity,
}

ABI_Result :: struct {
    result: vev__Result_Set,
    owns_values: bool,
    pull_values: [dynamic]vev__Value,
    pull_offsets: [dynamic]int,
}

ABI_U64_Array :: struct {
    values: [dynamic]u64,
}

ABI_String_Array :: struct {
    values: [dynamic]string,
    data: [dynamic]rawptr,
    lengths: [dynamic]i32,
}

ABI_I64_Array :: struct {
    values: [dynamic]i64,
}

ABI_Entity_Int_Pairs :: struct {
    entities: [dynamic]u64,
    values: [dynamic]i64,
}

ABI_Entity_String_Int_Triples :: struct {
    entities: [dynamic]u64,
    strings: [dynamic]string,
    ints: [dynamic]i64,
    owns_strings: bool,
    string_data: [dynamic]rawptr,
    string_lengths: [dynamic]i32,
    string_dictionary: [dynamic]string,
    string_dictionary_data: [dynamic]rawptr,
    string_dictionary_lengths: [dynamic]i32,
    string_indices: [dynamic]i32,
}

ABI_String_String_Pairs :: struct {
    first: [dynamic]string,
    second: [dynamic]string,
    owns_strings: bool,
    first_data: [dynamic]rawptr,
    first_lengths: [dynamic]i32,
    second_data: [dynamic]rawptr,
    second_lengths: [dynamic]i32,
}

ABI_Generic_Column :: struct {
    kind: int,
    value_kinds: [dynamic]i32,
    entities: [dynamic]u64,
    ints: [dynamic]i64,
    floats: [dynamic]f64,
    bools: [dynamic]bool,
    strings: [dynamic]string,
    string_data: [dynamic]rawptr,
    string_lengths: [dynamic]i32,
    values: [dynamic]vev__Value,
    value_ptrs: [dynamic]rawptr,
}

ABI_Generic_Column_Batch :: struct {
    rows: int,
    columns: [dynamic]ABI_Generic_Column,
}

ABI_COLUMN_BATCH_NONE :: 0
ABI_COLUMN_BATCH_ENTITY :: 1
ABI_COLUMN_BATCH_STRING :: 2
ABI_COLUMN_BATCH_ENTITY_INT :: 3
ABI_COLUMN_BATCH_ENTITY_STRING_INT :: 4
ABI_COLUMN_BATCH_INT :: 5
ABI_COLUMN_BATCH_ENTITY_STRING :: 6
ABI_COLUMN_BATCH_STRING_INT :: 7
ABI_COLUMN_BATCH_STRING_STRING :: 8

ABI_COLUMN_KIND_NONE :: 0
ABI_COLUMN_KIND_ENTITY :: 1
ABI_COLUMN_KIND_STRING :: 2
ABI_COLUMN_KIND_INT :: 3
ABI_COLUMN_KIND_MIXED :: 4
ABI_COLUMN_KIND_BOOL :: 5
ABI_COLUMN_KIND_FLOAT :: 6
ABI_COLUMN_KIND_VALUE :: 7
ABI_COLUMN_KIND_KEYWORD :: 8
ABI_COLUMN_KIND_SYMBOL :: 9
ABI_COLUMN_KIND_UUID :: 10
ABI_COLUMN_KIND_INSTANT :: 11

ABI_Column_Batch :: struct {
    kind: int,
    handle: rawptr,
    generic: bool,
}

ABI_Tx_Report :: struct {
    value: vev__Value,
    has_store_dbs: bool,
    db_before: vev__Store_DB,
    db_after: vev__Store_DB,
}

ABI_Tx_Report_Array :: struct {
    reports: [dynamic]rawptr,
}

ABI_Tx_Builder :: struct {
    tx_data: [dynamic]vev__Tx_Data,
}

ABI_Tx_Fn_Registry :: struct {
    entries: [dynamic]vev__Tx_Fn_String,
    source_entries: [dynamic]vev__Tx_Fn_Source_String,
    slots: [dynamic]int,
}

ABI_Query_Fn_Registry :: struct {
    entries: [dynamic]vev__Native_Query_Fn,
    predicate_slots: [dynamic]int,
    aggregate_slots: [dynamic]int,
}

ABI_Value_Handle :: struct {
    value: vev__Value,
}

ABI_Value_Visit_Fn :: proc "c" (user: rawptr, event: int, value: rawptr) -> bool
ABI_Result_Visit_Fn :: proc "c" (user: rawptr, event, row, index: int, value: rawptr) -> bool
ABI_Tx_Fn_Edn_Callback :: proc "c" (user: rawptr, db: rawptr, argc: int, args: rawptr) -> cstring
ABI_Query_Predicate_Callback :: proc "c" (user: rawptr, argc: int, args: rawptr) -> bool
ABI_Query_Value_Callback :: proc "c" (user: rawptr, argc: int, args: rawptr) -> cstring
ABI_Tx_Listener_Callback :: proc "c" (user: rawptr, report: rawptr)

ABI_Tx_Listener :: struct {
    name: string,
    callback: ABI_Tx_Listener_Callback,
    user: rawptr,
}

ABI_TX_FN_SLOT_COUNT :: 16
abi_tx_fn_callbacks: [ABI_TX_FN_SLOT_COUNT]ABI_Tx_Fn_Edn_Callback
abi_tx_fn_users: [ABI_TX_FN_SLOT_COUNT]rawptr
abi_tx_fn_used: [ABI_TX_FN_SLOT_COUNT]bool

ABI_QUERY_FN_SLOT_COUNT :: 16
abi_query_predicate_callbacks: [ABI_QUERY_FN_SLOT_COUNT]ABI_Query_Predicate_Callback
abi_query_predicate_users: [ABI_QUERY_FN_SLOT_COUNT]rawptr
abi_query_predicate_used: [ABI_QUERY_FN_SLOT_COUNT]bool
abi_query_value_callbacks: [ABI_QUERY_FN_SLOT_COUNT]ABI_Query_Value_Callback
abi_query_value_users: [ABI_QUERY_FN_SLOT_COUNT]rawptr
abi_query_value_used: [ABI_QUERY_FN_SLOT_COUNT]bool

ABI_Stmt :: struct {
    query: rawptr,
    inputs: [dynamic]vev__Query_Input,
    sources: [dynamic]vev__DB_Read_Named_Source,
    source_handles: [dynamic]rawptr,
    last_error: string,
}

abi_alloc_conn :: proc() -> rawptr {
    wrapper := new(ABI_Conn)
    wrapper.tx_sources = make([dynamic]string)
    wrapper.listeners = make([dynamic]ABI_Tx_Listener)
    return rawptr(wrapper)
}

abi_conn_ptr :: proc(conn: rawptr) -> ^vev__Conn {
    return &((^ABI_Conn)(conn))^.conn
}

abi_conn_store_tx_source :: proc(conn: rawptr, source: string) {
    append(&((^ABI_Conn)(conn))^.tx_sources, source)
}

abi_tx_listener_entry :: proc(name: string, callback: rawptr, user: rawptr) -> ABI_Tx_Listener {
    return ABI_Tx_Listener{
        name = name,
        callback = transmute(ABI_Tx_Listener_Callback)callback,
        user = user,
    }
}

abi_tx_listener_notify :: proc(listener: ABI_Tx_Listener, report: rawptr) {
    if listener.callback == nil {
        return
    }
    listener.callback(listener.user, report)
}

abi_conn_add_tx_listener :: proc(conn: rawptr, name: string, callback: rawptr, user: rawptr) -> bool {
    if conn == nil || callback == nil {
        return false
    }
    wrapper := (^ABI_Conn)(conn)
    for &listener in wrapper.listeners {
        if listener.name == name {
            delete(listener.name)
            listener = abi_tx_listener_entry(name, callback, user)
            return true
        }
    }
    append(&wrapper.listeners, abi_tx_listener_entry(name, callback, user))
    return true
}

abi_conn_remove_tx_listener :: proc(conn: rawptr, name: string) -> bool {
    if conn == nil {
        return false
    }
    wrapper := (^ABI_Conn)(conn)
    for listener, index in wrapper.listeners {
        if listener.name == name {
            delete(wrapper.listeners[index].name)
            ordered_remove(&wrapper.listeners, index)
            return true
        }
    }
    return false
}

abi_conn_notify_tx_listeners :: proc(conn: rawptr, report: rawptr) {
    if conn == nil || report == nil {
        return
    }
    wrapper := (^ABI_Conn)(conn)
    for listener in wrapper.listeners {
        abi_tx_listener_notify(listener, report)
    }
}

abi_free_conn :: proc(conn: rawptr) {
    wrapper := (^ABI_Conn)(conn)
    for source in wrapper.tx_sources {
        delete(source)
    }
    for listener in wrapper.listeners {
        delete(listener.name)
    }
    delete(wrapper.tx_sources)
    delete(wrapper.listeners)
    free(wrapper)
}

abi_alloc_sqlite_conn :: proc(store: vev__SQLite_Conn, ok: bool, error: string) -> rawptr {
    wrapper := new(ABI_SQLite_Conn)
    wrapper.store = store
    wrapper.ok = ok
    wrapper.error = error
    wrapper.tx_sources = make([dynamic]string)
    wrapper.listeners = make([dynamic]ABI_Tx_Listener)
    return rawptr(wrapper)
}

abi_sqlite_conn_ptr :: proc(conn: rawptr) -> ^vev__SQLite_Conn {
    return &((^ABI_SQLite_Conn)(conn))^.store
}

abi_sqlite_conn_ok :: proc(conn: rawptr) -> bool {
    if conn == nil {
        return false
    }
    return ((^ABI_SQLite_Conn)(conn))^.ok
}

abi_sqlite_conn_error :: proc(conn: rawptr) -> string {
    if conn == nil {
        return "null sqlite connection"
    }
    return ((^ABI_SQLite_Conn)(conn))^.error
}

abi_sqlite_conn_path :: proc(conn: rawptr) -> string {
    if conn == nil {
        return ""
    }
    return ((^ABI_SQLite_Conn)(conn))^.store.path
}

abi_sqlite_conn_basis_t :: proc(conn: rawptr) -> u64 {
    if conn == nil {
        return 0
    }
    basis, ok, _ := vev__sqlite_conn_basis_t(&((^ABI_SQLite_Conn)(conn))^.store)
    if !ok {
        return 0
    }
    return basis
}

abi_sqlite_conn_store_tx_source :: proc(conn: rawptr, source: string) {
    append(&((^ABI_SQLite_Conn)(conn))^.tx_sources, source)
}

abi_sqlite_conn_add_tx_listener :: proc(conn: rawptr, name: string, callback: rawptr, user: rawptr) -> bool {
    if conn == nil || callback == nil {
        return false
    }
    wrapper := (^ABI_SQLite_Conn)(conn)
    for &listener in wrapper.listeners {
        if listener.name == name {
            delete(listener.name)
            listener = abi_tx_listener_entry(name, callback, user)
            return true
        }
    }
    append(&wrapper.listeners, abi_tx_listener_entry(name, callback, user))
    return true
}

abi_sqlite_conn_remove_tx_listener :: proc(conn: rawptr, name: string) -> bool {
    if conn == nil {
        return false
    }
    wrapper := (^ABI_SQLite_Conn)(conn)
    for listener, index in wrapper.listeners {
        if listener.name == name {
            delete(wrapper.listeners[index].name)
            ordered_remove(&wrapper.listeners, index)
            return true
        }
    }
    return false
}

abi_sqlite_conn_notify_tx_listeners :: proc(conn: rawptr, report: rawptr) {
    if conn == nil || report == nil {
        return
    }
    wrapper := (^ABI_SQLite_Conn)(conn)
    for listener in wrapper.listeners {
        abi_tx_listener_notify(listener, report)
    }
}

abi_free_sqlite_conn :: proc(conn: rawptr) {
    wrapper := (^ABI_SQLite_Conn)(conn)
    if len(wrapper.error) > 0 {
        delete(wrapper.error)
    }
    for source in wrapper.tx_sources {
        delete(source)
    }
    for listener in wrapper.listeners {
        delete(listener.name)
    }
    delete(wrapper.tx_sources)
    delete(wrapper.listeners)
    free(wrapper)
}

abi_alloc_prepared_query :: proc(source: string) -> rawptr {
    wrapper := new(ABI_Prepared_Query)
    wrapper.source = source
    return rawptr(wrapper)
}

abi_prepared_query_ptr :: proc(query: rawptr) -> ^vev__Prepared_Query {
    return &((^ABI_Prepared_Query)(query))^.query
}

abi_free_prepared_query :: proc(query: rawptr) {
    wrapper := (^ABI_Prepared_Query)(query)
    delete(wrapper.source)
    free(wrapper)
}

abi_alloc_prepared_pull_pattern :: proc(source: string) -> rawptr {
    wrapper := new(ABI_Prepared_Pull_Pattern)
    wrapper.source = source
    return rawptr(wrapper)
}

abi_prepared_pull_pattern_ptr :: proc(pattern: rawptr) -> ^vev__Prepared_Pull_Pattern {
    return &((^ABI_Prepared_Pull_Pattern)(pattern))^.pattern
}

abi_free_prepared_pull_pattern :: proc(pattern: rawptr) {
    wrapper := (^ABI_Prepared_Pull_Pattern)(pattern)
    delete(wrapper.source)
    free(wrapper)
}

abi_alloc_db :: proc(store_db: vev__Store_DB) -> rawptr {
    storage := new(ABI_DB_Storage)
    storage.store_db = store_db
    storage.refs = 1
    wrapper := new(ABI_DB)
    wrapper.storage = storage
    return rawptr(wrapper)
}

abi_retain_db :: proc(db: rawptr) -> rawptr {
    wrapper := (^ABI_DB)(db)
    if wrapper == nil || wrapper.storage == nil {
        return nil
    }
    wrapper.storage.refs += 1
    retained := new(ABI_DB)
    retained.storage = wrapper.storage
    return rawptr(retained)
}

abi_db_ptr :: proc(db: rawptr) -> ^vev__DB {
    return &((^ABI_DB)(db))^.storage.store_db.resident
}

abi_store_db_ptr :: proc(db: rawptr) -> ^vev__Store_DB {
    return &((^ABI_DB)(db))^.storage.store_db
}

abi_release_db :: proc(db: rawptr) -> rawptr {
    wrapper := (^ABI_DB)(db)
    if wrapper == nil || wrapper.storage == nil {
        return nil
    }
    storage := wrapper.storage
    storage.refs -= 1
    free(wrapper)
    if storage.refs == 0 {
        return rawptr(storage)
    }
    return nil
}

abi_db_storage_ptr :: proc(storage: rawptr) -> ^vev__DB {
    return &((^ABI_DB_Storage)(storage))^.store_db.resident
}

abi_store_db_storage_ptr :: proc(storage: rawptr) -> ^vev__Store_DB {
    return &((^ABI_DB_Storage)(storage))^.store_db
}

abi_free_db_storage :: proc(storage: rawptr) {
    storage := (^ABI_DB_Storage)(storage)
    free(storage)
}

abi_alloc_result :: proc() -> rawptr {
    wrapper := new(ABI_Result)
    wrapper.pull_values = make([dynamic]vev__Value)
    wrapper.pull_offsets = make([dynamic]int)
    return rawptr(wrapper)
}

abi_result_ptr :: proc(result: rawptr) -> ^vev__Result_Set {
    return &((^ABI_Result)(result))^.result
}

abi_result_set_owns_values :: proc(result: rawptr, owns_values: bool) {
    ((^ABI_Result)(result))^.owns_values = owns_values
}

abi_result_owns_values :: proc(result: rawptr) -> bool {
    return ((^ABI_Result)(result))^.owns_values
}

abi_result_pull_values_ptr :: proc(result: rawptr) -> ^[dynamic]vev__Value {
    return &((^ABI_Result)(result))^.pull_values
}

abi_result_pull_offsets_ptr :: proc(result: rawptr) -> ^[dynamic]int {
    return &((^ABI_Result)(result))^.pull_offsets
}

abi_value_ptr :: proc(value: rawptr) -> ^vev__Value {
    return (^vev__Value)(value)
}

abi_alloc_tx_report :: proc(value: vev__Value) -> rawptr {
    wrapper := new(ABI_Tx_Report)
    wrapper.value = value
    return rawptr(wrapper)
}

abi_alloc_tx_report_with_dbs :: proc(value: vev__Value, db_before: vev__Store_DB, db_after: vev__Store_DB) -> rawptr {
    wrapper := new(ABI_Tx_Report)
    wrapper.value = value
    wrapper.has_store_dbs = true
    wrapper.db_before = db_before
    wrapper.db_after = db_after
    return rawptr(wrapper)
}

abi_tx_report_value_ptr :: proc(report: rawptr) -> ^vev__Value {
    return &((^ABI_Tx_Report)(report))^.value
}

abi_tx_report_has_store_dbs :: proc(report: rawptr) -> bool {
    return ((^ABI_Tx_Report)(report))^.has_store_dbs
}

abi_tx_report_db_before_ptr :: proc(report: rawptr) -> ^vev__Store_DB {
    return &((^ABI_Tx_Report)(report))^.db_before
}

abi_tx_report_db_after_ptr :: proc(report: rawptr) -> ^vev__Store_DB {
    return &((^ABI_Tx_Report)(report))^.db_after
}

abi_free_tx_report :: proc(report: rawptr) {
    free((^ABI_Tx_Report)(report))
}

abi_alloc_tx_report_array :: proc(capacity: int) -> rawptr {
    wrapper := new(ABI_Tx_Report_Array)
    wrapper.reports = make([dynamic]rawptr, 0, capacity)
    return rawptr(wrapper)
}

abi_tx_report_array_reports_ptr :: proc(array: rawptr) -> ^[dynamic]rawptr {
    return &((^ABI_Tx_Report_Array)(array))^.reports
}

abi_tx_report_array_count :: proc(array: rawptr) -> int {
    if array == nil {
        return 0
    }
    return len(((^ABI_Tx_Report_Array)(array))^.reports)
}

abi_tx_report_array_value :: proc(array: rawptr, index: int) -> rawptr {
    if array == nil {
        return nil
    }
    wrapper := (^ABI_Tx_Report_Array)(array)
    if index < 0 || index >= len(wrapper.reports) {
        return nil
    }
    return wrapper.reports[index]
}

abi_free_tx_report_array :: proc(array: rawptr) {
    wrapper := (^ABI_Tx_Report_Array)(array)
    delete(wrapper.reports)
    free(wrapper)
}

abi_alloc_tx_builder :: proc(capacity: int) -> rawptr {
    wrapper := new(ABI_Tx_Builder)
    wrapper.tx_data = make([dynamic]vev__Tx_Data, 0, capacity)
    return rawptr(wrapper)
}

abi_tx_builder_data_ptr :: proc(builder: rawptr) -> ^[dynamic]vev__Tx_Data {
    return &((^ABI_Tx_Builder)(builder))^.tx_data
}

abi_free_tx_builder :: proc(builder: rawptr) {
    wrapper := (^ABI_Tx_Builder)(builder)
    delete(wrapper.tx_data)
    free(wrapper)
}

abi_alloc_tx_fn_registry :: proc() -> rawptr {
    wrapper := new(ABI_Tx_Fn_Registry)
    wrapper.entries = make([dynamic]vev__Tx_Fn_String)
    wrapper.source_entries = make([dynamic]vev__Tx_Fn_Source_String)
    wrapper.slots = make([dynamic]int)
    return rawptr(wrapper)
}

abi_tx_fn_registry_entries_ptr :: proc(registry: rawptr) -> ^[dynamic]vev__Tx_Fn_String {
    return &((^ABI_Tx_Fn_Registry)(registry))^.entries
}

abi_tx_fn_registry_source_entries_ptr :: proc(registry: rawptr) -> ^[dynamic]vev__Tx_Fn_Source_String {
    return &((^ABI_Tx_Fn_Registry)(registry))^.source_entries
}

abi_tx_fn_registry_slots_ptr :: proc(registry: rawptr) -> ^[dynamic]int {
    return &((^ABI_Tx_Fn_Registry)(registry))^.slots
}

abi_tx_fn_alloc_slot :: proc(callback: rawptr, user: rawptr) -> int {
    if callback == nil {
        return -1
    }
    for i in 0..<ABI_TX_FN_SLOT_COUNT {
        if !abi_tx_fn_used[i] {
            abi_tx_fn_used[i] = true
            abi_tx_fn_callbacks[i] = transmute(ABI_Tx_Fn_Edn_Callback)callback
            abi_tx_fn_users[i] = user
            return i
        }
    }
    return -1
}

abi_tx_fn_free_slot :: proc(slot: int) {
    if slot < 0 || slot >= ABI_TX_FN_SLOT_COUNT {
        return
    }
    abi_tx_fn_used[slot] = false
    abi_tx_fn_callbacks[slot] = nil
    abi_tx_fn_users[slot] = nil
}

abi_tx_fn_call :: proc(slot: int, db: rawptr, argc: int, args: rawptr) -> cstring {
    if slot < 0 || slot >= ABI_TX_FN_SLOT_COUNT || !abi_tx_fn_used[slot] || abi_tx_fn_callbacks[slot] == nil {
        return nil
    }
    return abi_tx_fn_callbacks[slot](abi_tx_fn_users[slot], db, argc, args)
}

abi_tx_fn_arg_ptr :: proc(args: rawptr, index: int) -> rawptr {
    if args == nil || index < 0 {
        return nil
    }
    return rawptr(&(([^]vev__Value)(args))[index])
}

abi_free_tx_fn_registry :: proc(registry: rawptr) {
    wrapper := (^ABI_Tx_Fn_Registry)(registry)
    for slot in wrapper.slots {
        abi_tx_fn_free_slot(slot)
    }
    delete(wrapper.entries)
    delete(wrapper.source_entries)
    delete(wrapper.slots)
    free(wrapper)
}

abi_alloc_query_fn_registry :: proc() -> rawptr {
    wrapper := new(ABI_Query_Fn_Registry)
    wrapper.entries = make([dynamic]vev__Native_Query_Fn)
    wrapper.predicate_slots = make([dynamic]int)
    wrapper.aggregate_slots = make([dynamic]int)
    return rawptr(wrapper)
}

abi_query_fn_registry_entries_ptr :: proc(registry: rawptr) -> ^[dynamic]vev__Native_Query_Fn {
    return &((^ABI_Query_Fn_Registry)(registry))^.entries
}

abi_query_fn_registry_predicate_slots_ptr :: proc(registry: rawptr) -> ^[dynamic]int {
    return &((^ABI_Query_Fn_Registry)(registry))^.predicate_slots
}

abi_query_fn_registry_aggregate_slots_ptr :: proc(registry: rawptr) -> ^[dynamic]int {
    return &((^ABI_Query_Fn_Registry)(registry))^.aggregate_slots
}

abi_query_predicate_alloc_slot :: proc(callback: rawptr, user: rawptr) -> int {
    if callback == nil {
        return -1
    }
    for i in 0..<ABI_QUERY_FN_SLOT_COUNT {
        if !abi_query_predicate_used[i] {
            abi_query_predicate_used[i] = true
            abi_query_predicate_callbacks[i] = transmute(ABI_Query_Predicate_Callback)callback
            abi_query_predicate_users[i] = user
            return i
        }
    }
    return -1
}

abi_query_predicate_free_slot :: proc(slot: int) {
    if slot < 0 || slot >= ABI_QUERY_FN_SLOT_COUNT {
        return
    }
    abi_query_predicate_used[slot] = false
    abi_query_predicate_callbacks[slot] = nil
    abi_query_predicate_users[slot] = nil
}

abi_query_predicate_call :: proc(slot: int, argc: int, args: rawptr) -> bool {
    if slot < 0 || slot >= ABI_QUERY_FN_SLOT_COUNT || !abi_query_predicate_used[slot] || abi_query_predicate_callbacks[slot] == nil {
        return false
    }
    return abi_query_predicate_callbacks[slot](abi_query_predicate_users[slot], argc, args)
}

abi_query_value_alloc_slot :: proc(callback: rawptr, user: rawptr) -> int {
    if callback == nil {
        return -1
    }
    for i in 0..<ABI_QUERY_FN_SLOT_COUNT {
        if !abi_query_value_used[i] {
            abi_query_value_used[i] = true
            abi_query_value_callbacks[i] = transmute(ABI_Query_Value_Callback)callback
            abi_query_value_users[i] = user
            return i
        }
    }
    return -1
}

abi_query_value_free_slot :: proc(slot: int) {
    if slot < 0 || slot >= ABI_QUERY_FN_SLOT_COUNT {
        return
    }
    abi_query_value_used[slot] = false
    abi_query_value_callbacks[slot] = nil
    abi_query_value_users[slot] = nil
}

abi_query_value_call :: proc(slot: int, argc: int, args: rawptr) -> cstring {
    if slot < 0 || slot >= ABI_QUERY_FN_SLOT_COUNT || !abi_query_value_used[slot] || abi_query_value_callbacks[slot] == nil {
        return nil
    }
    return abi_query_value_callbacks[slot](abi_query_value_users[slot], argc, args)
}

abi_free_query_fn_registry :: proc(registry: rawptr) {
    wrapper := (^ABI_Query_Fn_Registry)(registry)
    for slot in wrapper.predicate_slots {
        abi_query_predicate_free_slot(slot)
    }
    for slot in wrapper.aggregate_slots {
        abi_query_value_free_slot(slot)
    }
    delete(wrapper.entries)
    delete(wrapper.predicate_slots)
    delete(wrapper.aggregate_slots)
    free(wrapper)
}

abi_alloc_value_handle :: proc(value: vev__Value) -> rawptr {
    wrapper := new(ABI_Value_Handle)
    wrapper.value = value
    return rawptr(wrapper)
}

abi_value_handle_value_ptr :: proc(handle: rawptr) -> ^vev__Value {
    return &((^ABI_Value_Handle)(handle))^.value
}

abi_free_value_handle :: proc(handle: rawptr) {
    free((^ABI_Value_Handle)(handle))
}

abi_alloc_entity :: proc(entity: vev__Store_Entity) -> rawptr {
    wrapper := new(ABI_Entity)
    wrapper.entity = entity
    return rawptr(wrapper)
}

abi_entity_ptr :: proc(entity: rawptr) -> ^vev__Store_Entity {
    return &((^ABI_Entity)(entity))^.entity
}

abi_free_entity :: proc(entity: rawptr) {
    free((^ABI_Entity)(entity))
}

abi_free_result :: proc(result: rawptr) {
    wrapper := (^ABI_Result)(result)
    delete(wrapper.pull_values)
    delete(wrapper.pull_offsets)
    free(wrapper)
}

abi_alloc_u64_array :: proc(values: [dynamic]u64) -> rawptr {
    wrapper := new(ABI_U64_Array)
    wrapper.values = values
    return rawptr(wrapper)
}

abi_u64_array_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_U64_Array)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.values)
}

abi_u64_array_value :: proc(array: rawptr, index: int) -> u64 {
    wrapper := (^ABI_U64_Array)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.values) {
        return 0
    }
    return wrapper.values[index]
}

abi_u64_array_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_U64_Array)(array)
    if wrapper == nil || len(wrapper.values) == 0 {
        return nil
    }
    return rawptr(&wrapper.values[0])
}

abi_free_u64_array :: proc(array: rawptr) {
    wrapper := (^ABI_U64_Array)(array)
    if wrapper == nil {
        return
    }
    delete(wrapper.values)
    free(wrapper)
}

abi_alloc_string_array :: proc(values: [dynamic]string) -> rawptr {
    wrapper := new(ABI_String_Array)
    wrapper.values = values
    wrapper.data = make([dynamic]rawptr, 0, len(values))
    wrapper.lengths = make([dynamic]i32, 0, len(values))
    for text in values {
        if len(text) == 0 {
            append(&wrapper.data, nil)
        } else {
            append(&wrapper.data, raw_data(text))
        }
        append(&wrapper.lengths, i32(len(text)))
    }
    return rawptr(wrapper)
}

abi_string_array_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_String_Array)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.values)
}

abi_string_array_data_array :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_Array)(array)
    if wrapper == nil || len(wrapper.data) == 0 {
        return nil
    }
    return rawptr(&wrapper.data[0])
}

abi_string_array_lengths_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_Array)(array)
    if wrapper == nil || len(wrapper.lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.lengths[0])
}

abi_free_string_array :: proc(array: rawptr) {
    wrapper := (^ABI_String_Array)(array)
    if wrapper == nil {
        return
    }
    for text in wrapper.values {
        delete(text)
    }
    delete(wrapper.values)
    delete(wrapper.data)
    delete(wrapper.lengths)
    free(wrapper)
}

abi_alloc_i64_array :: proc(values: [dynamic]i64) -> rawptr {
    wrapper := new(ABI_I64_Array)
    wrapper.values = values
    return rawptr(wrapper)
}

abi_i64_array_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_I64_Array)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.values)
}

abi_i64_array_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_I64_Array)(array)
    if wrapper == nil || len(wrapper.values) == 0 {
        return nil
    }
    return rawptr(&wrapper.values[0])
}

abi_free_i64_array :: proc(array: rawptr) {
    wrapper := (^ABI_I64_Array)(array)
    if wrapper == nil {
        return
    }
    delete(wrapper.values)
    free(wrapper)
}

abi_alloc_entity_int_pairs :: proc(columns: vev__Entity_Int_Pair_Columns) -> rawptr {
    wrapper := new(ABI_Entity_Int_Pairs)
    wrapper.entities = columns.entities
    wrapper.values = columns.values
    return rawptr(wrapper)
}

abi_entity_int_pairs_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.entities)
}

abi_entity_int_pairs_entity :: proc(array: rawptr, index: int) -> u64 {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.entities) {
        return 0
    }
    return wrapper.entities[index]
}

abi_entity_int_pairs_value :: proc(array: rawptr, index: int) -> i64 {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.values) {
        return 0
    }
    return wrapper.values[index]
}

abi_entity_int_pairs_entities_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil || len(wrapper.entities) == 0 {
        return nil
    }
    return rawptr(&wrapper.entities[0])
}

abi_entity_int_pairs_values_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil || len(wrapper.values) == 0 {
        return nil
    }
    return rawptr(&wrapper.values[0])
}

abi_free_entity_int_pairs :: proc(array: rawptr) {
    wrapper := (^ABI_Entity_Int_Pairs)(array)
    if wrapper == nil {
        return
    }
    delete(wrapper.entities)
    delete(wrapper.values)
    free(wrapper)
}

abi_alloc_entity_string_int_triples_with_ownership :: proc(columns: vev__Entity_String_Int_Triples, owns_strings: bool) -> rawptr {
    wrapper := new(ABI_Entity_String_Int_Triples)
    wrapper.entities = columns.entities
    wrapper.strings = columns.strings
    wrapper.ints = columns.ints
    wrapper.owns_strings = owns_strings
    wrapper.string_data = make([dynamic]rawptr, 0, len(columns.strings))
    wrapper.string_lengths = make([dynamic]i32, 0, len(columns.strings))
    wrapper.string_dictionary = make([dynamic]string)
    wrapper.string_dictionary_data = make([dynamic]rawptr)
    wrapper.string_dictionary_lengths = make([dynamic]i32)
    for text in columns.strings {
        append(&wrapper.string_data, raw_data(text))
        append(&wrapper.string_lengths, i32(len(text)))
    }
    sample_count := min(len(columns.strings), 256)
    sample_unique := make([dynamic]string)
    defer delete(sample_unique)
    for text, index in columns.strings {
        if index >= sample_count {
            break
        }
        found := false
        for unique in sample_unique {
            if unique == text {
                found = true
                break
            }
        }
        if !found {
            append(&sample_unique, text)
        }
    }
    if sample_count > 0 && len(sample_unique) * 2 <= sample_count {
        wrapper.string_indices = make([dynamic]i32, 0, len(columns.strings))
        for text in columns.strings {
            found_index: i32 = -1
            for unique, unique_index in wrapper.string_dictionary {
                if unique == text {
                    found_index = i32(unique_index)
                    break
                }
            }
            if found_index >= 0 {
                append(&wrapper.string_indices, found_index)
            } else {
                next := i32(len(wrapper.string_dictionary))
                append(&wrapper.string_dictionary, text)
                append(&wrapper.string_dictionary_data, raw_data(text))
                append(&wrapper.string_dictionary_lengths, i32(len(text)))
                append(&wrapper.string_indices, next)
            }
        }
    } else {
        wrapper.string_indices = make([dynamic]i32)
    }
    return rawptr(wrapper)
}

abi_alloc_entity_string_int_triples :: proc(columns: vev__Entity_String_Int_Triples) -> rawptr {
    return abi_alloc_entity_string_int_triples_with_ownership(columns, columns.owns_strings)
}

abi_alloc_entity_string_pairs :: proc(columns: vev__Entity_String_Pair_Columns) -> rawptr {
    triples := vev__Entity_String_Int_Triples{
        entities = columns.entities,
        strings = columns.strings,
        ints = make([dynamic]i64),
        owns_strings = columns.owns_strings,
    }
    return abi_alloc_entity_string_int_triples(triples)
}

abi_alloc_string_string_pairs :: proc(columns: vev__String_String_Pair_Columns) -> rawptr {
    wrapper := new(ABI_String_String_Pairs)
    wrapper.first = columns.first
    wrapper.second = columns.second
    wrapper.owns_strings = columns.owns_strings
    wrapper.first_data = make([dynamic]rawptr, 0, len(columns.first))
    wrapper.first_lengths = make([dynamic]i32, 0, len(columns.first))
    wrapper.second_data = make([dynamic]rawptr, 0, len(columns.second))
    wrapper.second_lengths = make([dynamic]i32, 0, len(columns.second))
    for text in columns.first {
        append(&wrapper.first_data, raw_data(text))
        append(&wrapper.first_lengths, i32(len(text)))
    }
    for text in columns.second {
        append(&wrapper.second_data, raw_data(text))
        append(&wrapper.second_lengths, i32(len(text)))
    }
    return rawptr(wrapper)
}

abi_string_string_pairs_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.first)
}

abi_string_string_pairs_first_data_array :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil || len(wrapper.first_data) == 0 {
        return nil
    }
    return rawptr(&wrapper.first_data[0])
}

abi_string_string_pairs_first_lengths_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil || len(wrapper.first_lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.first_lengths[0])
}

abi_string_string_pairs_second_data_array :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil || len(wrapper.second_data) == 0 {
        return nil
    }
    return rawptr(&wrapper.second_data[0])
}

abi_string_string_pairs_second_lengths_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil || len(wrapper.second_lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.second_lengths[0])
}

abi_entity_string_int_triples_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.entities)
}

abi_entity_string_int_triples_entities_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.entities) == 0 {
        return nil
    }
    return rawptr(&wrapper.entities[0])
}

abi_entity_string_int_triples_ints_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.ints) == 0 {
        return nil
    }
    return rawptr(&wrapper.ints[0])
}

abi_entity_string_int_triples_string_data_array :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.string_data) == 0 {
        return nil
    }
    return rawptr(&wrapper.string_data[0])
}

abi_entity_string_int_triples_string_lengths_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.string_lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.string_lengths[0])
}

abi_entity_string_int_triples_string_dictionary_count :: proc(array: rawptr) -> int {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.string_dictionary)
}

abi_entity_string_int_triples_string_dictionary_data_array :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.string_dictionary_data) == 0 {
        return nil
    }
    return rawptr(&wrapper.string_dictionary_data[0])
}

abi_entity_string_int_triples_string_dictionary_lengths_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.string_dictionary_lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.string_dictionary_lengths[0])
}

abi_entity_string_int_triples_string_indices_data :: proc(array: rawptr) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || len(wrapper.string_indices) == 0 {
        return nil
    }
    return rawptr(&wrapper.string_indices[0])
}

abi_entity_string_int_triples_string :: proc(array: rawptr, index: int) -> cstring {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.strings) {
        return nil
    }
    return c_string_owned(wrapper.strings[index])
}

abi_entity_string_int_triples_string_data :: proc(array: rawptr, index: int) -> rawptr {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.strings) {
        return nil
    }
    text := wrapper.strings[index]
    if len(text) == 0 {
        return nil
    }
    return raw_data(text)
}

abi_entity_string_int_triples_string_len :: proc(array: rawptr, index: int) -> int {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil || index < 0 || index >= len(wrapper.strings) {
        return 0
    }
    return len(wrapper.strings[index])
}

abi_free_entity_string_int_triples :: proc(array: rawptr) {
    wrapper := (^ABI_Entity_String_Int_Triples)(array)
    if wrapper == nil {
        return
    }
    if wrapper.owns_strings {
        for text in wrapper.strings {
            delete(text)
        }
    }
    delete(wrapper.entities)
    delete(wrapper.strings)
    delete(wrapper.ints)
    delete(wrapper.string_data)
    delete(wrapper.string_lengths)
    delete(wrapper.string_dictionary)
    delete(wrapper.string_dictionary_data)
    delete(wrapper.string_dictionary_lengths)
    delete(wrapper.string_indices)
    free(wrapper)
}

abi_free_string_string_pairs :: proc(array: rawptr) {
    wrapper := (^ABI_String_String_Pairs)(array)
    if wrapper == nil {
        return
    }
    if wrapper.owns_strings {
        for text in wrapper.first {
            delete(text)
        }
        for text in wrapper.second {
            delete(text)
        }
    }
    delete(wrapper.first)
    delete(wrapper.second)
    delete(wrapper.first_data)
    delete(wrapper.first_lengths)
    delete(wrapper.second_data)
    delete(wrapper.second_lengths)
    free(wrapper)
}

abi_column_kind_is_text :: proc(kind: int) -> bool {
    return kind == ABI_COLUMN_KIND_STRING ||
           kind == ABI_COLUMN_KIND_KEYWORD ||
           kind == ABI_COLUMN_KIND_SYMBOL ||
           kind == ABI_COLUMN_KIND_UUID
}

abi_generic_column_empty :: proc(kind: int, capacity: int) -> ABI_Generic_Column {
    column: ABI_Generic_Column
    column.kind = kind
    if kind == ABI_COLUMN_KIND_ENTITY {
        column.entities = make([dynamic]u64, 0, capacity)
    } else if kind == ABI_COLUMN_KIND_INT || kind == ABI_COLUMN_KIND_INSTANT {
        column.ints = make([dynamic]i64, 0, capacity)
    } else if kind == ABI_COLUMN_KIND_BOOL {
        column.bools = make([dynamic]bool, 0, capacity)
    } else if kind == ABI_COLUMN_KIND_FLOAT {
        column.floats = make([dynamic]f64, 0, capacity)
    } else if abi_column_kind_is_text(kind) {
        column.strings = make([dynamic]string, 0, capacity)
        column.string_data = make([dynamic]rawptr, 0, capacity)
        column.string_lengths = make([dynamic]i32, 0, capacity)
    } else if kind == ABI_COLUMN_KIND_MIXED {
        column.value_kinds = make([dynamic]i32, 0, capacity)
        column.entities = make([dynamic]u64, 0, capacity)
        column.ints = make([dynamic]i64, 0, capacity)
        column.floats = make([dynamic]f64, 0, capacity)
        column.bools = make([dynamic]bool, 0, capacity)
        column.strings = make([dynamic]string, 0, capacity)
        column.string_data = make([dynamic]rawptr, 0, capacity)
        column.string_lengths = make([dynamic]i32, 0, capacity)
    } else if kind == ABI_COLUMN_KIND_VALUE {
        column.values = make([dynamic]vev__Value, 0, capacity)
        column.value_ptrs = make([dynamic]rawptr, 0, capacity)
    }
    return column
}

abi_generic_column_delete :: proc(column: ^ABI_Generic_Column) {
    delete(column.value_kinds)
    delete(column.entities)
    delete(column.ints)
    delete(column.floats)
    delete(column.bools)
    for text in column.strings {
        if len(text) > 0 {
            delete(text)
        }
    }
    delete(column.strings)
    delete(column.string_data)
    delete(column.string_lengths)
    for value in column.values {
        vev__delete_owned_value(value)
    }
    delete(column.values)
    delete(column.value_ptrs)
}

abi_alloc_generic_column_batch :: proc(kinds: [dynamic]int, rows: int) -> rawptr {
    wrapper := new(ABI_Generic_Column_Batch)
    wrapper.rows = rows
    wrapper.columns = make([dynamic]ABI_Generic_Column, 0, len(kinds))
    for kind in kinds {
        append(&wrapper.columns, abi_generic_column_empty(kind, rows))
    }
    return rawptr(wrapper)
}

abi_generic_column_batch_set_count :: proc(batch: rawptr, rows: int) {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil {
        return
    }
    wrapper.rows = rows
}

abi_generic_column_batch_column_count :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil {
        return 0
    }
    return len(wrapper.columns)
}

abi_generic_column_batch_count :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil {
        return 0
    }
    return wrapper.rows
}

abi_generic_column_batch_column_kind :: proc(batch: rawptr, column: int) -> int {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) {
        return ABI_COLUMN_KIND_NONE
    }
    return wrapper.columns[column].kind
}

abi_generic_column_batch_append_entity :: proc(batch: rawptr, column: int, value: u64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_ENTITY {
        return false
    }
    append(&wrapper.columns[column].entities, value)
    return true
}

abi_generic_column_batch_append_int :: proc(batch: rawptr, column: int, value: i64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_INT {
        return false
    }
    append(&wrapper.columns[column].ints, value)
    return true
}

abi_generic_column_batch_append_instant :: proc(batch: rawptr, column: int, value: i64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_INSTANT {
        return false
    }
    append(&wrapper.columns[column].ints, value)
    return true
}

abi_generic_column_batch_append_bool :: proc(batch: rawptr, column: int, value: bool) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_BOOL {
        return false
    }
    append(&wrapper.columns[column].bools, value)
    return true
}

abi_generic_column_batch_append_float :: proc(batch: rawptr, column: int, value: f64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_FLOAT {
        return false
    }
    append(&wrapper.columns[column].floats, value)
    return true
}

abi_generic_column_batch_append_string_owned :: proc(batch: rawptr, column: int, value: string) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || !abi_column_kind_is_text(wrapper.columns[column].kind) {
        delete(value)
        return false
    }
    append(&wrapper.columns[column].strings, value)
    if len(value) == 0 {
        append(&wrapper.columns[column].string_data, nil)
    } else {
        append(&wrapper.columns[column].string_data, raw_data(value))
    }
    append(&wrapper.columns[column].string_lengths, i32(len(value)))
    return true
}

abi_generic_column_batch_append_mixed_nil :: proc(batch: rawptr, column: int) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 0)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, 0)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_entity :: proc(batch: rawptr, column: int, value: u64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 1)
    append(&wrapper.columns[column].entities, value)
    append(&wrapper.columns[column].ints, 0)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_int :: proc(batch: rawptr, column: int, value: i64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 3)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, value)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_instant :: proc(batch: rawptr, column: int, value: i64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 12)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, value)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_float :: proc(batch: rawptr, column: int, value: f64) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 4)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, 0)
    append(&wrapper.columns[column].floats, value)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_bool :: proc(batch: rawptr, column: int, value: bool) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        return false
    }
    append(&wrapper.columns[column].value_kinds, 5)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, 0)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, value)
    append(&wrapper.columns[column].strings, "")
    append(&wrapper.columns[column].string_data, nil)
    append(&wrapper.columns[column].string_lengths, 0)
    return true
}

abi_generic_column_batch_append_mixed_string_owned :: proc(batch: rawptr, column: int, kind: i32, value: string) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_MIXED {
        delete(value)
        return false
    }
    append(&wrapper.columns[column].value_kinds, kind)
    append(&wrapper.columns[column].entities, 0)
    append(&wrapper.columns[column].ints, 0)
    append(&wrapper.columns[column].floats, 0)
    append(&wrapper.columns[column].bools, false)
    append(&wrapper.columns[column].strings, value)
    if len(value) == 0 {
        append(&wrapper.columns[column].string_data, nil)
    } else {
        append(&wrapper.columns[column].string_data, raw_data(value))
    }
    append(&wrapper.columns[column].string_lengths, i32(len(value)))
    return true
}

abi_generic_column_batch_append_value_owned :: proc(batch: rawptr, column: int, value: vev__Value) -> bool {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_VALUE {
        vev__delete_owned_value(value)
        return false
    }
    append(&wrapper.columns[column].values, value)
    return true
}

abi_generic_column_batch_entities_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].entities) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].entities[0])
}

abi_generic_column_batch_ints_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].ints) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].ints[0])
}

abi_generic_column_batch_floats_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].floats) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].floats[0])
}

abi_generic_column_batch_bools_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].bools) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].bools[0])
}

abi_generic_column_batch_value_kinds_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].value_kinds) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].value_kinds[0])
}

abi_generic_column_batch_values_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || wrapper.columns[column].kind != ABI_COLUMN_KIND_VALUE || len(wrapper.columns[column].values) == 0 {
        return nil
    }
    clear(&wrapper.columns[column].value_ptrs)
    for index in 0..<len(wrapper.columns[column].values) {
        append(&wrapper.columns[column].value_ptrs, rawptr(&wrapper.columns[column].values[index]))
    }
    return rawptr(&wrapper.columns[column].value_ptrs[0])
}

abi_generic_column_batch_string_data_array :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].string_data) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].string_data[0])
}

abi_generic_column_batch_string_lengths_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil || column < 0 || column >= len(wrapper.columns) || len(wrapper.columns[column].string_lengths) == 0 {
        return nil
    }
    return rawptr(&wrapper.columns[column].string_lengths[0])
}

abi_free_generic_column_batch :: proc(batch: rawptr) {
    wrapper := (^ABI_Generic_Column_Batch)(batch)
    if wrapper == nil {
        return
    }
    for &column in wrapper.columns {
        abi_generic_column_delete(&column)
    }
    delete(wrapper.columns)
    free(wrapper)
}

abi_alloc_column_batch :: proc(kind: int, handle: rawptr) -> rawptr {
    if handle == nil {
        return nil
    }
    wrapper := new(ABI_Column_Batch)
    wrapper.kind = kind
    wrapper.handle = handle
    wrapper.generic = false
    return rawptr(wrapper)
}

abi_alloc_column_batch_generic :: proc(kind: int, handle: rawptr) -> rawptr {
    if handle == nil {
        return nil
    }
    wrapper := new(ABI_Column_Batch)
    wrapper.kind = kind
    wrapper.handle = handle
    wrapper.generic = true
    return rawptr(wrapper)
}

abi_column_batch_kind :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return ABI_COLUMN_BATCH_NONE
    }
    return wrapper.kind
}

abi_column_batch_count :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return 0
    }
    if wrapper.generic {
        return abi_generic_column_batch_count(wrapper.handle)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY:
        return abi_u64_array_count(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING:
        return abi_string_array_count(wrapper.handle)
    case ABI_COLUMN_BATCH_INT:
        return abi_i64_array_count(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_INT:
        return abi_entity_int_pairs_count(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return abi_entity_string_int_triples_count(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        return abi_entity_string_int_triples_count(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_INT:
        return abi_entity_string_int_triples_count(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_STRING:
        return abi_string_string_pairs_count(wrapper.handle)
    }
    return 0
}

abi_column_batch_column_count :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return 0
    }
    if wrapper.generic {
        return abi_generic_column_batch_column_count(wrapper.handle)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY, ABI_COLUMN_BATCH_STRING, ABI_COLUMN_BATCH_INT:
        return 1
    case ABI_COLUMN_BATCH_ENTITY_INT, ABI_COLUMN_BATCH_ENTITY_STRING, ABI_COLUMN_BATCH_STRING_INT, ABI_COLUMN_BATCH_STRING_STRING:
        return 2
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return 3
    }
    return 0
}

abi_column_batch_column_kind :: proc(batch: rawptr, column: int) -> int {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil || column < 0 {
        return ABI_COLUMN_KIND_NONE
    }
    if wrapper.generic {
        return abi_generic_column_batch_column_kind(wrapper.handle, column)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY:
        if column == 0 { return ABI_COLUMN_KIND_ENTITY }
    case ABI_COLUMN_BATCH_STRING:
        if column == 0 { return ABI_COLUMN_KIND_STRING }
    case ABI_COLUMN_BATCH_INT:
        if column == 0 { return ABI_COLUMN_KIND_INT }
    case ABI_COLUMN_BATCH_ENTITY_INT:
        if column == 0 { return ABI_COLUMN_KIND_ENTITY }
        if column == 1 { return ABI_COLUMN_KIND_INT }
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        if column == 0 { return ABI_COLUMN_KIND_ENTITY }
        if column == 1 { return ABI_COLUMN_KIND_STRING }
    case ABI_COLUMN_BATCH_STRING_INT:
        if column == 0 { return ABI_COLUMN_KIND_STRING }
        if column == 1 { return ABI_COLUMN_KIND_INT }
    case ABI_COLUMN_BATCH_STRING_STRING:
        if column == 0 || column == 1 { return ABI_COLUMN_KIND_STRING }
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        if column == 0 { return ABI_COLUMN_KIND_ENTITY }
        if column == 1 { return ABI_COLUMN_KIND_STRING }
        if column == 2 { return ABI_COLUMN_KIND_INT }
    }
    return ABI_COLUMN_KIND_NONE
}

abi_column_batch_entities_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_entities_data(wrapper.handle, 0)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY:
        return abi_u64_array_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_INT:
        return abi_entity_int_pairs_entities_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return abi_entity_string_int_triples_entities_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        return abi_entity_string_int_triples_entities_data(wrapper.handle)
    }
    return nil
}

abi_column_batch_column_entities_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_entities_data(wrapper.handle, column)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY:
        if column == 0 { return abi_u64_array_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_INT, ABI_COLUMN_BATCH_ENTITY_STRING, ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        if column == 0 { return abi_column_batch_entities_data(batch) }
    }
    return nil
}

abi_column_batch_ints_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        for column in 0..<abi_generic_column_batch_column_count(wrapper.handle) {
            if abi_generic_column_batch_column_kind(wrapper.handle, column) == ABI_COLUMN_KIND_INT {
                return abi_generic_column_batch_ints_data(wrapper.handle, column)
            }
        }
        return nil
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_INT:
        return abi_i64_array_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_INT:
        return abi_entity_int_pairs_values_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return abi_entity_string_int_triples_ints_data(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_INT:
        return abi_entity_string_int_triples_ints_data(wrapper.handle)
    }
    return nil
}

abi_column_batch_column_ints_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_ints_data(wrapper.handle, column)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_INT:
        if column == 0 { return abi_i64_array_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_INT:
        if column == 1 { return abi_entity_int_pairs_values_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_STRING_INT:
        if column == 1 { return abi_entity_string_int_triples_ints_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        if column == 2 { return abi_entity_string_int_triples_ints_data(wrapper.handle) }
    }
    return nil
}

abi_column_batch_column_floats_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_floats_data(wrapper.handle, column)
    }
    return nil
}

abi_column_batch_column_bools_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_bools_data(wrapper.handle, column)
    }
    return nil
}

abi_column_batch_column_value_kinds_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_value_kinds_data(wrapper.handle, column)
    }
    return nil
}

abi_column_batch_column_values_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_values_data(wrapper.handle, column)
    }
    return nil
}

abi_column_batch_string_data_array :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        for column in 0..<abi_generic_column_batch_column_count(wrapper.handle) {
            if abi_generic_column_batch_column_kind(wrapper.handle, column) == ABI_COLUMN_KIND_STRING {
                return abi_generic_column_batch_string_data_array(wrapper.handle, column)
            }
        }
        return nil
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_STRING:
        return abi_string_array_data_array(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return abi_entity_string_int_triples_string_data_array(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        return abi_entity_string_int_triples_string_data_array(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_INT:
        return abi_entity_string_int_triples_string_data_array(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_STRING:
        return abi_string_string_pairs_first_data_array(wrapper.handle)
    }
    return nil
}

abi_column_batch_column_string_data_array :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_string_data_array(wrapper.handle, column)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_STRING:
        if column == 0 { return abi_string_array_data_array(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        if column == 1 { return abi_entity_string_int_triples_string_data_array(wrapper.handle) }
    case ABI_COLUMN_BATCH_STRING_INT:
        if column == 0 { return abi_entity_string_int_triples_string_data_array(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        if column == 1 { return abi_entity_string_int_triples_string_data_array(wrapper.handle) }
    case ABI_COLUMN_BATCH_STRING_STRING:
        if column == 0 { return abi_string_string_pairs_first_data_array(wrapper.handle) }
        if column == 1 { return abi_string_string_pairs_second_data_array(wrapper.handle) }
    }
    return nil
}

abi_column_batch_string_lengths_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        for column in 0..<abi_generic_column_batch_column_count(wrapper.handle) {
            if abi_generic_column_batch_column_kind(wrapper.handle, column) == ABI_COLUMN_KIND_STRING {
                return abi_generic_column_batch_string_lengths_data(wrapper.handle, column)
            }
        }
        return nil
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_STRING:
        return abi_string_array_lengths_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        return abi_entity_string_int_triples_string_lengths_data(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        return abi_entity_string_int_triples_string_lengths_data(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_INT:
        return abi_entity_string_int_triples_string_lengths_data(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_STRING:
        return abi_string_string_pairs_first_lengths_data(wrapper.handle)
    }
    return nil
}

abi_column_batch_column_string_lengths_data :: proc(batch: rawptr, column: int) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return nil
    }
    if wrapper.generic {
        return abi_generic_column_batch_string_lengths_data(wrapper.handle, column)
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_STRING:
        if column == 0 { return abi_string_array_lengths_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        if column == 1 { return abi_entity_string_int_triples_string_lengths_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_STRING_INT:
        if column == 0 { return abi_entity_string_int_triples_string_lengths_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        if column == 1 { return abi_entity_string_int_triples_string_lengths_data(wrapper.handle) }
    case ABI_COLUMN_BATCH_STRING_STRING:
        if column == 0 { return abi_string_string_pairs_first_lengths_data(wrapper.handle) }
        if column == 1 { return abi_string_string_pairs_second_lengths_data(wrapper.handle) }
    }
    return nil
}

abi_column_batch_second_string_data_array :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        string_column := 0
        for column in 0..<abi_generic_column_batch_column_count(wrapper.handle) {
            if abi_generic_column_batch_column_kind(wrapper.handle, column) == ABI_COLUMN_KIND_STRING {
                if string_column == 1 {
                    return abi_generic_column_batch_string_data_array(wrapper.handle, column)
                }
                string_column += 1
            }
        }
        return nil
    }
    if wrapper == nil || wrapper.kind != ABI_COLUMN_BATCH_STRING_STRING {
        return nil
    }
    return abi_string_string_pairs_second_data_array(wrapper.handle)
}

abi_column_batch_second_string_lengths_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        string_column := 0
        for column in 0..<abi_generic_column_batch_column_count(wrapper.handle) {
            if abi_generic_column_batch_column_kind(wrapper.handle, column) == ABI_COLUMN_KIND_STRING {
                if string_column == 1 {
                    return abi_generic_column_batch_string_lengths_data(wrapper.handle, column)
                }
                string_column += 1
            }
        }
        return nil
    }
    if wrapper == nil || wrapper.kind != ABI_COLUMN_BATCH_STRING_STRING {
        return nil
    }
    return abi_string_string_pairs_second_lengths_data(wrapper.handle)
}

abi_column_batch_string_dictionary_count :: proc(batch: rawptr) -> int {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        return 0
    }
    if wrapper == nil || (wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING_INT && wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING && wrapper.kind != ABI_COLUMN_BATCH_STRING_INT) {
        return 0
    }
    return abi_entity_string_int_triples_string_dictionary_count(wrapper.handle)
}

abi_column_batch_string_dictionary_data_array :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        return nil
    }
    if wrapper == nil || (wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING_INT && wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING && wrapper.kind != ABI_COLUMN_BATCH_STRING_INT) {
        return nil
    }
    return abi_entity_string_int_triples_string_dictionary_data_array(wrapper.handle)
}

abi_column_batch_string_dictionary_lengths_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        return nil
    }
    if wrapper == nil || (wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING_INT && wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING && wrapper.kind != ABI_COLUMN_BATCH_STRING_INT) {
        return nil
    }
    return abi_entity_string_int_triples_string_dictionary_lengths_data(wrapper.handle)
}

abi_column_batch_string_indices_data :: proc(batch: rawptr) -> rawptr {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper != nil && wrapper.generic {
        return nil
    }
    if wrapper == nil || (wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING_INT && wrapper.kind != ABI_COLUMN_BATCH_ENTITY_STRING && wrapper.kind != ABI_COLUMN_BATCH_STRING_INT) {
        return nil
    }
    return abi_entity_string_int_triples_string_indices_data(wrapper.handle)
}

abi_free_column_batch :: proc(batch: rawptr) {
    wrapper := (^ABI_Column_Batch)(batch)
    if wrapper == nil {
        return
    }
    if wrapper.generic {
        abi_free_generic_column_batch(wrapper.handle)
        free(wrapper)
        return
    }
    switch wrapper.kind {
    case ABI_COLUMN_BATCH_ENTITY:
        abi_free_u64_array(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING:
        abi_free_string_array(wrapper.handle)
    case ABI_COLUMN_BATCH_INT:
        abi_free_i64_array(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_INT:
        abi_free_entity_int_pairs(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING_INT:
        abi_free_entity_string_int_triples(wrapper.handle)
    case ABI_COLUMN_BATCH_ENTITY_STRING:
        abi_free_entity_string_int_triples(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_INT:
        abi_free_entity_string_int_triples(wrapper.handle)
    case ABI_COLUMN_BATCH_STRING_STRING:
        abi_free_string_string_pairs(wrapper.handle)
    }
    free(wrapper)
}

abi_column_batch_copy_u64_array :: proc(batch: rawptr, column: int) -> rawptr {
    count := abi_column_batch_count(batch)
    if column < 0 || column >= abi_column_batch_column_count(batch) || abi_column_batch_column_kind(batch, column) != ABI_COLUMN_KIND_ENTITY {
        return nil
    }
    data := abi_column_batch_column_entities_data(batch, column)
    if count > 0 && data == nil {
        return nil
    }
    values := make([dynamic]u64, 0, count)
    raw := ([^]u64)(data)
    for i in 0..<count {
        append(&values, raw[i])
    }
    return abi_alloc_u64_array(values)
}

abi_column_batch_copy_string_array :: proc(batch: rawptr, column: int) -> rawptr {
    count := abi_column_batch_count(batch)
    if column < 0 || column >= abi_column_batch_column_count(batch) || abi_column_batch_column_kind(batch, column) != ABI_COLUMN_KIND_STRING {
        return nil
    }
    data := abi_column_batch_column_string_data_array(batch, column)
    lengths := abi_column_batch_column_string_lengths_data(batch, column)
    if count > 0 && (data == nil || lengths == nil) {
        return nil
    }
    values := make([dynamic]string, 0, count)
    raw_data_values := ([^]rawptr)(data)
    raw_lengths := ([^]i32)(lengths)
    for i in 0..<count {
        owned, err := strings.clone_from_ptr((^byte)(raw_data_values[i]), int(raw_lengths[i]))
        if err != nil {
            for value in values {
                delete(value)
            }
            delete(values)
            return nil
        }
        append(&values, owned)
    }
    return abi_alloc_string_array(values)
}

abi_column_batch_copy_entity_int_pairs :: proc(batch: rawptr) -> rawptr {
    count := abi_column_batch_count(batch)
    if abi_column_batch_column_count(batch) != 2 ||
       abi_column_batch_column_kind(batch, 0) != ABI_COLUMN_KIND_ENTITY ||
       abi_column_batch_column_kind(batch, 1) != ABI_COLUMN_KIND_INT {
        return nil
    }
    entity_data := abi_column_batch_column_entities_data(batch, 0)
    int_data := abi_column_batch_column_ints_data(batch, 1)
    if count > 0 && (entity_data == nil || int_data == nil) {
        return nil
    }
    columns := vev__Entity_Int_Pair_Columns{
        entities = make([dynamic]u64, 0, count),
        values = make([dynamic]i64, 0, count),
    }
    raw_entities := ([^]u64)(entity_data)
    raw_ints := ([^]i64)(int_data)
    for i in 0..<count {
        append(&columns.entities, raw_entities[i])
        append(&columns.values, raw_ints[i])
    }
    return abi_alloc_entity_int_pairs(columns)
}

abi_column_batch_copy_entity_string_int_triples :: proc(batch: rawptr) -> rawptr {
    count := abi_column_batch_count(batch)
    if abi_column_batch_column_count(batch) != 3 ||
       abi_column_batch_column_kind(batch, 0) != ABI_COLUMN_KIND_ENTITY ||
       abi_column_batch_column_kind(batch, 1) != ABI_COLUMN_KIND_STRING ||
       abi_column_batch_column_kind(batch, 2) != ABI_COLUMN_KIND_INT {
        return nil
    }
    entity_data := abi_column_batch_column_entities_data(batch, 0)
    string_data := abi_column_batch_column_string_data_array(batch, 1)
    string_lengths := abi_column_batch_column_string_lengths_data(batch, 1)
    int_data := abi_column_batch_column_ints_data(batch, 2)
    if count > 0 && (entity_data == nil || string_data == nil || string_lengths == nil || int_data == nil) {
        return nil
    }
    columns := vev__Entity_String_Int_Triples{
        entities = make([dynamic]u64, 0, count),
        strings = make([dynamic]string, 0, count),
        ints = make([dynamic]i64, 0, count),
        owns_strings = true,
    }
    raw_entities := ([^]u64)(entity_data)
    raw_string_data := ([^]rawptr)(string_data)
    raw_string_lengths := ([^]i32)(string_lengths)
    raw_ints := ([^]i64)(int_data)
    for i in 0..<count {
        owned, err := strings.clone_from_ptr((^byte)(raw_string_data[i]), int(raw_string_lengths[i]))
        if err != nil {
            for value in columns.strings {
                delete(value)
            }
            delete(columns.entities)
            delete(columns.strings)
            delete(columns.ints)
            return nil
        }
        append(&columns.entities, raw_entities[i])
        append(&columns.strings, owned)
        append(&columns.ints, raw_ints[i])
    }
    return abi_alloc_entity_string_int_triples(columns)
}

abi_result_value_ptr :: proc(result: rawptr, row: int, column: int) -> rawptr {
    wrapper := (^ABI_Result)(result)
    if wrapper == nil || row < 0 || column < 0 || row >= len(wrapper.result.rows) || column >= len(wrapper.result.rows[row].values) {
        return nil
    }
    return rawptr(&wrapper.result.rows[row].values[column])
}

abi_result_pull_value_ptr :: proc(result: rawptr, row: int, pull: int) -> rawptr {
    wrapper := (^ABI_Result)(result)
    if wrapper == nil || row < 0 || pull < 0 || row >= len(wrapper.result.rows) || pull >= len(wrapper.result.rows[row].pulls) {
        return nil
    }
    if row >= len(wrapper.pull_offsets) {
        return nil
    }
    flat := wrapper.pull_offsets[row] + pull
    if flat < 0 || flat >= len(wrapper.pull_values) {
        return nil
    }
    return rawptr(&wrapper.pull_values[flat])
}

abi_value_item_ptr :: proc(value: rawptr, index: int) -> rawptr {
    if value == nil || index < 0 {
        return nil
    }
    v := (^vev__Value)(value)
    if (v.kind != .Vector && v.kind != .Set) || index >= len(v.items) {
        return nil
    }
    return rawptr(&v.items[index])
}

abi_value_map_key_ptr :: proc(value: rawptr, index: int) -> rawptr {
    if value == nil || index < 0 {
        return nil
    }
    v := (^vev__Value)(value)
    item_index := index * 2
    if v.kind != .Map || item_index >= len(v.items) {
        return nil
    }
    return rawptr(&v.items[item_index])
}

abi_value_map_value_ptr :: proc(value: rawptr, index: int) -> rawptr {
    if value == nil || index < 0 {
        return nil
    }
    v := (^vev__Value)(value)
    item_index := index * 2 + 1
    if v.kind != .Map || item_index >= len(v.items) {
        return nil
    }
    return rawptr(&v.items[item_index])
}

abi_value_text_data :: proc(value: rawptr) -> rawptr {
    if value == nil {
        return nil
    }
    v := (^vev__Value)(value)
    if v.kind != .String && v.kind != .Keyword && v.kind != .Symbol && v.kind != .Uuid {
        return nil
    }
    if len(v.text) == 0 {
        return nil
    }
    return raw_data(v.text)
}

abi_value_text_len :: proc(value: rawptr) -> int {
    if value == nil {
        return 0
    }
    v := (^vev__Value)(value)
    if v.kind != .String && v.kind != .Keyword && v.kind != .Symbol && v.kind != .Uuid {
        return 0
    }
    return len(v.text)
}

abi_value_visit_walk :: proc(value: ^vev__Value, visitor: ABI_Value_Visit_Fn, user: rawptr) -> bool {
    if value == nil || visitor == nil {
        return false
    }
    if !visitor(user, 1, rawptr(value)) {
        return false
    }
    if value.kind == .Vector || value.kind == .Set || value.kind == .Map {
        for i in 0..<len(value.items) {
            if !abi_value_visit_walk(&value.items[i], visitor, user) {
                return false
            }
        }
        if !visitor(user, 2, rawptr(value)) {
            return false
        }
    }
    return true
}

abi_value_visit :: proc(value: rawptr, visitor: rawptr, user: rawptr) -> bool {
    if value == nil || visitor == nil {
        return false
    }
    cb := transmute(ABI_Value_Visit_Fn)visitor
    return abi_value_visit_walk((^vev__Value)(value), cb, user)
}

abi_result_visit :: proc(result: rawptr, visitor: rawptr, user: rawptr) -> bool {
    wrapper := (^ABI_Result)(result)
    if wrapper == nil || visitor == nil {
        return false
    }
    cb := transmute(ABI_Result_Visit_Fn)visitor
    for row_index in 0..<len(wrapper.result.rows) {
        row := &wrapper.result.rows[row_index]
        if !cb(user, 1, row_index, -1, nil) {
            return false
        }
        for value_index in 0..<len(row.values) {
            if !cb(user, 2, row_index, value_index, rawptr(&row.values[value_index])) {
                return false
            }
        }
        for pull_index in 0..<len(row.pulls) {
            pull_value := abi_result_pull_value_ptr(result, row_index, pull_index)
            if !cb(user, 3, row_index, pull_index, pull_value) {
                return false
            }
        }
        if !cb(user, 4, row_index, -1, nil) {
            return false
        }
    }
    return true
}

abi_alloc_stmt :: proc(query: rawptr) -> rawptr {
    wrapper := new(ABI_Stmt)
    wrapper.query = query
    wrapper.inputs = make([dynamic]vev__Query_Input)
    wrapper.sources = make([dynamic]vev__DB_Read_Named_Source)
    wrapper.source_handles = make([dynamic]rawptr)
    return rawptr(wrapper)
}

abi_stmt_query :: proc(stmt: rawptr) -> rawptr {
    return (^ABI_Stmt)(stmt)^.query
}

abi_stmt_inputs_ptr :: proc(stmt: rawptr) -> ^[dynamic]vev__Query_Input {
    return &((^ABI_Stmt)(stmt))^.inputs
}

abi_stmt_sources_ptr :: proc(stmt: rawptr) -> ^[dynamic]vev__DB_Read_Named_Source {
    return &((^ABI_Stmt)(stmt))^.sources
}

abi_stmt_source_handles_ptr :: proc(stmt: rawptr) -> ^[dynamic]rawptr {
    return &((^ABI_Stmt)(stmt))^.source_handles
}

abi_stmt_error_ptr :: proc(stmt: rawptr) -> ^string {
    return &((^ABI_Stmt)(stmt))^.last_error
}

abi_stmt_push_input :: proc(stmt: rawptr, input: vev__Query_Input) {
    append(&((^ABI_Stmt)(stmt))^.inputs, input)
}

abi_stmt_push_source :: proc(stmt: rawptr, source: vev__DB_Read_Named_Source, handle: rawptr) {
    append(&((^ABI_Stmt)(stmt))^.sources, source)
    append(&((^ABI_Stmt)(stmt))^.source_handles, handle)
}

abi_cstring_at :: proc(values: rawptr, index: int) -> cstring {
    return ([^]cstring)(values)[index]
}

abi_u64_at :: proc(values: rawptr, index: int) -> u64 {
    return ([^]u64)(values)[index]
}

abi_i64_at :: proc(values: rawptr, index: int) -> i64 {
    return ([^]i64)(values)[index]
}

abi_bool_at :: proc(values: rawptr, index: int) -> bool {
    return ([^]bool)(values)[index]
}

abi_rawptr_at :: proc(values: rawptr, index: int) -> rawptr {
    return ([^]rawptr)(values)[index]
}

abi_free_stmt :: proc(stmt: rawptr) {
    wrapper := (^ABI_Stmt)(stmt)
    delete(wrapper.inputs)
    delete(wrapper.sources)
    delete(wrapper.source_handles)
    if len(wrapper.last_error) > 0 {
        delete(wrapper.last_error)
    }
    free(wrapper)
}
