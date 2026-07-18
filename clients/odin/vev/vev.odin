// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package vev

import "core:dynlib"
import "core:strings"

ABI_VERSION :: 1

@(private)
API :: struct {
	abi_version:  proc "c" () -> u32 `dynlib:"vev_abi_version"`,
	open_memory:  proc "c" () -> rawptr `dynlib:"vev_conn_open_memory"`,
	close_conn:   proc "c" (conn: rawptr) `dynlib:"vev_conn_close"`,
	transact_edn: proc "c" (conn: rawptr, tx_text: cstring) -> cstring `dynlib:"vev_transact_edn"`,
	query_edn:    proc "c" (conn: rawptr, query_text: cstring) -> cstring `dynlib:"vev_query_edn"`,
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
	   library.api.string_free == nil ||
	   library.api.abi_version() != ABI_VERSION {
		dynlib.unload_library(library.api.__handle)
		return {}, false
	}

	return library, true
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

close :: proc(connection: ^Connection) {
	if connection == nil || connection.handle == nil {
		return
	}
	connection.library.api.close_conn(connection.handle)
	connection^ = {}
}

transact :: proc(
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
