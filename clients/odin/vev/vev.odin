// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import "core:dynlib"
import "core:os"
import "core:strings"

ABI_VERSION :: 1

@(private)
API :: struct {
	abi_version:  proc "c" () -> u32 `dynlib:"vev_abi_version"`,
	open_memory:  proc "c" () -> rawptr `dynlib:"vev_conn_open_memory"`,
	close_conn:   proc "c" (conn: rawptr) `dynlib:"vev_conn_close"`,
	transact_edn: proc "c" (conn: rawptr, tx_text: cstring) -> cstring `dynlib:"vev_transact_edn"`,
	query_edn:    proc "c" (conn: rawptr, query_text: cstring) -> cstring `dynlib:"vev_query_edn"`,
	connect:      proc "c" (uri: cstring) -> rawptr `dynlib:"vev_connect"`,
	connection_ok: proc "c" (conn: rawptr) -> bool `dynlib:"vev_connection_ok"`,
	connection_error: proc "c" (conn: rawptr) -> cstring `dynlib:"vev_connection_error"`,
	connection_close: proc "c" (conn: rawptr) `dynlib:"vev_connection_close"`,
	connection_db: proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_connection_db"`,
	connection_transact_edn_report: proc "c" (conn: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_connection_transact_edn_report"`,
	tx_report_edn: proc "c" (report: rawptr) -> cstring `dynlib:"vev_tx_report_edn"`,
	tx_report_free: proc "c" (report: rawptr) `dynlib:"vev_tx_report_free"`,
	db_release: proc "c" (db: rawptr) `dynlib:"vev_db_release"`,
	prepare_query_edn: proc "c" (query_text: cstring) -> rawptr `dynlib:"vev_prepare_query_edn"`,
	prepared_query_ok: proc "c" (query: rawptr) -> bool `dynlib:"vev_prepared_query_ok"`,
	prepared_query_error: proc "c" (query: rawptr) -> cstring `dynlib:"vev_prepared_query_error"`,
	prepared_query_free: proc "c" (query: rawptr) `dynlib:"vev_prepared_query_free"`,
	query_db_prepared_result_with_inputs: proc "c" (db, query: rawptr, inputs_text: cstring) -> rawptr `dynlib:"vev_query_db_prepared_result_with_inputs"`,
	result_free: proc "c" (result: rawptr) `dynlib:"vev_result_free"`,
	result_ok: proc "c" (result: rawptr) -> bool `dynlib:"vev_result_ok"`,
	result_error: proc "c" (result: rawptr) -> cstring `dynlib:"vev_result_error"`,
	result_row_count: proc "c" (result: rawptr) -> int `dynlib:"vev_result_row_count"`,
	result_value_count: proc "c" (result: rawptr, row: int) -> int `dynlib:"vev_result_value_count"`,
	result_value_edn: proc "c" (result: rawptr, row, column: int) -> cstring `dynlib:"vev_result_value_edn"`,
	string_free:  proc "c" (text: cstring) `dynlib:"vev_string_free"`,
	__handle:     dynlib.Library,
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

Rows :: struct {
	library: ^Library,
	handle: rawptr,
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
	   library.api.transact_edn == nil ||
	   library.api.query_edn == nil ||
	   library.api.connect == nil ||
	   library.api.connection_ok == nil ||
	   library.api.connection_error == nil ||
	   library.api.connection_close == nil ||
	   library.api.connection_db == nil ||
	   library.api.connection_transact_edn_report == nil ||
	   library.api.tx_report_edn == nil ||
	   library.api.tx_report_free == nil ||
	   library.api.db_release == nil ||
	   library.api.prepare_query_edn == nil ||
	   library.api.prepared_query_ok == nil ||
	   library.api.prepared_query_error == nil ||
	   library.api.prepared_query_free == nil ||
	   library.api.query_db_prepared_result_with_inputs == nil ||
	   library.api.result_free == nil ||
	   library.api.result_ok == nil ||
	   library.api.result_error == nil ||
	   library.api.result_row_count == nil ||
	   library.api.result_value_count == nil ||
	   library.api.result_value_edn == nil ||
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

query_rows :: proc(
	connection: ^Durable_Connection,
	query_text: string,
	inputs := "[]",
) -> (rows: Rows, ok: bool) {
	if connection == nil || connection.handle == nil {
		return {}, false
	}
	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	prepared := connection.library.api.prepare_query_edn(query_cstring)
	if prepared == nil {
		return {}, false
	}
	defer connection.library.api.prepared_query_free(prepared)
	if !connection.library.api.prepared_query_ok(prepared) {
		return {}, false
	}
	db := connection.library.api.connection_db(connection.handle)
	if db == nil {
		return {}, false
	}
	defer connection.library.api.db_release(db)
	inputs_text := strings.clone_to_cstring(inputs, context.temp_allocator)
	result := connection.library.api.query_db_prepared_result_with_inputs(
		db,
		prepared,
		inputs_text,
	)
	if result == nil {
		return {}, false
	}
	rows = Rows{library = connection.library, handle = result}
	return rows, connection.library.api.result_ok(result)
}

rows_error :: proc(rows: ^Rows, allocator := context.allocator) -> string {
	if rows == nil || rows.handle == nil {
		return strings.clone("invalid query result", allocator)
	}
	native_error := rows.library.api.result_error(rows.handle)
	if native_error == nil {
		return strings.clone("", allocator)
	}
	defer rows.library.api.string_free(native_error)
	return strings.clone(string(native_error), allocator)
}

row_count :: proc(rows: ^Rows) -> int {
	if rows == nil || rows.handle == nil {
		return 0
	}
	return rows.library.api.result_row_count(rows.handle)
}

value_count :: proc(rows: ^Rows, row: int) -> int {
	if rows == nil || rows.handle == nil {
		return 0
	}
	return rows.library.api.result_value_count(rows.handle, row)
}

value_edn :: proc(
	rows: ^Rows,
	row, column: int,
	allocator := context.allocator,
) -> (value: string, ok: bool) {
	if rows == nil || rows.handle == nil {
		return "", false
	}
	native_value := rows.library.api.result_value_edn(rows.handle, row, column)
	if native_value == nil {
		return "", false
	}
	defer rows.library.api.string_free(native_value)
	return strings.clone(string(native_value), allocator), true
}

close_rows :: proc(rows: ^Rows) {
	if rows == nil || rows.handle == nil {
		return
	}
	rows.library.api.result_free(rows.handle)
	rows^ = {}
}

close :: proc{close_memory, close_durable, close_rows}
transact :: proc{transact_memory, transact_durable}

query :: proc(
	connection: ^Connection,
	query_text: string,
	allocator := context.allocator,
) -> (result: string, ok: bool) {
	if connection == nil || connection.handle == nil {
		return "", false
	}

	query_cstring := strings.clone_to_cstring(query_text, context.temp_allocator)
	native_result := connection.library.api.query_edn(connection.handle, query_cstring)
	if native_result == nil {
		return "", false
	}
	defer connection.library.api.string_free(native_result)

	result = strings.clone(string(native_result), allocator)
	return result, true
}
