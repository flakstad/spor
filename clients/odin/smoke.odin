package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"

Vev_API :: struct {
	version:       proc "c" () -> cstring `dynlib:"vev_version"`,
	open_memory:   proc "c" () -> rawptr `dynlib:"vev_conn_open_memory"`,
	close_conn:    proc "c" (conn: rawptr) `dynlib:"vev_conn_close"`,
	transact_edn:  proc "c" (conn: rawptr, tx_text: cstring) -> cstring `dynlib:"vev_transact_edn"`,
	query_edn:     proc "c" (conn: rawptr, query_text: cstring) -> cstring `dynlib:"vev_query_edn"`,
	db:            proc "c" (conn: rawptr) -> rawptr `dynlib:"vev_conn_db"`,
	db_release:    proc "c" (db: rawptr) `dynlib:"vev_db_release"`,
	prepare_query: proc "c" (query_text: cstring) -> rawptr `dynlib:"vev_prepare_query_edn"`,
	free_query:    proc "c" (query: rawptr) `dynlib:"vev_prepared_query_free"`,
	query_db:      proc "c" (db: rawptr, query: rawptr, inputs_text: cstring) -> cstring `dynlib:"vev_query_db_prepared_with_inputs"`,
	with_report:   proc "c" (db: rawptr, tx_text: cstring) -> rawptr `dynlib:"vev_with_edn_report"`,
	report_edn:    proc "c" (report: rawptr) -> cstring `dynlib:"vev_tx_report_edn"`,
	report_before: proc "c" (report: rawptr) -> rawptr `dynlib:"vev_tx_report_db_before"`,
	report_after:  proc "c" (report: rawptr) -> rawptr `dynlib:"vev_tx_report_db_after"`,
	report_free:   proc "c" (report: rawptr) `dynlib:"vev_tx_report_free"`,
	string_free:   proc "c" (text: cstring) `dynlib:"vev_string_free"`,
	__handle:      dynlib.Library,
}

platform_library_name :: proc() -> string {
	when ODIN_OS == .Darwin {
		return "libvev.dylib"
	} else when ODIN_OS == .Linux {
		return "libvev.so"
	} else when ODIN_OS == .Windows {
		return "vev.dll"
	}
	return "libvev"
}

default_library_path :: proc() -> string {
	path, err := os.join_path({"build", "lib", platform_library_name()}, context.allocator)
	if err != nil {
		return strings.clone(platform_library_name())
	}
	return path
}

to_cstring :: proc(text: string) -> cstring {
	return strings.clone_to_cstring(text, context.allocator)
}

main :: proc() {
	library_path := ""
	if len(os.args) > 1 {
		library_path = strings.clone(os.args[1])
	} else {
		library_path = default_library_path()
	}
	defer delete(library_path)

	api := Vev_API{}
	_, ok := dynlib.initialize_symbols(&api, library_path)
	if !ok {
		fmt.eprintln("failed to load Vev native library:", library_path)
		os.exit(1)
	}
	defer dynlib.unload_library(api.__handle)

	if api.version == nil || api.open_memory == nil || api.close_conn == nil || api.transact_edn == nil || api.query_edn == nil || api.db == nil || api.db_release == nil || api.prepare_query == nil || api.free_query == nil || api.query_db == nil || api.with_report == nil || api.report_edn == nil || api.report_before == nil || api.report_after == nil || api.report_free == nil || api.string_free == nil {
		fmt.eprintln("loaded library does not expose the expected Vev ABI")
		os.exit(1)
	}

	conn := api.open_memory()
	if conn == nil {
		fmt.eprintln("failed to create Vev connection")
		os.exit(1)
	}
	defer api.close_conn(conn)

	tx := to_cstring(`[
		{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
		{:db/id 2 :user/name "Grace" :user/email "grace@example.com"}
	]`)
	defer delete(tx)

	tx_result := api.transact_edn(conn, tx)
	if tx_result == nil {
		fmt.eprintln("transaction returned nil")
		os.exit(1)
	}
	defer api.string_free(tx_result)
	fmt.println("tx:", tx_result)

	query := to_cstring(`[:find ?name :where [?e :user/name ?name]]`)
	defer delete(query)

	query_result := api.query_edn(conn, query)
	if query_result == nil {
		fmt.eprintln("query returned nil")
		os.exit(1)
	}
	defer api.string_free(query_result)

	result := string(query_result)
	fmt.println("query:", result)
	if !strings.contains(result, `"Ada"`) || !strings.contains(result, `"Grace"`) {
		fmt.eprintln("unexpected query result:", result)
		os.exit(1)
	}

	snapshot := api.db(conn)
	if snapshot == nil {
		fmt.eprintln("failed to retain DB snapshot")
		os.exit(1)
	}
	defer api.db_release(snapshot)

	later_tx := to_cstring(`[{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}]`)
	defer delete(later_tx)
	later_result := api.transact_edn(conn, later_tx)
	if later_result == nil {
		fmt.eprintln("later transaction returned nil")
		os.exit(1)
	}
	defer api.string_free(later_result)

	all_names_query_text := to_cstring(`[:find ?e ?name :where [?e :user/name ?name]]`)
	defer delete(all_names_query_text)
	all_names_query := api.prepare_query(all_names_query_text)
	if all_names_query == nil {
		fmt.eprintln("failed to prepare DB query")
		os.exit(1)
	}
	defer api.free_query(all_names_query)

	with_tx := to_cstring(`[{:db/id 4 :user/name "Barbara"}]`)
	defer delete(with_tx)
	report := api.with_report(snapshot, with_tx)
	if report == nil {
		fmt.eprintln("with report returned nil")
		os.exit(1)
	}
	defer api.report_free(report)

	report_text := api.report_edn(report)
	if report_text == nil {
		fmt.eprintln("with report EDN returned nil")
		os.exit(1)
	}
	defer api.string_free(report_text)
	fmt.println("with report:", report_text)

	report_before := api.report_before(report)
	report_after := api.report_after(report)
	if report_before == nil || report_after == nil {
		fmt.eprintln("with report did not expose DB values")
		os.exit(1)
	}
	defer api.db_release(report_before)
	defer api.db_release(report_after)

	empty_inputs := to_cstring(`[]`)
	defer delete(empty_inputs)
	before_result := api.query_db(report_before, all_names_query, empty_inputs)
	after_result := api.query_db(report_after, all_names_query, empty_inputs)
	if before_result == nil || after_result == nil {
		fmt.eprintln("with report DB query returned nil")
		os.exit(1)
	}
	defer api.string_free(before_result)
	defer api.string_free(after_result)

	before_text := string(before_result)
	after_text := string(after_result)
	if strings.contains(before_text, `"Barbara"`) || !strings.contains(after_text, `"Barbara"`) {
		fmt.eprintln("unexpected with report DB results:", before_text, after_text)
		os.exit(1)
	}
}
