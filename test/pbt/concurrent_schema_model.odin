package main

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CONCURRENT_SCHEMA_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "schema", "unique", "atomic", "failure", "linearizable", "snapshot", "log", "reopen", "model"}
CONCURRENT_CARDINALITY_SCHEMA_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "schema", "cardinality", "atomic", "linearizable", "snapshot", "log", "reopen", "model"}
CONCURRENT_COMPONENT_SCHEMA_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "schema", "component", "cascade", "retract", "atomic", "linearizable", "snapshot", "log", "reopen", "model"}

CONCURRENT_SCHEMA :: `[
	{:db/id 100 :db/ident :concurrent-schema/email :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :concurrent-schema/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

CONCURRENT_CARDINALITY_SCHEMA :: `[
	{:db/id 100 :db/ident :concurrent-cardinality/value :db/valueType :db.type/string :db/cardinality :db.cardinality/many}
	{:db/id 101 :db/ident :concurrent-cardinality/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

CONCURRENT_COMPONENT_SCHEMA :: `[
	{:db/id 100 :db/ident :concurrent-component/child :db/valueType :db.type/ref :db/cardinality :db.cardinality/one :db/isComponent false}
	{:db/id 101 :db/ident :concurrent-component/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :concurrent-component/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Concurrent_Schema_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	tx:         string,
	report:     string,
	committed:  bool,
}

concurrent_component_schema_property :: proc(t: ^pbt.T) -> pbt.Result {
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	schema_started_first := pbt.draw(t, pbt.boolean())
	pbt.cover(t, resident_mode == 0, 15, "concurrent-component-source-backed")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-component-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-component-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-component-both-resident")
	pbt.cover(t, schema_started_first, 35, "concurrent-component-schema-started-first")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-component path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create concurrent-component seed")}
	setup := [?]string{
		CONCURRENT_COMPONENT_SCHEMA,
		`[{:db/id 1 :concurrent-component/name "parent" :concurrent-component/child 2}
		  {:db/id 2 :concurrent-component/name "child"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(&seed, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			vev.close(&seed)
			return pbt.error(fmt.tprintf("could not initialize concurrent component: %s", report))
		}
	}
	vev.close(&seed)

	schema_connection, schema_connection_ok := vev.connect(&library, path)
	if !schema_connection_ok {return pbt.error("could not open concurrent component schema writer")}
	defer vev.close(&schema_connection)
	data_connection, data_connection_ok := vev.connect(&library, path)
	if !data_connection_ok {return pbt.error("could not open concurrent component retract writer")}
	defer vev.close(&data_connection)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&schema_connection) {
		return pbt.error("could not make component schema writer resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&data_connection) {
		return pbt.error("could not make component retract writer resident")
	}
	checkpoint, checkpoint_ok := vev.db(&schema_connection)
	if !checkpoint_ok {return pbt.error("could not retain concurrent-component checkpoint")}
	defer vev.close(&checkpoint)

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	schema_worker := Concurrent_Schema_Worker{
		connection = &schema_connection,
		barrier = &barrier,
		tx = `[[:db/add 10 :concurrent-component/marker "schema"] [:db/add 100 :db/isComponent true]]`,
	}
	retract_worker := Concurrent_Schema_Worker{
		connection = &data_connection,
		barrier = &barrier,
		tx = `[[:db/add 20 :concurrent-component/marker "retract"] [:db.fn/retractEntity 1]]`,
	}
	schema_thread: ^thread.Thread
	retract_thread: ^thread.Thread
	if schema_started_first {
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
		if schema_thread == nil {return pbt.error("could not start concurrent component schema worker")}
		retract_thread = thread.create_and_start_with_poly_data(&retract_worker, concurrent_schema_worker_run)
	} else {
		retract_thread = thread.create_and_start_with_poly_data(&retract_worker, concurrent_schema_worker_run)
		if retract_thread == nil {return pbt.error("could not start concurrent component retract worker")}
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
	}
	if schema_thread == nil || retract_thread == nil {return pbt.error("could not start concurrent component race")}
	thread.join(schema_thread)
	thread.join(retract_thread)
	thread.destroy(schema_thread)
	thread.destroy(retract_thread)
	defer delete(schema_worker.report)
	defer delete(retract_worker.report)
	if !schema_worker.committed || !retract_worker.committed {
		return pbt.fail(fmt.tprintf(
			"concurrent component race lost a legal commit: resident=%d committed=%v/%v reports=%s / %s",
			resident_mode,
			schema_worker.committed,
			retract_worker.committed,
			schema_worker.report,
			retract_worker.report,
		))
	}
	if result := multi_connection_metadata_check(t, &schema_connection, &data_connection, 4, "after concurrent component race"); result.status != .Pass {return result}
	if result := concurrent_component_checkpoint_check(t, &checkpoint); result.status != .Pass {return result}

	vev.close(&schema_connection)
	vev.close(&data_connection)
	schema_connection, schema_connection_ok = vev.connect(&library, path)
	data_connection, data_connection_ok = vev.connect(&library, path)
	if !schema_connection_ok || !data_connection_ok {return pbt.error("could not reopen concurrent-component connections")}
	connections := [?]^vev.Durable_Connection{&schema_connection, &data_connection}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened concurrent-component database")}
		if index == 0 {
			child := query_name_attr(t, &database, 2, ":concurrent-component/name")
			if !child.ok {
				vev.close(&database)
				return pbt.error("could not classify concurrent-component commit order")
			}
			pbt.cover(t, child.found, 0, "concurrent-component-retract-committed-first")
			pbt.cover(t, !child.found, 0, "concurrent-component-schema-committed-first")
		}
		result := concurrent_component_final_check(t, &database, fmt.tprintf("reopened concurrent component %d", index))
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	schema_log, schema_log_ok := index_maintenance_log_edn(t, &schema_connection)
	retract_log, retract_log_ok := index_maintenance_log_edn(t, &data_connection)
	if !schema_log_ok || !retract_log_ok || schema_log != retract_log {
		return pbt.fail("concurrent component writers produced divergent logs")
	}
	return concurrent_component_checkpoint_check(t, &checkpoint)
}

concurrent_component_checkpoint_check :: proc(t: ^pbt.T, database: ^vev.DB) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 2 {return pbt.fail(fmt.tprintf("concurrent-component checkpoint basis changed: %d", basis))}
	if result := concurrent_component_flag_check(database, false, "concurrent-component checkpoint"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":concurrent-component/name", "parent", true, "concurrent-component checkpoint"); result.status != .Pass {return result}
	return multi_connection_conflict_attr_check(t, database, 2, ":concurrent-component/name", "child", true, "concurrent-component checkpoint")
}

concurrent_component_final_check :: proc(t: ^pbt.T, database: ^vev.DB, label: string) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 4 {return pbt.fail(fmt.tprintf("%s basis: expected=4 actual=%d", label, basis))}
	if result := concurrent_component_flag_check(database, true, label); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":concurrent-component/name", "parent", false, label); result.status != .Pass {return result}
	child := query_name_attr(t, database, 2, ":concurrent-component/name")
	if !child.ok || (child.found && child.name != "child") {
		return pbt.fail(fmt.tprintf("%s component child has impossible state: found=%v value=%q", label, child.found, child.name))
	}
	if result := multi_connection_conflict_attr_check(t, database, 10, ":concurrent-component/marker", "schema", true, label); result.status != .Pass {return result}
	return multi_connection_conflict_attr_check(t, database, 20, ":concurrent-component/marker", "retract", true, label)
}

concurrent_component_flag_check :: proc(database: ^vev.DB, expected: bool, label: string) -> pbt.Result {
	result, query_ok := vev.query(database, `[:find ?component . :where [100 :db/isComponent ?component]]`)
	if !query_ok {return pbt.error(fmt.tprintf("%s component flag query failed", label))}
	defer vev.close(&result)
	value, value_ok := vev.value(&result)
	actual, actual_ok := vev.as_bool(value)
	if !value_ok || !actual_ok || actual != expected {
		return pbt.fail(fmt.tprintf("%s component flag: expected=%v actual=%v", label, expected, actual))
	}
	return pbt.pass()
}

concurrent_cardinality_schema_property :: proc(t: ^pbt.T) -> pbt.Result {
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	schema_started_first := pbt.draw(t, pbt.boolean())
	pbt.cover(t, resident_mode == 0, 15, "concurrent-cardinality-source-backed")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-cardinality-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-cardinality-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-cardinality-both-resident")
	pbt.cover(t, schema_started_first, 35, "concurrent-cardinality-schema-started-first")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-cardinality path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create concurrent-cardinality seed")}
	setup := [?]string{
		CONCURRENT_CARDINALITY_SCHEMA,
		`[{:db/id 1 :concurrent-cardinality/value "a"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(&seed, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			vev.close(&seed)
			return pbt.error(fmt.tprintf("could not initialize concurrent cardinality: %s", report))
		}
	}
	vev.close(&seed)

	schema_connection, schema_connection_ok := vev.connect(&library, path)
	if !schema_connection_ok {return pbt.error("could not open concurrent cardinality schema writer")}
	defer vev.close(&schema_connection)
	data_connection, data_connection_ok := vev.connect(&library, path)
	if !data_connection_ok {return pbt.error("could not open concurrent cardinality data writer")}
	defer vev.close(&data_connection)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&schema_connection) {
		return pbt.error("could not make cardinality schema writer resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&data_connection) {
		return pbt.error("could not make cardinality data writer resident")
	}
	checkpoint, checkpoint_ok := vev.db(&schema_connection)
	if !checkpoint_ok {return pbt.error("could not retain concurrent-cardinality checkpoint")}
	defer vev.close(&checkpoint)

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	schema_worker := Concurrent_Schema_Worker{
		connection = &schema_connection,
		barrier = &barrier,
		tx = `[[:db/add 10 :concurrent-cardinality/marker "schema"] [:db/add 100 :db/cardinality :db.cardinality/one]]`,
	}
	data_worker := Concurrent_Schema_Worker{
		connection = &data_connection,
		barrier = &barrier,
		tx = `[[:db/add 20 :concurrent-cardinality/marker "data"] [:db/add 1 :concurrent-cardinality/value "b"]]`,
	}
	schema_thread: ^thread.Thread
	data_thread: ^thread.Thread
	if schema_started_first {
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
		if schema_thread == nil {return pbt.error("could not start concurrent cardinality schema worker")}
		data_thread = thread.create_and_start_with_poly_data(&data_worker, concurrent_schema_worker_run)
	} else {
		data_thread = thread.create_and_start_with_poly_data(&data_worker, concurrent_schema_worker_run)
		if data_thread == nil {return pbt.error("could not start concurrent cardinality data worker")}
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
	}
	if schema_thread == nil || data_thread == nil {return pbt.error("could not start concurrent cardinality race")}
	thread.join(schema_thread)
	thread.join(data_thread)
	thread.destroy(schema_thread)
	thread.destroy(data_thread)
	defer delete(schema_worker.report)
	defer delete(data_worker.report)
	if !schema_worker.committed || !data_worker.committed {
		return pbt.fail(fmt.tprintf(
			"concurrent cardinality race lost a legal commit: resident=%d committed=%v/%v reports=%s / %s",
			resident_mode,
			schema_worker.committed,
			data_worker.committed,
			schema_worker.report,
			data_worker.report,
		))
	}
	if result := multi_connection_metadata_check(t, &schema_connection, &data_connection, 4, "after concurrent cardinality race"); result.status != .Pass {
		return result
	}
	if result := concurrent_cardinality_checkpoint_check(t, &checkpoint); result.status != .Pass {return result}

	vev.close(&schema_connection)
	vev.close(&data_connection)
	schema_connection, schema_connection_ok = vev.connect(&library, path)
	data_connection, data_connection_ok = vev.connect(&library, path)
	if !schema_connection_ok || !data_connection_ok {return pbt.error("could not reopen concurrent-cardinality connections")}
	connections := [?]^vev.Durable_Connection{&schema_connection, &data_connection}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened concurrent-cardinality database")}
		if index == 0 {
			has_a, has_a_ok := concurrent_cardinality_value_exists(&database, "a")
			if !has_a_ok {
				vev.close(&database)
				return pbt.error("could not classify concurrent-cardinality commit order")
			}
			pbt.cover(t, has_a, 0, "concurrent-cardinality-data-committed-first")
			pbt.cover(t, !has_a, 0, "concurrent-cardinality-schema-committed-first")
		}
		result := concurrent_cardinality_final_check(t, &database, fmt.tprintf("reopened concurrent cardinality %d", index))
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	schema_log, schema_log_ok := index_maintenance_log_edn(t, &schema_connection)
	data_log, data_log_ok := index_maintenance_log_edn(t, &data_connection)
	if !schema_log_ok || !data_log_ok || schema_log != data_log {
		return pbt.fail("concurrent cardinality writers produced divergent logs")
	}
	return concurrent_cardinality_checkpoint_check(t, &checkpoint)
}

concurrent_cardinality_value_exists :: proc(database: ^vev.DB, expected: string) -> (found: bool, ok: bool) {
	query := fmt.tprintf(`[:find ?entity . :where [?entity :concurrent-cardinality/value "%s"]]`, expected)
	result, query_ok := vev.query(database, query)
	if !query_ok {return false, false}
	defer vev.close(&result)
	value, value_ok := vev.value(&result)
	if !value_ok {return false, false}
	if vev.kind(value) == .Nil {return false, true}
	_, entity_ok := vev.as_int(value)
	return entity_ok, entity_ok
}

concurrent_cardinality_checkpoint_check :: proc(t: ^pbt.T, database: ^vev.DB) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 2 {return pbt.fail(fmt.tprintf("concurrent-cardinality checkpoint basis changed: %d", basis))}
	if result := concurrent_schema_kind_check(t, database, ":db/cardinality", ":db.cardinality/many", "concurrent-cardinality checkpoint"); result.status != .Pass {return result}
	return concurrent_cardinality_values_check(t, database, true, false, "concurrent-cardinality checkpoint")
}

concurrent_cardinality_final_check :: proc(t: ^pbt.T, database: ^vev.DB, label: string) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 4 {return pbt.fail(fmt.tprintf("%s basis: expected=4 actual=%d", label, basis))}
	if result := concurrent_schema_kind_check(t, database, ":db/cardinality", ":db.cardinality/one", label); result.status != .Pass {return result}
	if result := concurrent_cardinality_values_check(t, database, false, true, label); result.status == .Pass {
		// Schema committed before the data write, which replaced "a" with "b".
	} else {
		if result := concurrent_cardinality_values_check(t, database, true, true, label); result.status != .Pass {
			return result
		}
		// Data committed first; switching to cardinality-one retained both legacy values.
	}
	if result := multi_connection_conflict_attr_check(t, database, 10, ":concurrent-cardinality/marker", "schema", true, label); result.status != .Pass {return result}
	return multi_connection_conflict_attr_check(t, database, 20, ":concurrent-cardinality/marker", "data", true, label)
}

concurrent_cardinality_values_check :: proc(t: ^pbt.T, database: ^vev.DB, expect_a, expect_b: bool, label: string) -> pbt.Result {
	values, values_ok := vev.query(database, `[:find ?value :where [1 :concurrent-cardinality/value ?value]]`)
	if !values_ok {return pbt.error(fmt.tprintf("%s cardinality values query failed", label))}
	defer vev.close(&values)
	value, value_ok := vev.value(&values)
	expected_count := int(expect_a) + int(expect_b)
	if !value_ok || vev.item_count(value) != expected_count {
		return pbt.fail(fmt.tprintf("%s cardinality value count: expected=%d actual=%d", label, expected_count, vev.item_count(value)))
	}
	seen_a, seen_b := false, false
	for index in 0 ..< vev.item_count(value) {
		row, row_ok := vev.item(value, index)
		item, item_ok := vev.item(row, 0)
		text_value, text_ok := vev.as_string(item, t.value_allocator)
		if !row_ok || !item_ok || !text_ok {return pbt.error(fmt.tprintf("%s cardinality value malformed", label))}
		if text_value == "a" {seen_a = true} else if text_value == "b" {seen_b = true} else {
			return pbt.fail(fmt.tprintf("%s cardinality unexpected value: %q", label, text_value))
		}
	}
	if seen_a != expect_a || seen_b != expect_b {
		return pbt.fail(fmt.tprintf("%s cardinality value set: a=%v/%v b=%v/%v", label, seen_a, expect_a, seen_b, expect_b))
	}
	return pbt.pass()
}

concurrent_schema_kind_check :: proc(t: ^pbt.T, database: ^vev.DB, attribute, expected, label: string) -> pbt.Result {
	actual := query_name_attr(t, database, 100, attribute)
	if !actual.ok {return pbt.error(fmt.tprintf("%s schema kind query failed", label))}
	if !actual.found || actual.name != expected {
		return pbt.fail(fmt.tprintf("%s schema kind: expected=%q found=%v value=%q", label, expected, actual.found, actual.name))
	}
	return pbt.pass()
}

concurrent_schema_property :: proc(t: ^pbt.T) -> pbt.Result {
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	schema_started_first := pbt.draw(t, pbt.boolean())
	pbt.cover(t, resident_mode == 0, 15, "concurrent-schema-source-backed")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-schema-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-schema-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-schema-both-resident")
	pbt.cover(t, schema_started_first, 35, "concurrent-schema-change-started-first")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-schema path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create concurrent-schema seed")}
	setup := [?]string{
		CONCURRENT_SCHEMA,
		`[{:db/id 1 :concurrent-schema/email "shared@example.test"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(&seed, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			vev.close(&seed)
			return pbt.error(fmt.tprintf("could not initialize concurrent schema: %s", report))
		}
	}
	vev.close(&seed)

	schema_connection, schema_connection_ok := vev.connect(&library, path)
	if !schema_connection_ok {return pbt.error("could not open concurrent schema writer")}
	defer vev.close(&schema_connection)
	data_connection, data_connection_ok := vev.connect(&library, path)
	if !data_connection_ok {return pbt.error("could not open concurrent schema data writer")}
	defer vev.close(&data_connection)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&schema_connection) {
		return pbt.error("could not make concurrent schema writer resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&data_connection) {
		return pbt.error("could not make concurrent schema data writer resident")
	}
	checkpoint, checkpoint_ok := vev.db(&schema_connection)
	if !checkpoint_ok {return pbt.error("could not retain concurrent-schema checkpoint")}
	defer vev.close(&checkpoint)

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	schema_worker := Concurrent_Schema_Worker{
		connection = &schema_connection,
		barrier = &barrier,
		tx = `[[:db/add 10 :concurrent-schema/marker "schema"] [:db/add 100 :db/unique :db.unique/value]]`,
	}
	data_worker := Concurrent_Schema_Worker{
		connection = &data_connection,
		barrier = &barrier,
		tx = `[[:db/add 20 :concurrent-schema/marker "data"] [:db/add 2 :concurrent-schema/email "shared@example.test"]]`,
	}
	schema_thread: ^thread.Thread
	data_thread: ^thread.Thread
	if schema_started_first {
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
		if schema_thread == nil {return pbt.error("could not start concurrent schema worker")}
		data_thread = thread.create_and_start_with_poly_data(&data_worker, concurrent_schema_worker_run)
	} else {
		data_thread = thread.create_and_start_with_poly_data(&data_worker, concurrent_schema_worker_run)
		if data_thread == nil {return pbt.error("could not start concurrent schema data worker")}
		schema_thread = thread.create_and_start_with_poly_data(&schema_worker, concurrent_schema_worker_run)
	}
	if schema_thread == nil || data_thread == nil {return pbt.error("could not start concurrent schema race")}
	thread.join(schema_thread)
	thread.join(data_thread)
	thread.destroy(schema_thread)
	thread.destroy(data_thread)
	defer delete(schema_worker.report)
	defer delete(data_worker.report)

	commit_count := int(schema_worker.committed) + int(data_worker.committed)
	if commit_count != 1 {
		return pbt.fail(fmt.tprintf(
			"concurrent schema race was not linearizable: resident=%d committed=%v/%v reports=%s / %s",
			resident_mode,
			schema_worker.committed,
			data_worker.committed,
			schema_worker.report,
			data_worker.report,
		))
	}
	loser_report := data_worker.report
	if !schema_worker.committed {loser_report = schema_worker.report}
	if !strings.contains(loser_report, ":ok false") || !strings.contains(loser_report, "schema unique conflict") {
		return pbt.fail(fmt.tprintf("concurrent schema loser returned wrong error: %s", loser_report))
	}
	if result := multi_connection_metadata_check(t, &schema_connection, &data_connection, 3, "after concurrent schema race"); result.status != .Pass {
		return result
	}
	if result := concurrent_schema_checkpoint_check(t, &checkpoint); result.status != .Pass {
		return result
	}

	vev.close(&schema_connection)
	vev.close(&data_connection)
	schema_connection, schema_connection_ok = vev.connect(&library, path)
	data_connection, data_connection_ok = vev.connect(&library, path)
	if !schema_connection_ok || !data_connection_ok {return pbt.error("could not reopen concurrent-schema connections")}
	connections := [?]^vev.Durable_Connection{&schema_connection, &data_connection}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened concurrent-schema database")}
		result := concurrent_schema_final_check(t, &database, schema_worker.committed, fmt.tprintf("reopened concurrent schema %d", index))
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	schema_log, schema_log_ok := index_maintenance_log_edn(t, &schema_connection)
	data_log, data_log_ok := index_maintenance_log_edn(t, &data_connection)
	if !schema_log_ok || !data_log_ok || schema_log != data_log {
		return pbt.fail("concurrent schema writers produced divergent logs")
	}
	return concurrent_schema_checkpoint_check(t, &checkpoint)
}

concurrent_schema_worker_run :: proc(worker: ^Concurrent_Schema_Worker) {
	sync.barrier_wait(worker.barrier)
	report, committed := vev.transact(worker.connection, worker.tx)
	worker.report = strings.clone(report)
	worker.committed = committed
	delete(report)
}

concurrent_schema_checkpoint_check :: proc(t: ^pbt.T, database: ^vev.DB) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 2 {return pbt.fail(fmt.tprintf("concurrent-schema checkpoint basis changed: %d", basis))}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":concurrent-schema/email", "shared@example.test", true, "concurrent-schema checkpoint"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 2, ":concurrent-schema/email", "shared@example.test", false, "concurrent-schema checkpoint"); result.status != .Pass {return result}
	return concurrent_schema_unique_check(t, database, false, "concurrent-schema checkpoint")
}

concurrent_schema_final_check :: proc(t: ^pbt.T, database: ^vev.DB, schema_won: bool, label: string) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 3 {return pbt.fail(fmt.tprintf("%s basis: expected=3 actual=%d", label, basis))}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":concurrent-schema/email", "shared@example.test", true, label); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 2, ":concurrent-schema/email", "shared@example.test", !schema_won, label); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 10, ":concurrent-schema/marker", "schema", schema_won, label); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, database, 20, ":concurrent-schema/marker", "data", !schema_won, label); result.status != .Pass {return result}
	return concurrent_schema_unique_check(t, database, schema_won, label)
}

concurrent_schema_unique_check :: proc(t: ^pbt.T, database: ^vev.DB, expected: bool, label: string) -> pbt.Result {
	actual := query_name_attr(t, database, 100, ":db/unique")
	if !actual.ok {return pbt.error(fmt.tprintf("%s unique schema query failed", label))}
	if expected && (!actual.found || actual.name != ":db.unique/value") {
		return pbt.fail(fmt.tprintf("%s expected unique schema, found=%v value=%q", label, actual.found, actual.name))
	}
	if !expected && actual.found {
		return pbt.fail(fmt.tprintf("%s unexpectedly enabled unique schema: %q", label, actual.name))
	}
	return pbt.pass()
}
