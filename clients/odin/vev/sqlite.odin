// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import "core:strings"

SQLITE_OK :: 0
SQLITE_ERROR :: 1
SQLITE_BUSY :: 5
SQLITE_LOCKED :: 6
SQLITE_READONLY :: 8
SQLITE_INTERRUPT :: 9
SQLITE_CONSTRAINT :: 19
SQLITE_MISUSE :: 21
SQLITE_RANGE :: 25
SQLITE_ROW :: 100
SQLITE_DONE :: 101

SQLITE_OPEN_READONLY :: 0x00000001
SQLITE_OPEN_READWRITE :: 0x00000002
SQLITE_OPEN_CREATE :: 0x00000004
SQLITE_OPEN_URI :: 0x00000040
SQLITE_OPEN_MEMORY :: 0x00000080
SQLITE_OPEN_NOMUTEX :: 0x00008000
SQLITE_OPEN_FULLMUTEX :: 0x00010000

SQLite_Kind :: enum int {
	Integer = 1,
	Float,
	Text,
	Blob,
	Null,
}

SQLite_DB :: struct {
	library: ^Library,
	handle:  rawptr,
}

SQLite_Statement :: struct {
	library: ^Library,
	handle:  rawptr,
}

sqlite_available :: proc(library: ^Library) -> bool {
	return library != nil &&
	       library.api.sqlite_open != nil &&
	       library.api.sqlite_open_v2 != nil &&
	       library.api.sqlite_db_ok != nil &&
	       library.api.sqlite_db_error_code != nil &&
	       library.api.sqlite_db_extended_error_code != nil &&
	       library.api.sqlite_db_error != nil &&
	       library.api.sqlite_db_close != nil &&
	       library.api.sqlite_exec != nil &&
	       library.api.sqlite_prepare != nil &&
	       library.api.sqlite_stmt_finalize != nil &&
	       library.api.sqlite_stmt_reset != nil &&
	       library.api.sqlite_stmt_clear_bindings != nil &&
	       library.api.sqlite_stmt_step != nil &&
	       library.api.sqlite_stmt_readonly != nil &&
	       library.api.sqlite_bind_null != nil &&
	       library.api.sqlite_bind_int64 != nil &&
	       library.api.sqlite_bind_double != nil &&
	       library.api.sqlite_bind_text != nil &&
	       library.api.sqlite_bind_blob != nil &&
	       library.api.sqlite_bind_parameter_count != nil &&
	       library.api.sqlite_bind_parameter_index != nil &&
	       library.api.sqlite_bind_parameter_name != nil &&
	       library.api.sqlite_column_count != nil &&
	       library.api.sqlite_column_name != nil &&
	       library.api.sqlite_column_type != nil &&
	       library.api.sqlite_column_int64 != nil &&
	       library.api.sqlite_column_double != nil &&
	       library.api.sqlite_column_text != nil &&
	       library.api.sqlite_column_blob != nil &&
	       library.api.sqlite_column_bytes != nil &&
	       library.api.sqlite_changes != nil &&
	       library.api.sqlite_total_changes != nil &&
	       library.api.sqlite_last_insert_rowid != nil &&
	       library.api.sqlite_autocommit != nil &&
	       library.api.sqlite_busy_timeout != nil &&
	       library.api.sqlite_interrupt != nil &&
	       library.api.sqlite_version != nil &&
	       library.api.sqlite_source_id != nil &&
	       library.api.sqlite_compile_option_used != nil
}

sqlite_open :: proc(library: ^Library, path: string) -> (db: SQLite_DB, ok: bool) {
	if !sqlite_available(library) {
		return {}, false
	}
	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	handle := library.api.sqlite_open(path_c)
	if handle == nil {
		return {}, false
	}
	return SQLite_DB{library = library, handle = handle},
	       library.api.sqlite_db_ok(handle)
}

sqlite_open_v2 :: proc(
	library: ^Library,
	path: string,
	flags: int,
) -> (db: SQLite_DB, ok: bool) {
	if !sqlite_available(library) {
		return {}, false
	}
	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	handle := library.api.sqlite_open_v2(path_c, flags)
	if handle == nil {
		return {}, false
	}
	return SQLite_DB{library = library, handle = handle},
	       library.api.sqlite_db_ok(handle)
}

sqlite_ok :: proc(db: ^SQLite_DB) -> bool {
	return db != nil &&
	       db.handle != nil &&
	       db.library.api.sqlite_db_ok(db.handle)
}

sqlite_error_code :: proc(db: ^SQLite_DB) -> int {
	if db == nil || db.handle == nil {
		return SQLITE_MISUSE
	}
	return db.library.api.sqlite_db_error_code(db.handle)
}

sqlite_extended_error_code :: proc(db: ^SQLite_DB) -> int {
	if db == nil || db.handle == nil {
		return SQLITE_MISUSE
	}
	return db.library.api.sqlite_db_extended_error_code(db.handle)
}

sqlite_error :: proc(
	db: ^SQLite_DB,
	allocator := context.allocator,
) -> string {
	if db == nil || db.handle == nil {
		return strings.clone("invalid sqlite database handle", allocator)
	}
	native_error := db.library.api.sqlite_db_error(db.handle)
	if native_error == nil {
		return strings.clone("", allocator)
	}
	defer db.library.api.string_free(native_error)
	return strings.clone(string(native_error), allocator)
}

sqlite_close :: proc(db: ^SQLite_DB) {
	if db == nil || db.handle == nil {
		return
	}
	db.library.api.sqlite_db_close(db.handle)
	db^ = {}
}

sqlite_exec :: proc(db: ^SQLite_DB, sql: string) -> int {
	if db == nil || db.handle == nil {
		return SQLITE_MISUSE
	}
	sql_c := strings.clone_to_cstring(sql, context.temp_allocator)
	return db.library.api.sqlite_exec(db.handle, sql_c)
}

sqlite_prepare :: proc(
	db: ^SQLite_DB,
	sql: string,
) -> (statement: SQLite_Statement, ok: bool) {
	if db == nil || db.handle == nil {
		return {}, false
	}
	sql_c := strings.clone_to_cstring(sql, context.temp_allocator)
	handle := db.library.api.sqlite_prepare(db.handle, sql_c)
	if handle == nil {
		return {}, false
	}
	return SQLite_Statement{library = db.library, handle = handle}, true
}

sqlite_finalize :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_OK
	}
	code := statement.library.api.sqlite_stmt_finalize(statement.handle)
	statement^ = {}
	return code
}

sqlite_reset :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_stmt_reset(statement.handle)
}

sqlite_clear_bindings :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_stmt_clear_bindings(statement.handle)
}

sqlite_step :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_stmt_step(statement.handle)
}

sqlite_statement_readonly :: proc(statement: ^SQLite_Statement) -> bool {
	return statement != nil &&
	       statement.handle != nil &&
	       statement.library.api.sqlite_stmt_readonly(statement.handle)
}

sqlite_bind_null :: proc(statement: ^SQLite_Statement, index: int) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_bind_null(statement.handle, index)
}

sqlite_bind_int :: proc(
	statement: ^SQLite_Statement,
	index: int,
	value: i64,
) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_bind_int64(statement.handle, index, value)
}

sqlite_bind_float :: proc(
	statement: ^SQLite_Statement,
	index: int,
	value: f64,
) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	return statement.library.api.sqlite_bind_double(statement.handle, index, value)
}

sqlite_bind_text :: proc(
	statement: ^SQLite_Statement,
	index: int,
	value: string,
) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	data := rawptr(nil)
	if len(value) > 0 {
		data = raw_data(value)
	}
	return statement.library.api.sqlite_bind_text(
		statement.handle,
		index,
		data,
		u64(len(value)),
	)
}

sqlite_bind_blob :: proc(
	statement: ^SQLite_Statement,
	index: int,
	value: []u8,
) -> int {
	if statement == nil || statement.handle == nil {
		return SQLITE_MISUSE
	}
	data := rawptr(nil)
	if len(value) > 0 {
		data = raw_data(value)
	}
	return statement.library.api.sqlite_bind_blob(
		statement.handle,
		index,
		data,
		u64(len(value)),
	)
}

sqlite_bind_parameter_count :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return 0
	}
	return statement.library.api.sqlite_bind_parameter_count(statement.handle)
}

sqlite_bind_parameter_index :: proc(
	statement: ^SQLite_Statement,
	name: string,
) -> int {
	if statement == nil || statement.handle == nil {
		return 0
	}
	name_c := strings.clone_to_cstring(name, context.temp_allocator)
	return statement.library.api.sqlite_bind_parameter_index(
		statement.handle,
		name_c,
	)
}

sqlite_bind_parameter_name :: proc(
	statement: ^SQLite_Statement,
	index: int,
	allocator := context.allocator,
) -> string {
	if statement == nil || statement.handle == nil {
		return strings.clone("", allocator)
	}
	native_name := statement.library.api.sqlite_bind_parameter_name(
		statement.handle,
		index,
	)
	if native_name == nil {
		return strings.clone("", allocator)
	}
	defer statement.library.api.string_free(native_name)
	return strings.clone(string(native_name), allocator)
}

sqlite_column_count :: proc(statement: ^SQLite_Statement) -> int {
	if statement == nil || statement.handle == nil {
		return 0
	}
	return statement.library.api.sqlite_column_count(statement.handle)
}

sqlite_column_name :: proc(
	statement: ^SQLite_Statement,
	index: int,
	allocator := context.allocator,
) -> string {
	if statement == nil || statement.handle == nil {
		return strings.clone("", allocator)
	}
	native_name := statement.library.api.sqlite_column_name(
		statement.handle,
		index,
	)
	if native_name == nil {
		return strings.clone("", allocator)
	}
	defer statement.library.api.string_free(native_name)
	return strings.clone(string(native_name), allocator)
}

sqlite_column_kind :: proc(statement: ^SQLite_Statement, index: int) -> SQLite_Kind {
	if statement == nil || statement.handle == nil {
		return .Null
	}
	return SQLite_Kind(statement.library.api.sqlite_column_type(
		statement.handle,
		index,
	))
}

sqlite_column_int :: proc(statement: ^SQLite_Statement, index: int) -> i64 {
	if statement == nil || statement.handle == nil {
		return 0
	}
	return statement.library.api.sqlite_column_int64(statement.handle, index)
}

sqlite_column_float :: proc(statement: ^SQLite_Statement, index: int) -> f64 {
	if statement == nil || statement.handle == nil {
		return 0
	}
	return statement.library.api.sqlite_column_double(statement.handle, index)
}

sqlite_column_text :: proc(
	statement: ^SQLite_Statement,
	index: int,
	allocator := context.allocator,
) -> string {
	if statement == nil || statement.handle == nil {
		return strings.clone("", allocator)
	}
	length := statement.library.api.sqlite_column_bytes(statement.handle, index)
	data := statement.library.api.sqlite_column_text(statement.handle, index)
	if data == nil || length <= 0 {
		return strings.clone("", allocator)
	}
	value, error := strings.clone_from_ptr((^u8)(data), length, allocator)
	if error != nil {
		return strings.clone("", allocator)
	}
	return value
}

sqlite_column_blob :: proc(
	statement: ^SQLite_Statement,
	index: int,
	allocator := context.allocator,
) -> []u8 {
	if statement == nil || statement.handle == nil {
		return nil
	}
	length := statement.library.api.sqlite_column_bytes(statement.handle, index)
	data := statement.library.api.sqlite_column_blob(statement.handle, index)
	if length <= 0 {
		return make([]u8, 0, allocator)
	}
	if data == nil {
		return nil
	}
	value := make([]u8, length, allocator)
	copy(value, ([^]u8)(data)[:length])
	return value
}

sqlite_changes :: proc(db: ^SQLite_DB) -> i64 {
	if db == nil || db.handle == nil {
		return 0
	}
	return db.library.api.sqlite_changes(db.handle)
}

sqlite_total_changes :: proc(db: ^SQLite_DB) -> i64 {
	if db == nil || db.handle == nil {
		return 0
	}
	return db.library.api.sqlite_total_changes(db.handle)
}

sqlite_last_insert_rowid :: proc(db: ^SQLite_DB) -> i64 {
	if db == nil || db.handle == nil {
		return 0
	}
	return db.library.api.sqlite_last_insert_rowid(db.handle)
}

sqlite_autocommit :: proc(db: ^SQLite_DB) -> bool {
	return db != nil &&
	       db.handle != nil &&
	       db.library.api.sqlite_autocommit(db.handle)
}

sqlite_busy_timeout :: proc(db: ^SQLite_DB, milliseconds: int) -> int {
	if db == nil || db.handle == nil {
		return SQLITE_MISUSE
	}
	return db.library.api.sqlite_busy_timeout(db.handle, milliseconds)
}

sqlite_interrupt :: proc(db: ^SQLite_DB) {
	if db != nil && db.handle != nil {
		db.library.api.sqlite_interrupt(db.handle)
	}
}

sqlite_version :: proc(
	library: ^Library,
	allocator := context.allocator,
) -> (version: string, ok: bool) {
	if !sqlite_available(library) {
		return "", false
	}
	native_version := library.api.sqlite_version()
	if native_version == nil {
		return "", false
	}
	defer library.api.string_free(native_version)
	return strings.clone(string(native_version), allocator), true
}

sqlite_source_id :: proc(
	library: ^Library,
	allocator := context.allocator,
) -> (source_id: string, ok: bool) {
	if !sqlite_available(library) {
		return "", false
	}
	native_source_id := library.api.sqlite_source_id()
	if native_source_id == nil {
		return "", false
	}
	defer library.api.string_free(native_source_id)
	return strings.clone(string(native_source_id), allocator), true
}

sqlite_compile_option_used :: proc(library: ^Library, option: string) -> bool {
	if !sqlite_available(library) {
		return false
	}
	option_c := strings.clone_to_cstring(option, context.temp_allocator)
	return library.api.sqlite_compile_option_used(option_c)
}
