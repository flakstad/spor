// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import "core:dynlib"
import "core:os"
import "core:strings"
import "core:time"

ABI_VERSION :: 1

@(private)
API :: struct {
	abi_version: proc "c" () -> u32 `dynlib:"vev_abi_version"`,
	open_memory: proc "c" () -> rawptr `dynlib:"vev_conn_open_memory"`,
	close_conn: proc "c" (conn: rawptr) `dynlib:"vev_conn_close"`,
	conn_db: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_conn_db"`,
	transact_edn: proc "c" (conn: rawptr, tx_text: cstring) -> cstring `dynlib:"vev_transact_edn"`,
	query_value_with_inputs: proc "c" (conn: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_query_value_with_inputs"`,
	connect: proc "c" (uri: cstring) -> rawptr `dynlib:"vev_connect"`,
	connection_ok: proc "c" (conn: rawptr) -> bool `dynlib:"vev_connection_ok"`,
	connection_error: proc "c" (conn: rawptr) -> cstring `dynlib:"vev_connection_error"`,
	connection_close: proc "c" (conn: rawptr) `dynlib:"vev_connection_close"`,
	connection_db: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_connection_db"`,
	connection_transact_edn_report: proc "c" (conn: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_connection_transact_edn_report"`,
	connection_query_value_with_inputs: proc "c" (conn: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_connection_query_value_with_inputs"`,
	db_release: proc "c" (db: rawptr) `dynlib:"vev_db_release"`,
	db_basis_t: proc "c" (db: rawptr) -> u64 `dynlib:"vev_db_basis_t"`,
	db_next_t: proc "c" (db: rawptr) -> u64 `dynlib:"vev_db_next_t"`,
	db_has_as_of_t: proc "c" (db: rawptr) -> bool `dynlib:"vev_db_has_as_of_t"`,
	db_as_of_t: proc "c" (db: rawptr) -> u64 `dynlib:"vev_db_as_of_t"`,
	db_has_since_t: proc "c" (db: rawptr) -> bool `dynlib:"vev_db_has_since_t"`,
	db_since_t: proc "c" (db: rawptr) -> u64 `dynlib:"vev_db_since_t"`,
	db_is_history: proc "c" (db: rawptr) -> bool `dynlib:"vev_db_is_history"`,
	db_as_of: proc "c" (db: rawptr, tx: u64) -> rawptr `dynlib:"vev_db_as_of"`,
	db_as_of_instant_millis: proc "c" (db: rawptr, unix_millis: i64) -> rawptr `dynlib:"vev_db_as_of_instant_millis"`,
	db_since: proc "c" (db: rawptr, tx: u64) -> rawptr `dynlib:"vev_db_since"`,
	db_since_instant_millis: proc "c" (db: rawptr, unix_millis: i64) -> rawptr `dynlib:"vev_db_since_instant_millis"`,
	db_history: proc "c" (db: rawptr) -> rawptr `dynlib:"vev_db_history"`,
	db_tx_range_value: proc "c" (db: rawptr, start_kind: int, start_value: i64, end_kind: int, end_value: i64) -> rawptr `dynlib:"vev_db_tx_range_value"`,
	db_query_value_with_inputs: proc "c" (db: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_db_query_value_with_inputs"`,
	tx_report_edn: proc "c" (report: rawptr) -> cstring `dynlib:"vev_tx_report_edn"`,
	tx_report_free: proc "c" (report: rawptr) `dynlib:"vev_tx_report_free"`,
	value_handle_free: proc "c" (handle: rawptr) `dynlib:"vev_value_handle_free"`,
	value_handle_value: proc "c" (handle: rawptr) -> rawptr `dynlib:"vev_value_handle_value"`,
	value_handle_edn: proc "c" (handle: rawptr) -> cstring `dynlib:"vev_value_handle_edn"`,
	value_kind: proc "c" (value: rawptr) -> int `dynlib:"vev_value_kind"`,
	value_entity: proc "c" (value: rawptr) -> u64 `dynlib:"vev_value_entity"`,
	value_int: proc "c" (value: rawptr) -> i64 `dynlib:"vev_value_int"`,
	value_float: proc "c" (value: rawptr) -> f64 `dynlib:"vev_value_float"`,
	value_bool: proc "c" (value: rawptr) -> bool `dynlib:"vev_value_bool"`,
	value_text: proc "c" (value: rawptr) -> cstring `dynlib:"vev_value_text"`,
	value_edn: proc "c" (value: rawptr) -> cstring `dynlib:"vev_value_edn"`,
	value_item_count: proc "c" (value: rawptr) -> int `dynlib:"vev_value_item_count"`,
	value_item: proc "c" (value: rawptr, index: int) -> rawptr `dynlib:"vev_value_item"`,
	value_map_count: proc "c" (value: rawptr) -> int `dynlib:"vev_value_map_count"`,
	value_map_key: proc "c" (value: rawptr, index: int) -> rawptr `dynlib:"vev_value_map_key"`,
	value_map_value: proc "c" (value: rawptr, index: int) -> rawptr `dynlib:"vev_value_map_value"`,
	value_map_get: proc "c" (value: rawptr, key: cstring) -> rawptr `dynlib:"vev_value_map_get"`,
	string_free: proc "c" (text: cstring) `dynlib:"vev_string_free"`,
	__handle: dynlib.Library,
}

Library :: struct {
	api: API,
}

Connection :: struct {
	library: ^Library,
	handle: rawptr,
}

Durable_Connection :: struct {
	library: ^Library,
	handle: rawptr,
}

DB :: struct {
	library: ^Library,
	handle: rawptr,
}

Log :: struct {
	database: DB,
}

Data :: struct {
	library: ^Library,
	handle: rawptr,
}

// Value is a borrowed view into Data. It remains valid until its Data is closed.
Value :: struct {
	library: ^Library,
	handle: rawptr,
}

Kind :: enum int {
	Nil,
	Entity,
	String,
	Int,
	Float,
	Bool,
	Keyword,
	Symbol,
	Vector,
	Map,
	UUID,
	Set,
	Instant,
}

library_filename :: proc() -> string {
	when ODIN_OS == .Darwin {
		return "libvev.dylib"
	} else when ODIN_OS == .Linux {
		return "libvev.so"
	} else when ODIN_OS == .Windows {
		return "vev.dll"
	}
	return "libvev"
}

load :: proc(path: string) -> (library: Library, ok: bool) {
	_, loaded := dynlib.initialize_symbols(&library.api, path)
	if !loaded {
		return {}, false
	}

	if library.api.abi_version == nil ||
	   library.api.open_memory == nil ||
	   library.api.close_conn == nil ||
	   library.api.conn_db == nil ||
	   library.api.transact_edn == nil ||
	   library.api.query_value_with_inputs == nil ||
	   library.api.connect == nil ||
	   library.api.connection_ok == nil ||
	   library.api.connection_error == nil ||
	   library.api.connection_close == nil ||
	   library.api.connection_db == nil ||
	   library.api.connection_transact_edn_report == nil ||
	   library.api.connection_query_value_with_inputs == nil ||
	   library.api.db_release == nil ||
	   library.api.db_basis_t == nil ||
	   library.api.db_next_t == nil ||
	   library.api.db_has_as_of_t == nil ||
	   library.api.db_as_of_t == nil ||
	   library.api.db_has_since_t == nil ||
	   library.api.db_since_t == nil ||
	   library.api.db_is_history == nil ||
	   library.api.db_as_of == nil ||
	   library.api.db_as_of_instant_millis == nil ||
	   library.api.db_since == nil ||
	   library.api.db_since_instant_millis == nil ||
	   library.api.db_history == nil ||
	   library.api.db_tx_range_value == nil ||
	   library.api.db_query_value_with_inputs == nil ||
	   library.api.tx_report_edn == nil ||
	   library.api.tx_report_free == nil ||
	   library.api.value_handle_free == nil ||
	   library.api.value_handle_value == nil ||
	   library.api.value_handle_edn == nil ||
	   library.api.value_kind == nil ||
	   library.api.value_entity == nil ||
	   library.api.value_int == nil ||
	   library.api.value_float == nil ||
	   library.api.value_bool == nil ||
	   library.api.value_text == nil ||
	   library.api.value_edn == nil ||
	   library.api.value_item_count == nil ||
	   library.api.value_item == nil ||
	   library.api.value_map_count == nil ||
	   library.api.value_map_key == nil ||
	   library.api.value_map_value == nil ||
	   library.api.value_map_get == nil ||
	   library.api.string_free == nil ||
	   library.api.abi_version() != ABI_VERSION {
		dynlib.unload_library(library.api.__handle)
		return {}, false
	}

	return library, true
}

load_bundled :: proc(package_root: string) -> (library: Library, ok: bool) {
	path, path_error := os.join_path(
		{package_root, "lib", library_filename()},
		context.temp_allocator,
	)
	if path_error != nil {
		return {}, false
	}
	return load(path)
}

unload :: proc(library: ^Library) {
	if library == nil || library.api.__handle == nil {
		return
	}
	dynlib.unload_library(library.api.__handle)
	library^ = {}
}

open_memory :: proc(library: ^Library) -> (connection: Connection, ok: bool) {
	if library == nil || library.api.open_memory == nil {
		return {}, false
	}
	handle := library.api.open_memory()
	if handle == nil {
		return {}, false
	}
	return Connection{library = library, handle = handle}, true
}

close_memory :: proc(connection: ^Connection) {
	if connection == nil || connection.handle == nil {
		return
	}
	connection.library.api.close_conn(connection.handle)
	connection^ = {}
}

connect :: proc(library: ^Library, uri: string) -> (connection: Durable_Connection, ok: bool) {
	if library == nil || library.api.connect == nil {
		return {}, false
	}
	uri_text := strings.clone_to_cstring(uri, context.temp_allocator)
	handle := library.api.connect(uri_text)
	if handle == nil || !library.api.connection_ok(handle) {
		return Durable_Connection{library = library, handle = handle}, false
	}
	return Durable_Connection{library = library, handle = handle}, true
}

connection_error :: proc(
	connection: ^Durable_Connection,
	allocator := context.allocator,
) -> string {
	if connection == nil || connection.handle == nil {
		return strings.clone("invalid durable connection", allocator)
	}
	native_error := connection.library.api.connection_error(connection.handle)
	if native_error == nil {
		return strings.clone("", allocator)
	}
	defer connection.library.api.string_free(native_error)
	return strings.clone(string(native_error), allocator)
}

close_durable :: proc(connection: ^Durable_Connection) {
	if connection == nil || connection.handle == nil {
		return
	}
	connection.library.api.connection_close(connection.handle)
	connection^ = {}
}

db_memory :: proc(connection: ^Connection) -> (database: DB, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	handle := connection.library.api.conn_db(connection.handle)
	if handle == nil {
		return {}, false
	}
	return DB{library = connection.library, handle = handle}, true
}

db_durable :: proc(connection: ^Durable_Connection) -> (database: DB, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	handle := connection.library.api.connection_db(connection.handle)
	if handle == nil {
		return {}, false
	}
	return DB{library = connection.library, handle = handle}, true
}

close_db :: proc(database: ^DB) {
	if database == nil || database.handle == nil {
		return
	}
	database.library.api.db_release(database.handle)
	database^ = {}
}

basis_t :: proc(database: ^DB) -> (t: u64, ok: bool) {
	if database == nil || database.handle == nil {
		return 0, false
	}
	return database.library.api.db_basis_t(database.handle), true
}

next_t :: proc(database: ^DB) -> (t: u64, ok: bool) {
	if database == nil || database.handle == nil {
		return 0, false
	}
	return database.library.api.db_next_t(database.handle), true
}

as_of_t :: proc(database: ^DB) -> (t: u64, present: bool) {
	if database == nil || database.handle == nil ||
	   !database.library.api.db_has_as_of_t(database.handle) {
		return 0, false
	}
	return database.library.api.db_as_of_t(database.handle), true
}

since_t :: proc(database: ^DB) -> (t: u64, present: bool) {
	if database == nil || database.handle == nil ||
	   !database.library.api.db_has_since_t(database.handle) {
		return 0, false
	}
	return database.library.api.db_since_t(database.handle), true
}

is_history :: proc(database: ^DB) -> bool {
	return database != nil &&
	       database.handle != nil &&
	       database.library.api.db_is_history(database.handle)
}

as_of_coordinate :: proc(database: ^DB, tx: u64) -> (filtered: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	handle := database.library.api.db_as_of(database.handle, tx)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

as_of_time :: proc(database: ^DB, time_point: time.Time) -> (filtered: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	unix_millis := time.to_unix_nanoseconds(time_point) / 1_000_000
	handle := database.library.api.db_as_of_instant_millis(database.handle, unix_millis)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

since_coordinate :: proc(database: ^DB, tx: u64) -> (filtered: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	handle := database.library.api.db_since(database.handle, tx)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

since_time :: proc(database: ^DB, time_point: time.Time) -> (filtered: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	unix_millis := time.to_unix_nanoseconds(time_point) / 1_000_000
	handle := database.library.api.db_since_instant_millis(database.handle, unix_millis)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

history :: proc(database: ^DB) -> (filtered: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	handle := database.library.api.db_history(database.handle)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

log_memory :: proc(connection: ^Connection) -> (log_value: Log, ok: bool) {
	database, retained := db_memory(connection)
	if !retained {
		return {}, false
	}
	return Log{database = database}, true
}

log_durable :: proc(connection: ^Durable_Connection) -> (log_value: Log, ok: bool) {
	database, retained := db_durable(connection)
	if !retained {
		return {}, false
	}
	return Log{database = database}, true
}

close_log :: proc(log_value: ^Log) {
	if log_value == nil {
		return
	}
	close_db(&log_value.database)
	log_value^ = {}
}

Time_Point :: union {
	u64,
	time.Time,
}

tx_range_bound :: proc(point: Maybe(Time_Point)) -> (kind: int, value: i64, ok: bool) {
	switch item in point {
	case nil:
		return 0, 0, true
	case Time_Point:
		switch time_point in item {
		case u64:
			if time_point > u64(max(i64)) {
				return 0, 0, false
			}
			return 1, i64(time_point), true
		case time.Time:
			return 2, time.to_unix_nanoseconds(time_point) / 1_000_000, true
		}
	}
	return 0, 0, false
}

tx_range :: proc(
	log_value: ^Log,
	start: Maybe(Time_Point) = nil,
	end: Maybe(Time_Point) = nil,
) -> (transactions: Data, ok: bool) {
	if log_value == nil || log_value.database.handle == nil {
		return {}, false
	}
	start_kind, start_value, start_ok := tx_range_bound(start)
	end_kind, end_value, end_ok := tx_range_bound(end)
	if !start_ok || !end_ok {
		return {}, false
	}
	handle := log_value.database.library.api.db_tx_range_value(
		log_value.database.handle,
		start_kind,
		start_value,
		end_kind,
		end_value,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = log_value.database.library, handle = handle}, true
}

transact_memory :: proc(
	connection: ^Connection,
	tx: string,
	allocator := context.allocator,
) -> (result: string, ok: bool) {
	if connection == nil || connection.handle == nil {
		return "", false
	}

	tx_text := strings.clone_to_cstring(tx, context.temp_allocator)
	native_result := connection.library.api.transact_edn(connection.handle, tx_text)
	if native_result == nil {
		return "", false
	}
	defer connection.library.api.string_free(native_result)

	result = strings.clone(string(native_result), allocator)
	return result, true
}

transact_durable :: proc(
	connection: ^Durable_Connection,
	tx: string,
	allocator := context.allocator,
) -> (result: string, ok: bool) {
	if connection == nil || connection.handle == nil {
		return "", false
	}
	tx_text := strings.clone_to_cstring(tx, context.temp_allocator)
	report := connection.library.api.connection_transact_edn_report(
		connection.handle,
		tx_text,
	)
	if report == nil {
		return "", false
	}
	defer connection.library.api.tx_report_free(report)
	native_result := connection.library.api.tx_report_edn(report)
	if native_result == nil {
		return "", false
	}
	defer connection.library.api.string_free(native_result)
	result = strings.clone(string(native_result), allocator)
	return result, strings.contains(result, ":ok true")
}

query_memory :: proc(
	connection: ^Connection,
	query_text: string,
	inputs := "[]",
) -> (result: Data, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	inputs_cstring := strings.clone_to_cstring(inputs, context.temp_allocator)
	handle := connection.library.api.query_value_with_inputs(
		connection.handle,
		query_cstring,
		inputs_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = connection.library, handle = handle}, true
}

query_durable :: proc(
	connection: ^Durable_Connection,
	query_text: string,
	inputs := "[]",
) -> (result: Data, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	inputs_cstring := strings.clone_to_cstring(inputs, context.temp_allocator)
	handle := connection.library.api.connection_query_value_with_inputs(
		connection.handle,
		query_cstring,
		inputs_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = connection.library, handle = handle}, true
}

query_db :: proc(
	database: ^DB,
	query_text: string,
	inputs := "[]",
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	inputs_cstring := strings.clone_to_cstring(inputs, context.temp_allocator)
	handle := database.library.api.db_query_value_with_inputs(
		database.handle,
		query_cstring,
		inputs_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

close_data :: proc(data: ^Data) {
	if data == nil || data.handle == nil {
		return
	}
	data.library.api.value_handle_free(data.handle)
	data^ = {}
}

value :: proc(data: ^Data) -> (result: Value, ok: bool) {
	if data == nil || data.handle == nil {
		return {}, false
	}
	handle := data.library.api.value_handle_value(data.handle)
	if handle == nil {
		return {}, false
	}
	return Value{library = data.library, handle = handle}, true
}

kind :: proc(value: Value) -> Kind {
	if value.handle == nil {
		return .Nil
	}
	return Kind(value.library.api.value_kind(value.handle))
}

edn_data :: proc(data: ^Data, allocator := context.allocator) -> (result: string, ok: bool) {
	if data == nil || data.handle == nil {
		return "", false
	}
	native_result := data.library.api.value_handle_edn(data.handle)
	if native_result == nil {
		return "", false
	}
	defer data.library.api.string_free(native_result)
	return strings.clone(string(native_result), allocator), true
}

edn_value :: proc(value: Value, allocator := context.allocator) -> (result: string, ok: bool) {
	if value.handle == nil {
		return "", false
	}
	native_result := value.library.api.value_edn(value.handle)
	if native_result == nil {
		return "", false
	}
	defer value.library.api.string_free(native_result)
	return strings.clone(string(native_result), allocator), true
}

item_count :: proc(value: Value) -> int {
	if value.handle == nil {
		return 0
	}
	return value.library.api.value_item_count(value.handle)
}

item :: proc(value: Value, index: int) -> (result: Value, ok: bool) {
	if value.handle == nil || index < 0 || index >= item_count(value) {
		return {}, false
	}
	handle := value.library.api.value_item(value.handle, index)
	if handle == nil {
		return {}, false
	}
	return Value{library = value.library, handle = handle}, true
}

map_count :: proc(value: Value) -> int {
	if value.handle == nil {
		return 0
	}
	return value.library.api.value_map_count(value.handle)
}

map_key :: proc(value: Value, index: int) -> (result: Value, ok: bool) {
	if value.handle == nil || index < 0 || index >= map_count(value) {
		return {}, false
	}
	handle := value.library.api.value_map_key(value.handle, index)
	if handle == nil {
		return {}, false
	}
	return Value{library = value.library, handle = handle}, true
}

map_value :: proc(value: Value, index: int) -> (result: Value, ok: bool) {
	if value.handle == nil || index < 0 || index >= map_count(value) {
		return {}, false
	}
	handle := value.library.api.value_map_value(value.handle, index)
	if handle == nil {
		return {}, false
	}
	return Value{library = value.library, handle = handle}, true
}

get :: proc(value: Value, key: string) -> (result: Value, ok: bool) {
	if value.handle == nil || kind(value) != .Map {
		return {}, false
	}
	key_cstring := strings.clone_to_cstring(key, context.temp_allocator)
	handle := value.library.api.value_map_get(value.handle, key_cstring)
	if handle == nil {
		return {}, false
	}
	return Value{library = value.library, handle = handle}, true
}

as_entity :: proc(value: Value) -> (result: u64, ok: bool) {
	if kind(value) != .Entity {
		return 0, false
	}
	return value.library.api.value_entity(value.handle), true
}

as_int :: proc(value: Value) -> (result: i64, ok: bool) {
	if kind(value) != .Int {
		return 0, false
	}
	return value.library.api.value_int(value.handle), true
}

as_instant :: proc(value: Value) -> (unix_millis: i64, ok: bool) {
	if kind(value) != .Instant {
		return 0, false
	}
	return value.library.api.value_int(value.handle), true
}

as_float :: proc(value: Value) -> (result: f64, ok: bool) {
	if kind(value) != .Float {
		return 0, false
	}
	return value.library.api.value_float(value.handle), true
}

as_bool :: proc(value: Value) -> (result: bool, ok: bool) {
	if kind(value) != .Bool {
		return false, false
	}
	return value.library.api.value_bool(value.handle), true
}

as_string :: proc(
	value: Value,
	allocator := context.allocator,
) -> (result: string, ok: bool) {
	value_kind := kind(value)
	if value_kind != .String &&
	   value_kind != .Keyword &&
	   value_kind != .Symbol &&
	   value_kind != .UUID {
		return "", false
	}
	native_result := value.library.api.value_text(value.handle)
	if native_result == nil {
		return "", false
	}
	defer value.library.api.string_free(native_result)
	return strings.clone(string(native_result), allocator), true
}

db :: proc{db_memory, db_durable}
log :: proc{log_memory, log_durable}
as_of :: proc{as_of_coordinate, as_of_time}
since :: proc{since_coordinate, since_time}
close :: proc{close_memory, close_durable, close_db, close_log, close_data}
transact :: proc{transact_memory, transact_durable}
query :: proc{query_memory, query_durable, query_db}
edn :: proc{edn_data, edn_value}
