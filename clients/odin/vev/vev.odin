// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import "core:dynlib"
import "core:os"
import "core:strings"
import "core:time"

ABI_VERSION :: 1
TX_PARTITION_BASE :: u64(4_611_686_018_427_387_904)

@(private)
API :: struct {
	abi_version: proc "c" () -> u32 `dynlib:"vev_abi_version"`,
	squuid: proc "c" () -> cstring `dynlib:"vev_squuid"`,
	squuid_time_millis: proc "c" (uuid_text: cstring) -> i64 `dynlib:"vev_squuid_time_millis"`,
	open_memory: proc "c" () -> rawptr `dynlib:"vev_conn_open_memory"`,
	close_conn: proc "c" (conn: rawptr) `dynlib:"vev_conn_close"`,
	conn_db: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_conn_db"`,
	transact_edn: proc "c" (conn: rawptr, tx_text: cstring) -> cstring `dynlib:"vev_transact_edn"`,
	query_value_with_inputs: proc "c" (conn: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_query_value_with_inputs"`,
	connect: proc "c" (uri: cstring) -> rawptr `dynlib:"vev_connect"`,
	connection_ok: proc "c" (conn: rawptr) -> bool `dynlib:"vev_connection_ok"`,
	connection_error: proc "c" (conn: rawptr) -> cstring `dynlib:"vev_connection_error"`,
	connection_basis_t: proc "c" (conn: rawptr) -> u64 `dynlib:"vev_connection_basis_t"`,
	connection_tx_count: proc "c" (conn: rawptr) -> u64 `dynlib:"vev_connection_tx_count"`,
	connection_tx_ids: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_connection_tx_ids"`,
	connection_close: proc "c" (conn: rawptr) `dynlib:"vev_connection_close"`,
	connection_db: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_connection_db"`,
	connection_transact_edn_report: proc "c" (conn: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_connection_transact_edn_report"`,
	connection_query_value_with_inputs: proc "c" (conn: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_connection_query_value_with_inputs"`,
	connection_compact_indexes: proc "c" (conn: rawptr) -> bool `dynlib:"vev_connection_compact_indexes"`,
	connection_maintain_indexes: proc "c" (conn: rawptr, max_steps: int) -> bool `dynlib:"vev_connection_maintain_indexes"`,
	connection_latest_index_merge_run_count: proc "c" (conn: rawptr, index_name: cstring) -> int `dynlib:"vev_connection_latest_index_merge_run_count"`,
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
	db_stats_value: proc "c" (db: rawptr) -> rawptr `dynlib:"vev_db_stats_value"`,
	with_edn_report: proc "c" (db: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_with_edn_report"`,
	db_with_edn: proc "c" (db: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_db_with_edn"`,
	db_query_value_with_inputs: proc "c" (db: rawptr, query_text, inputs_text: cstring) -> rawptr `dynlib:"vev_db_query_value_with_inputs"`,
	db_entity: proc "c" (db: rawptr, entity: u64) -> rawptr `dynlib:"vev_db_entity"`,
	db_entity_lookup_ref_string: proc "c" (db: rawptr, attr, value: cstring) -> rawptr `dynlib:"vev_db_entity_lookup_ref_string"`,
	db_entity_lookup_ref_edn: proc "c" (db: rawptr, attr, value_edn: cstring) -> rawptr `dynlib:"vev_db_entity_lookup_ref_edn"`,
	db_entity_ident: proc "c" (db: rawptr, ident: cstring) -> rawptr `dynlib:"vev_db_entity_ident"`,
	db_attribute_value: proc "c" (db: rawptr, attr: cstring) -> rawptr `dynlib:"vev_db_attribute_value"`,
	db_datoms_value: proc "c" (db: rawptr, mode: int, index, components_edn: cstring) -> rawptr `dynlib:"vev_db_datoms_value"`,
	db_index_pull_value: proc "c" (db: rawptr, index, selector_edn, start_edn: cstring, reverse: bool, offset, limit: i64) -> rawptr `dynlib:"vev_db_index_pull_value"`,
	db_index_range_value: proc "c" (db: rawptr, attr, start_edn, end_edn: cstring) -> rawptr `dynlib:"vev_db_index_range_value"`,
	entity_free: proc "c" (entity: rawptr) `dynlib:"vev_entity_free"`,
	entity_found: proc "c" (entity: rawptr) -> bool `dynlib:"vev_entity_found"`,
	entity_id: proc "c" (entity: rawptr) -> u64 `dynlib:"vev_entity_id"`,
	entity_contains: proc "c" (entity: rawptr, attr: cstring) -> bool `dynlib:"vev_entity_contains"`,
	entity_get: proc "c" (entity: rawptr, attr: cstring) -> rawptr `dynlib:"vev_entity_get"`,
	entity_values: proc "c" (entity: rawptr, attr: cstring) -> rawptr `dynlib:"vev_entity_values"`,
	entity_touch: proc "c" (entity: rawptr) -> rawptr `dynlib:"vev_entity_touch"`,
	pull_edn: proc "c" (db: rawptr, pattern_edn: cstring, entity: u64) -> rawptr `dynlib:"vev_pull_edn"`,
	pull_many_edn: proc "c" (db: rawptr, pattern_edn: cstring, entities: rawptr, entity_count: int) -> rawptr `dynlib:"vev_pull_many_edn"`,
	prepare_query_edn: proc "c" (query_text: cstring) -> rawptr `dynlib:"vev_prepare_query_edn"`,
	prepared_query_ok: proc "c" (query: rawptr) -> bool `dynlib:"vev_prepared_query_ok"`,
	prepared_query_free: proc "c" (query: rawptr) `dynlib:"vev_prepared_query_free"`,
	db_query_prepared_value_with_inputs: proc "c" (db, query: rawptr, inputs_text: cstring) -> rawptr `dynlib:"vev_db_query_prepared_value_with_inputs"`,
	tx_report_edn: proc "c" (report: rawptr) -> cstring `dynlib:"vev_tx_report_edn"`,
	tx_report_value: proc "c" (report: rawptr) -> rawptr `dynlib:"vev_tx_report_value"`,
	tx_report_resolve_tempid_edn: proc "c" (report: rawptr, tempid_edn: cstring) -> u64 `dynlib:"vev_tx_report_resolve_tempid_edn"`,
	tx_report_db_before: proc "c" (report: rawptr) -> rawptr `dynlib:"vev_tx_report_db_before"`,
	tx_report_db_after: proc "c" (report: rawptr) -> rawptr `dynlib:"vev_tx_report_db_after"`,
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
	u64_array_free: proc "c" (array: rawptr) `dynlib:"vev_u64_array_free"`,
	u64_array_count: proc "c" (array: rawptr) -> int `dynlib:"vev_u64_array_count"`,
	u64_array_value: proc "c" (array: rawptr, index: int) -> u64 `dynlib:"vev_u64_array_value"`,
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

Entity :: struct {
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

Native_Tx_Report :: struct {
	library: ^Library,
	handle: rawptr,
}

Prepared_Query :: struct {
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
	   library.api.squuid == nil ||
	   library.api.squuid_time_millis == nil ||
	   library.api.open_memory == nil ||
	   library.api.close_conn == nil ||
	   library.api.conn_db == nil ||
	   library.api.transact_edn == nil ||
	   library.api.query_value_with_inputs == nil ||
	   library.api.connect == nil ||
	   library.api.connection_ok == nil ||
	   library.api.connection_error == nil ||
	   library.api.connection_basis_t == nil ||
	   library.api.connection_tx_count == nil ||
	   library.api.connection_tx_ids == nil ||
	   library.api.connection_close == nil ||
	   library.api.connection_db == nil ||
	   library.api.connection_transact_edn_report == nil ||
	   library.api.connection_query_value_with_inputs == nil ||
	   library.api.connection_compact_indexes == nil ||
	   library.api.connection_maintain_indexes == nil ||
	   library.api.connection_latest_index_merge_run_count == nil ||
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
	   library.api.db_stats_value == nil ||
	   library.api.with_edn_report == nil ||
	   library.api.db_with_edn == nil ||
	   library.api.db_query_value_with_inputs == nil ||
	   library.api.db_entity == nil ||
	   library.api.db_entity_lookup_ref_string == nil ||
	   library.api.db_entity_lookup_ref_edn == nil ||
	   library.api.db_entity_ident == nil ||
	   library.api.db_attribute_value == nil ||
	   library.api.db_datoms_value == nil ||
	   library.api.db_index_pull_value == nil ||
	   library.api.db_index_range_value == nil ||
	   library.api.entity_free == nil ||
	   library.api.entity_found == nil ||
	   library.api.entity_id == nil ||
	   library.api.entity_contains == nil ||
	   library.api.entity_get == nil ||
	   library.api.entity_values == nil ||
	   library.api.entity_touch == nil ||
	   library.api.pull_edn == nil ||
	   library.api.pull_many_edn == nil ||
	   library.api.prepare_query_edn == nil ||
	   library.api.prepared_query_ok == nil ||
	   library.api.prepared_query_free == nil ||
	   library.api.db_query_prepared_value_with_inputs == nil ||
	   library.api.tx_report_edn == nil ||
	   library.api.tx_report_value == nil ||
	   library.api.tx_report_resolve_tempid_edn == nil ||
	   library.api.tx_report_db_before == nil ||
	   library.api.tx_report_db_after == nil ||
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
	   library.api.u64_array_free == nil ||
	   library.api.u64_array_count == nil ||
	   library.api.u64_array_value == nil ||
	   library.api.string_free == nil ||
	   library.api.abi_version() != ABI_VERSION {
		dynlib.unload_library(library.api.__handle)
		return {}, false
	}

	return library, true
}

squuid :: proc(library: ^Library, allocator := context.allocator) -> (value: string, ok: bool) {
	if library == nil || library.api.squuid == nil {
		return "", false
	}
	native_value := library.api.squuid()
	if native_value == nil {
		return "", false
	}
	defer library.api.string_free(native_value)
	return strings.clone(string(native_value), allocator), true
}

squuid_time_millis :: proc(library: ^Library, value: string) -> (unix_millis: i64, ok: bool) {
	if library == nil || library.api.squuid_time_millis == nil {
		return 0, false
	}
	value_cstring := strings.clone_to_cstring(value, context.temp_allocator)
	unix_millis = library.api.squuid_time_millis(value_cstring)
	return unix_millis, unix_millis >= 0
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

load_default :: proc() -> (library: Library, ok: bool) {
	if explicit := os.get_env("VEV_LIB", context.temp_allocator); len(explicit) > 0 {
		return load(explicit)
	}

	executable_dir, executable_error := os.get_executable_directory(context.temp_allocator)
	if executable_error == nil {
		candidates := [5]string{}
		candidates[0], _ = os.join_path(
			{executable_dir, "..", "Frameworks", library_filename()},
			context.temp_allocator,
		)
		candidates[1], _ = os.join_path(
			{executable_dir, "lib", library_filename()},
			context.temp_allocator,
		)
		candidates[2], _ = os.join_path(
			{executable_dir, library_filename()},
			context.temp_allocator,
		)
		candidates[3], _ = os.join_path(
			{executable_dir, "..", "lib", library_filename()},
			context.temp_allocator,
		)
		candidates[4], _ = os.join_path(
			{executable_dir, "deps", "vev", "lib", library_filename()},
			context.temp_allocator,
		)
		for candidate in candidates {
			if len(candidate) == 0 {
				continue
			}
			if loaded, loaded_ok := load(candidate); loaded_ok {
				return loaded, true
			}
		}
	}

	return {}, false
}

unload :: proc(library: ^Library) {
	if library == nil || library.api.__handle == nil {
		return
	}
	dynlib.unload_library(library.api.__handle)
	library^ = {}
}

create_conn :: proc(library: ^Library) -> (connection: Connection, ok: bool) {
	if library == nil || library.api.open_memory == nil {
		return {}, false
	}
	handle := library.api.open_memory()
	if handle == nil {
		return {}, false
	}
	return Connection{library = library, handle = handle}, true
}

// Compatibility alias for create_conn.
open_memory :: create_conn

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

connection_basis_t :: proc(connection: ^Durable_Connection) -> (t: u64, ok: bool) {
	if connection == nil || connection.handle == nil {
		return 0, false
	}
	return connection.library.api.connection_basis_t(connection.handle), true
}

connection_tx_count :: proc(connection: ^Durable_Connection) -> (count: u64, ok: bool) {
	if connection == nil || connection.handle == nil {
		return 0, false
	}
	return connection.library.api.connection_tx_count(connection.handle), true
}

connection_tx_ids :: proc(
	connection: ^Durable_Connection,
	allocator := context.allocator,
) -> (values: [dynamic]u64, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	handle := connection.library.api.connection_tx_ids(connection.handle)
	if handle == nil {
		return {}, false
	}
	defer connection.library.api.u64_array_free(handle)
	count := connection.library.api.u64_array_count(handle)
	if count < 0 {
		return {}, false
	}
	values = make([dynamic]u64, 0, count, allocator)
	for index in 0 ..< count {
		append(&values, connection.library.api.u64_array_value(handle, index))
	}
	return values, true
}

compact_indexes :: proc(connection: ^Durable_Connection) -> bool {
	if connection == nil || connection.handle == nil {
		return false
	}
	return connection.library.api.connection_compact_indexes(connection.handle)
}

maintain_indexes :: proc(connection: ^Durable_Connection, max_steps: int) -> bool {
	if connection == nil || connection.handle == nil || max_steps < 0 {
		return false
	}
	return connection.library.api.connection_maintain_indexes(
		connection.handle,
		max_steps,
	)
}

latest_index_merge_run_count :: proc(
	connection: ^Durable_Connection,
	index_name: string,
) -> (count: int, ok: bool) {
	if connection == nil || connection.handle == nil {
		return 0, false
	}
	index_name_cstring := strings.clone_to_cstring(
		index_name,
		context.temp_allocator,
	)
	count = connection.library.api.connection_latest_index_merge_run_count(
		connection.handle,
		index_name_cstring,
	)
	return count, count >= 0
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

t_to_tx :: proc(t: u64) -> u64 {
	if t == 0 {
		return 0
	}
	return TX_PARTITION_BASE + t - 1
}

tx_to_t :: proc(tx: u64) -> u64 {
	if tx >= TX_PARTITION_BASE {
		return tx - TX_PARTITION_BASE + 1
	}
	return tx
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

lookup_ref_string_exists :: proc(database: ^DB, attr, value: string) -> bool {
	if database == nil || database.handle == nil {
		return false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	value_cstring := strings.clone_to_cstring(value, context.temp_allocator)
	entity := database.library.api.db_entity_lookup_ref_string(
		database.handle,
		attr_cstring,
		value_cstring,
	)
	if entity == nil {
		return false
	}
	defer database.library.api.entity_free(entity)
	return database.library.api.entity_found(entity)
}

entity :: proc(database: ^DB, entity_id: u64) -> (result: Entity, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	handle := database.library.api.db_entity(database.handle, entity_id)
	if handle == nil || !database.library.api.entity_found(handle) {
		if handle != nil {
			database.library.api.entity_free(handle)
		}
		return {}, false
	}
	return Entity{library = database.library, handle = handle}, true
}

entity_lookup_ref :: proc(
	database: ^DB,
	attr, value_edn: string,
) -> (result: Entity, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	value_cstring := strings.clone_to_cstring(value_edn, context.temp_allocator)
	handle := database.library.api.db_entity_lookup_ref_edn(
		database.handle,
		attr_cstring,
		value_cstring,
	)
	if handle == nil || !database.library.api.entity_found(handle) {
		if handle != nil {
			database.library.api.entity_free(handle)
		}
		return {}, false
	}
	return Entity{library = database.library, handle = handle}, true
}

entity_ident :: proc(database: ^DB, ident: string) -> (result: Entity, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	ident_cstring := strings.clone_to_cstring(ident, context.temp_allocator)
	handle := database.library.api.db_entity_ident(database.handle, ident_cstring)
	if handle == nil || !database.library.api.entity_found(handle) {
		if handle != nil {
			database.library.api.entity_free(handle)
		}
		return {}, false
	}
	return Entity{library = database.library, handle = handle}, true
}

entity_id :: proc(entity_value: ^Entity) -> (id: u64, ok: bool) {
	if entity_value == nil || entity_value.handle == nil {
		return 0, false
	}
	id = entity_value.library.api.entity_id(entity_value.handle)
	return id, id != 0
}

entity_contains :: proc(entity_value: ^Entity, attr: string) -> bool {
	if entity_value == nil || entity_value.handle == nil {
		return false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	return entity_value.library.api.entity_contains(entity_value.handle, attr_cstring)
}

entity_get :: proc(entity_value: ^Entity, attr: string) -> (result: Data, ok: bool) {
	if entity_value == nil || entity_value.handle == nil {
		return {}, false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	handle := entity_value.library.api.entity_get(entity_value.handle, attr_cstring)
	if handle == nil {
		return {}, false
	}
	return Data{library = entity_value.library, handle = handle}, true
}

entity_values :: proc(entity_value: ^Entity, attr: string) -> (result: Data, ok: bool) {
	if entity_value == nil || entity_value.handle == nil {
		return {}, false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	handle := entity_value.library.api.entity_values(entity_value.handle, attr_cstring)
	if handle == nil {
		return {}, false
	}
	return Data{library = entity_value.library, handle = handle}, true
}

entity_touch :: proc(entity_value: ^Entity) -> (result: Data, ok: bool) {
	if entity_value == nil || entity_value.handle == nil {
		return {}, false
	}
	handle := entity_value.library.api.entity_touch(entity_value.handle)
	if handle == nil {
		return {}, false
	}
	return Data{library = entity_value.library, handle = handle}, true
}

close_entity :: proc(entity_value: ^Entity) {
	if entity_value == nil || entity_value.handle == nil {
		return
	}
	entity_value.library.api.entity_free(entity_value.handle)
	entity_value^ = {}
}

attribute :: proc(database: ^DB, attr: string) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	handle := database.library.api.db_attribute_value(
		database.handle,
		attr_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

datoms :: proc(
	database: ^DB,
	mode: int,
	index, components_edn: string,
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	index_cstring := strings.clone_to_cstring(index, context.temp_allocator)
	components_cstring := strings.clone_to_cstring(
		components_edn,
		context.temp_allocator,
	)
	handle := database.library.api.db_datoms_value(
		database.handle,
		mode,
		index_cstring,
		components_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

index_pull :: proc(
	database: ^DB,
	index, selector_edn, start_edn: string,
	reverse := false,
	offset: i64 = 0,
	limit: i64 = -1,
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	index_cstring := strings.clone_to_cstring(index, context.temp_allocator)
	selector_cstring := strings.clone_to_cstring(selector_edn, context.temp_allocator)
	start_cstring := strings.clone_to_cstring(start_edn, context.temp_allocator)
	handle := database.library.api.db_index_pull_value(
		database.handle,
		index_cstring,
		selector_cstring,
		start_cstring,
		reverse,
		offset,
		limit,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

index_range :: proc(
	database: ^DB,
	attr, start_edn, end_edn: string,
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	attr_cstring := strings.clone_to_cstring(attr, context.temp_allocator)
	start_cstring := strings.clone_to_cstring(start_edn, context.temp_allocator)
	end_cstring := strings.clone_to_cstring(end_edn, context.temp_allocator)
	handle := database.library.api.db_index_range_value(
		database.handle,
		attr_cstring,
		start_cstring,
		end_cstring,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

pull :: proc(
	database: ^DB,
	pattern_edn: string,
	entity_id: u64,
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	pattern_cstring := strings.clone_to_cstring(
		pattern_edn,
		context.temp_allocator,
	)
	handle := database.library.api.pull_edn(
		database.handle,
		pattern_cstring,
		entity_id,
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
}

pull_many :: proc(
	database: ^DB,
	pattern_edn: string,
	entities: []u64,
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	pattern_cstring := strings.clone_to_cstring(
		pattern_edn,
		context.temp_allocator,
	)
	entity_data: rawptr = nil
	if len(entities) > 0 {
		entity_data = rawptr(&entities[0])
	}
	handle := database.library.api.pull_many_edn(
		database.handle,
		pattern_cstring,
		entity_data,
		len(entities),
	)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
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

tx_range_all :: proc(log_value: ^Log) -> (transactions: Data, ok: bool) {
	return tx_range(log_value, nil, nil)
}

tx_range_coordinates :: proc(
	log_value: ^Log,
	start, end: u64,
) -> (transactions: Data, ok: bool) {
	return tx_range(
		log_value,
		Time_Point(start),
		Time_Point(end),
	)
}

db_stats :: proc(database: ^DB) -> (stats: Data, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	handle := database.library.api.db_stats_value(database.handle)
	if handle == nil {
		return {}, false
	}
	return Data{library = database.library, handle = handle}, true
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

transact_report_durable :: proc(
	connection: ^Durable_Connection,
	tx: string,
) -> (report: Native_Tx_Report, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	tx_text := strings.clone_to_cstring(tx, context.temp_allocator)
	handle := connection.library.api.connection_transact_edn_report(
		connection.handle,
		tx_text,
	)
	if handle == nil {
		return {}, false
	}
	return Native_Tx_Report{library = connection.library, handle = handle}, true
}

with_report :: proc(
	database: ^DB,
	tx: string,
) -> (report: Native_Tx_Report, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	tx_text := strings.clone_to_cstring(tx, context.temp_allocator)
	handle := database.library.api.with_edn_report(database.handle, tx_text)
	if handle == nil {
		return {}, false
	}
	return Native_Tx_Report{library = database.library, handle = handle}, true
}

db_with :: proc(database: ^DB, tx: string) -> (result: DB, ok: bool) {
	if database == nil || database.handle == nil {
		return {}, false
	}
	tx_text := strings.clone_to_cstring(tx, context.temp_allocator)
	handle := database.library.api.db_with_edn(database.handle, tx_text)
	if handle == nil {
		return {}, false
	}
	return DB{library = database.library, handle = handle}, true
}

tx_report_edn :: proc(
	report: ^Native_Tx_Report,
	allocator := context.allocator,
) -> (result: string, ok: bool) {
	if report == nil || report.handle == nil {
		return "", false
	}
	native_result := report.library.api.tx_report_edn(report.handle)
	if native_result == nil {
		return "", false
	}
	defer report.library.api.string_free(native_result)
	return strings.clone(string(native_result), allocator), true
}

tx_report_value :: proc(report: ^Native_Tx_Report) -> (result: Value, ok: bool) {
	if report == nil || report.handle == nil {
		return {}, false
	}
	handle := report.library.api.tx_report_value(report.handle)
	if handle == nil {
		return {}, false
	}
	return Value{library = report.library, handle = handle}, true
}

tx_report_resolve_tempid :: proc(
	report: ^Native_Tx_Report,
	tempid_edn: string,
) -> (entity: u64, ok: bool) {
	if report == nil || report.handle == nil {
		return 0, false
	}
	tempid_cstring := strings.clone_to_cstring(tempid_edn, context.temp_allocator)
	entity = report.library.api.tx_report_resolve_tempid_edn(
		report.handle,
		tempid_cstring,
	)
	return entity, entity != 0
}

tx_report_db_before :: proc(report: ^Native_Tx_Report) -> (database: DB, ok: bool) {
	if report == nil || report.handle == nil {
		return {}, false
	}
	handle := report.library.api.tx_report_db_before(report.handle)
	if handle == nil {
		return {}, false
	}
	return DB{library = report.library, handle = handle}, true
}

tx_report_db_after :: proc(report: ^Native_Tx_Report) -> (database: DB, ok: bool) {
	if report == nil || report.handle == nil {
		return {}, false
	}
	handle := report.library.api.tx_report_db_after(report.handle)
	if handle == nil {
		return {}, false
	}
	return DB{library = report.library, handle = handle}, true
}

close_tx_report :: proc(report: ^Native_Tx_Report) {
	if report == nil || report.handle == nil {
		return
	}
	report.library.api.tx_report_free(report.handle)
	report^ = {}
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

prepare :: proc(library: ^Library, query_text: string) -> (query: Prepared_Query, ok: bool) {
	if library == nil || library.api.prepare_query_edn == nil {
		return {}, false
	}
	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	handle := library.api.prepare_query_edn(query_cstring)
	if handle == nil || !library.api.prepared_query_ok(handle) {
		if handle != nil {
			library.api.prepared_query_free(handle)
		}
		return {}, false
	}
	return Prepared_Query{library = library, handle = handle}, true
}

close_prepared_query :: proc(query: ^Prepared_Query) {
	if query == nil || query.handle == nil {
		return
	}
	query.library.api.prepared_query_free(query.handle)
	query^ = {}
}

query_db_prepared :: proc(
	database: ^DB,
	query: ^Prepared_Query,
	inputs := "[]",
) -> (result: Data, ok: bool) {
	if database == nil || database.handle == nil ||
	   query == nil || query.handle == nil {
		return {}, false
	}
	inputs_cstring := strings.clone_to_cstring(inputs, context.temp_allocator)
	handle := database.library.api.db_query_prepared_value_with_inputs(
		database.handle,
		query.handle,
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
close :: proc{close_memory, close_durable, close_db, close_entity, close_log, close_data, close_prepared_query, close_tx_report}
transact :: proc{transact_memory, transact_durable}
query :: proc{query_memory, query_durable, query_db}
edn :: proc{edn_data, edn_value}
