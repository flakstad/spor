package main

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CONCURRENT_CONNECTION_MAX_ROUNDS :: 8
CONCURRENT_CONNECTION_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "snapshot", "log", "reopen", "model"}
CONCURRENT_MAINTENANCE_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "index", "maintenance", "compaction", "snapshot", "log", "reopen", "model"}
CONCURRENT_SNAPSHOT_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "snapshot", "atomic", "linearizable", "reopen", "model"}
CONCURRENT_SNAPSHOT_MAINTENANCE_TAGS := [?]string{"core", "durable", "multi-connection", "concurrent", "race", "snapshot", "index", "maintenance", "compaction", "atomic", "reopen", "model"}
CONCURRENT_REPORT_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "report", "snapshot", "atomic", "linearizable", "model"}

CONCURRENT_CONNECTION_SCHEMA :: `[
	{:db/id 100 :db/ident :race/value :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Concurrent_Connection_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	rounds:     int,
	entity_base: int,
	value:      string,
	failures:   int,
	basis_conflicts: int,
	other_failures: int,
	last_error: string,
	last_basis: u64,
}

Concurrent_Maintenance_Worker :: struct {
	connection:    ^vev.Durable_Connection,
	barrier:       ^sync.Barrier,
	rounds:        int,
	steps:         int,
	compact_first: bool,
	failures:      int,
}

Concurrent_Snapshot_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	database:   vev.DB,
	ok:         bool,
}

Concurrent_Snapshot_Write_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	tx:         string,
	committed:  bool,
	report:     string,
}

Concurrent_Compact_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	ok:         bool,
}

Concurrent_Report_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	tx:         string,
	report:     vev.Native_Tx_Report,
	ok:         bool,
}

concurrent_report_property :: proc(t: ^pbt.T) -> pbt.Result {
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	left_value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	right_value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	pbt.cover(t, resident_mode == 0, 15, "concurrent-report-source-backed")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-report-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-report-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-report-both-resident")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-report path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create concurrent-report seed")}
	seed_report, schema_ok := vev.transact(&seed, CONCURRENT_CONNECTION_SCHEMA, t.value_allocator)
	vev.close(&seed)
	if !schema_ok || !strings.contains(seed_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not install concurrent-report schema: %s", seed_report))
	}

	left, left_ok := vev.connect(&library, path)
	if !left_ok {return pbt.error("could not open concurrent-report left connection")}
	defer vev.close(&left)
	right, right_ok := vev.connect(&library, path)
	if !right_ok {return pbt.error("could not open concurrent-report right connection")}
	defer vev.close(&right)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&left) {
		return pbt.error("could not make concurrent-report left connection resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&right) {
		return pbt.error("could not make concurrent-report right connection resident")
	}

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	left_tx := fmt.tprintf(`[[:db/add 1000 :race/value "%s"]]`, MODEL_NAMES[left_value_index])
	right_tx := fmt.tprintf(`[[:db/add 2000 :race/value "%s"]]`, MODEL_NAMES[right_value_index])
	left_worker := Concurrent_Report_Worker{connection = &left, barrier = &barrier, tx = left_tx}
	right_worker := Concurrent_Report_Worker{connection = &right, barrier = &barrier, tx = right_tx}
	left_thread := thread.create_and_start_with_poly_data(&left_worker, concurrent_report_worker_run)
	if left_thread == nil {return pbt.error("could not start concurrent-report left worker")}
	right_thread := thread.create_and_start_with_poly_data(&right_worker, concurrent_report_worker_run)
	if right_thread == nil {
		thread.destroy(left_thread)
		return pbt.error("could not start concurrent-report right worker")
	}
	thread.join(left_thread)
	thread.join(right_thread)
	thread.destroy(left_thread)
	thread.destroy(right_thread)
	defer vev.close(&left_worker.report)
	defer vev.close(&right_worker.report)
	if !left_worker.ok || !right_worker.ok {
		return pbt.fail(fmt.tprintf("concurrent rich reports failed to open: %v/%v", left_worker.ok, right_worker.ok))
	}
	left_edn, left_edn_ok := vev.tx_report_edn(&left_worker.report, t.value_allocator)
	right_edn, right_edn_ok := vev.tx_report_edn(&right_worker.report, t.value_allocator)
	if !left_edn_ok || !right_edn_ok || !strings.contains(left_edn, ":ok true") || !strings.contains(right_edn, ":ok true") {
		return pbt.fail(fmt.tprintf("concurrent rich reports did not both commit: %s / %s", left_edn, right_edn))
	}
	left_before, left_before_ok := vev.tx_report_db_before(&left_worker.report)
	left_after, left_after_ok := vev.tx_report_db_after(&left_worker.report)
	right_before, right_before_ok := vev.tx_report_db_before(&right_worker.report)
	right_after, right_after_ok := vev.tx_report_db_after(&right_worker.report)
	if !left_before_ok || !left_after_ok || !right_before_ok || !right_after_ok {
		vev.close(&left_before)
		vev.close(&left_after)
		vev.close(&right_before)
		vev.close(&right_after)
		return pbt.error("could not retain concurrent report snapshots")
	}
	defer vev.close(&left_before)
	defer vev.close(&left_after)
	defer vev.close(&right_before)
	defer vev.close(&right_after)
	left_before_basis, left_before_basis_ok := vev.basis_t(&left_before)
	left_after_basis, left_after_basis_ok := vev.basis_t(&left_after)
	right_before_basis, right_before_basis_ok := vev.basis_t(&right_before)
	right_after_basis, right_after_basis_ok := vev.basis_t(&right_after)
	if !left_before_basis_ok || !left_after_basis_ok || !right_before_basis_ok || !right_after_basis_ok {
		return pbt.error("could not inspect concurrent report coordinates")
	}
	left_first := left_before_basis == 1 && left_after_basis == 2 && right_before_basis == 2 && right_after_basis == 3
	right_first := right_before_basis == 1 && right_after_basis == 2 && left_before_basis == 2 && left_after_basis == 3
	if !left_first && !right_first {
		return pbt.fail(fmt.tprintf(
			"concurrent reports do not form one serial history: left=%d->%d right=%d->%d resident=%d",
			left_before_basis,
			left_after_basis,
			right_before_basis,
			right_after_basis,
			resident_mode,
		))
	}
	first_after := &left_after
	second_before := &right_before
	second_after := &right_after
	first_entity := u64(1000)
	second_entity := u64(2000)
	first_value := MODEL_NAMES[left_value_index]
	second_value := MODEL_NAMES[right_value_index]
	if right_first {
		first_after = &right_after
		second_before = &left_before
		second_after = &left_after
		first_entity = 2000
		second_entity = 1000
		first_value = MODEL_NAMES[right_value_index]
		second_value = MODEL_NAMES[left_value_index]
	}
	if result := multi_connection_conflict_attr_check(t, first_after, first_entity, ":race/value", first_value, true, "first concurrent report after"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, first_after, second_entity, ":race/value", second_value, false, "first concurrent report after"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, second_before, first_entity, ":race/value", first_value, true, "second concurrent report before"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, second_before, second_entity, ":race/value", second_value, false, "second concurrent report before"); result.status != .Pass {return result}
	if result := multi_connection_conflict_attr_check(t, second_after, first_entity, ":race/value", first_value, true, "second concurrent report after"); result.status != .Pass {return result}
	return multi_connection_conflict_attr_check(t, second_after, second_entity, ":race/value", second_value, true, "second concurrent report after")
}

concurrent_report_worker_run :: proc(worker: ^Concurrent_Report_Worker) {
	sync.barrier_wait(worker.barrier)
	worker.report, worker.ok = vev.transact_report_durable(worker.connection, worker.tx)
}

CONCURRENT_SNAPSHOT_ENTITY_COUNT :: 64

concurrent_snapshot_maintenance_property :: proc(t: ^pbt.T) -> pbt.Result {
	compact_started_first := pbt.draw(t, pbt.boolean())
	reverse_seed := pbt.draw(t, pbt.boolean())
	pbt.cover(t, compact_started_first, 35, "concurrent-snapshot-compaction-started-first")
	pbt.cover(t, reverse_seed, 35, "concurrent-snapshot-compaction-reverse-seed")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate snapshot-compaction path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create snapshot-compaction seed")}
	schema_report, schema_ok := vev.transact(&seed, CONCURRENT_CONNECTION_SCHEMA, t.value_allocator)
	if !schema_ok || !strings.contains(schema_report, ":ok true") {
		vev.close(&seed)
		return pbt.error(fmt.tprintf("could not install snapshot-compaction schema: %s", schema_report))
	}
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< CONCURRENT_SNAPSHOT_ENTITY_COUNT {
		entity := offset + 1
		if reverse_seed {entity = CONCURRENT_SNAPSHOT_ENTITY_COUNT - offset}
		append(&parts, fmt.tprintf(`[:db/add %d :race/value "%s"]`, entity, MODEL_NAMES[entity % MODEL_VALUE_COUNT]))
	}
	append(&parts, "]")
	seed_tx := strings.concatenate(parts[:])
	seed_report, seed_committed := vev.transact(&seed, seed_tx, t.value_allocator)
	vev.close(&seed)
	if !seed_committed || !strings.contains(seed_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not seed snapshot-compaction data: %s", seed_report))
	}

	reader, reader_ok := vev.connect(&library, path)
	if !reader_ok {return pbt.error("could not open snapshot-compaction reader")}
	defer vev.close(&reader)
	maintenance, maintenance_ok := vev.connect(&library, path)
	if !maintenance_ok {return pbt.error("could not open snapshot-compaction maintenance connection")}
	defer vev.close(&maintenance)
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	snapshot_worker := Concurrent_Snapshot_Worker{connection = &reader, barrier = &barrier}
	compact_worker := Concurrent_Compact_Worker{connection = &maintenance, barrier = &barrier}
	snapshot_thread: ^thread.Thread
	compact_thread: ^thread.Thread
	if compact_started_first {
		compact_thread = thread.create_and_start_with_poly_data(&compact_worker, concurrent_compact_worker_run)
		if compact_thread == nil {return pbt.error("could not start snapshot-compaction maintenance worker")}
		snapshot_thread = thread.create_and_start_with_poly_data(&snapshot_worker, concurrent_snapshot_worker_run)
	} else {
		snapshot_thread = thread.create_and_start_with_poly_data(&snapshot_worker, concurrent_snapshot_worker_run)
		if snapshot_thread == nil {return pbt.error("could not start snapshot-compaction snapshot worker")}
		compact_thread = thread.create_and_start_with_poly_data(&compact_worker, concurrent_compact_worker_run)
	}
	if snapshot_thread == nil || compact_thread == nil {return pbt.error("could not start snapshot-compaction race")}
	thread.join(snapshot_thread)
	thread.join(compact_thread)
	thread.destroy(snapshot_thread)
	thread.destroy(compact_thread)
	defer vev.close(&snapshot_worker.database)
	if !snapshot_worker.ok || !compact_worker.ok {
		return pbt.fail(fmt.tprintf("snapshot/compaction operation failed: snapshot=%v compact=%v", snapshot_worker.ok, compact_worker.ok))
	}
	basis, basis_ok := vev.basis_t(&snapshot_worker.database)
	if !basis_ok || basis != 2 {return pbt.fail(fmt.tprintf("snapshot/compaction changed logical basis: %d", basis))}
	for entity in 1 ..= CONCURRENT_SNAPSHOT_ENTITY_COUNT {
		expected := MODEL_NAMES[entity % MODEL_VALUE_COUNT]
		if result := multi_connection_conflict_attr_check(t, &snapshot_worker.database, u64(entity), ":race/value", expected, true, "snapshot during compaction"); result.status != .Pass {
			return result
		}
	}
	vev.close(&reader)
	vev.close(&maintenance)
	reader, reader_ok = vev.connect(&library, path)
	if !reader_ok {return pbt.error("could not reopen snapshot-compaction source")}
	return multi_connection_conflict_attr_check(t, &snapshot_worker.database, 1, ":race/value", MODEL_NAMES[1 % MODEL_VALUE_COUNT], true, "snapshot after compaction reopen")
}

concurrent_compact_worker_run :: proc(worker: ^Concurrent_Compact_Worker) {
	sync.barrier_wait(worker.barrier)
	worker.ok = vev.compact_indexes(worker.connection)
}

concurrent_snapshot_property :: proc(t: ^pbt.T) -> pbt.Result {
	writer_resident := pbt.draw(t, pbt.boolean())
	snapshot_started_first := pbt.draw(t, pbt.boolean())
	value_index := pbt.draw(t, pbt.int_range(1, MODEL_VALUE_COUNT - 1))
	pbt.cover(t, writer_resident, 35, "concurrent-snapshot-resident-writer")
	pbt.cover(t, snapshot_started_first, 35, "concurrent-snapshot-started-first")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-snapshot path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not create concurrent-snapshot seed")}
	setup := [?]string{
		CONCURRENT_CONNECTION_SCHEMA,
		`[{:db/id 1 :race/value "ada"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(&seed, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			vev.close(&seed)
			return pbt.error(fmt.tprintf("could not initialize concurrent snapshot: %s", report))
		}
	}
	vev.close(&seed)

	reader, reader_ok := vev.connect(&library, path)
	if !reader_ok {return pbt.error("could not open concurrent-snapshot reader")}
	defer vev.close(&reader)
	writer, writer_ok := vev.connect(&library, path)
	if !writer_ok {return pbt.error("could not open concurrent-snapshot writer")}
	defer vev.close(&writer)
	if writer_resident && !vev.ensure_resident(&writer) {
		return pbt.error("could not make concurrent-snapshot writer resident")
	}

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	value := MODEL_NAMES[value_index]
	write_tx := fmt.tprintf(`[
		[:db/add 1 :race/value "%s"]
		[:db/add 2 :race/value "%s"]
	]`, value, value)
	snapshot_worker := Concurrent_Snapshot_Worker{connection = &reader, barrier = &barrier}
	write_worker := Concurrent_Snapshot_Write_Worker{connection = &writer, barrier = &barrier, tx = write_tx}
	snapshot_thread: ^thread.Thread
	write_thread: ^thread.Thread
	if snapshot_started_first {
		snapshot_thread = thread.create_and_start_with_poly_data(&snapshot_worker, concurrent_snapshot_worker_run)
		if snapshot_thread == nil {return pbt.error("could not start concurrent snapshot worker")}
		write_thread = thread.create_and_start_with_poly_data(&write_worker, concurrent_snapshot_write_worker_run)
	} else {
		write_thread = thread.create_and_start_with_poly_data(&write_worker, concurrent_snapshot_write_worker_run)
		if write_thread == nil {return pbt.error("could not start concurrent snapshot writer")}
		snapshot_thread = thread.create_and_start_with_poly_data(&snapshot_worker, concurrent_snapshot_worker_run)
	}
	if snapshot_thread == nil || write_thread == nil {return pbt.error("could not start concurrent snapshot race")}
	thread.join(snapshot_thread)
	thread.join(write_thread)
	thread.destroy(snapshot_thread)
	thread.destroy(write_thread)
	defer vev.close(&snapshot_worker.database)
	defer delete(write_worker.report)
	if !snapshot_worker.ok || !write_worker.committed {
		return pbt.fail(fmt.tprintf("concurrent snapshot operation failed: snapshot=%v writer=%v/%s", snapshot_worker.ok, write_worker.committed, write_worker.report))
	}

	snapshot_basis, snapshot_basis_ok := vev.basis_t(&snapshot_worker.database)
	if !snapshot_basis_ok || (snapshot_basis != 2 && snapshot_basis != 3) {
		return pbt.fail(fmt.tprintf("concurrent snapshot has impossible basis: %d", snapshot_basis))
	}
	pbt.cover(t, snapshot_basis == 2, 0, "concurrent-snapshot-before-write")
	pbt.cover(t, snapshot_basis == 3, 0, "concurrent-snapshot-after-write")
	expected_value := "ada"
	expect_second := false
	if snapshot_basis == 3 {
		expected_value = value
		expect_second = true
	}
	if result := multi_connection_conflict_attr_check(t, &snapshot_worker.database, 1, ":race/value", expected_value, true, "concurrent snapshot"); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, &snapshot_worker.database, 2, ":race/value", value, expect_second, "concurrent snapshot"); result.status != .Pass {
		return result
	}

	vev.close(&reader)
	vev.close(&writer)
	reader, reader_ok = vev.connect(&library, path)
	if !reader_ok {return pbt.error("could not reopen concurrent-snapshot source")}
	final_db, final_db_ok := vev.db(&reader)
	if !final_db_ok {return pbt.error("could not retain reopened concurrent-snapshot source")}
	defer vev.close(&final_db)
	if result := multi_connection_conflict_attr_check(t, &final_db, 1, ":race/value", value, true, "reopened concurrent-snapshot source"); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, &final_db, 2, ":race/value", value, true, "reopened concurrent-snapshot source"); result.status != .Pass {
		return result
	}
	final_basis, final_basis_ok := vev.basis_t(&final_db)
	if !final_basis_ok || final_basis != 3 {return pbt.fail(fmt.tprintf("reopened concurrent-snapshot source basis: %d", final_basis))}
	return multi_connection_conflict_attr_check(t, &snapshot_worker.database, 1, ":race/value", expected_value, true, "concurrent snapshot after reopen")
}

concurrent_snapshot_worker_run :: proc(worker: ^Concurrent_Snapshot_Worker) {
	sync.barrier_wait(worker.barrier)
	worker.database, worker.ok = vev.db(worker.connection)
}

concurrent_snapshot_write_worker_run :: proc(worker: ^Concurrent_Snapshot_Write_Worker) {
	sync.barrier_wait(worker.barrier)
	report, committed := vev.transact(worker.connection, worker.tx)
	worker.committed = committed
	worker.report = strings.clone(report)
	delete(report)
}

concurrent_connection_property :: proc(t: ^pbt.T) -> pbt.Result {
	rounds := pbt.draw(t, pbt.int_range(1, CONCURRENT_CONNECTION_MAX_ROUNDS))
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	left_value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	right_value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	pbt.cover(t, rounds == 1, 10, "concurrent-single-round")
	pbt.cover(t, rounds >= 5, 35, "concurrent-many-rounds")
	pbt.cover(t, resident_mode == 0, 15, "concurrent-source-backed-peers")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-both-resident")
	pbt.cover(t, left_value_index == right_value_index, 15, "concurrent-same-values")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-connection path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not open concurrent-connection seed")}
	seed_report, schema_ok := vev.transact(&seed, CONCURRENT_CONNECTION_SCHEMA, t.value_allocator)
	vev.close(&seed)
	if !schema_ok {return pbt.error(fmt.tprintf("could not install concurrent schema: %s", seed_report))}

	left, left_ok := vev.connect(&library, path)
	if !left_ok {return pbt.error("could not open concurrent left connection")}
	defer vev.close(&left)
	right, right_ok := vev.connect(&library, path)
	if !right_ok {return pbt.error("could not open concurrent right connection")}
	defer vev.close(&right)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&left) {
		return pbt.error("could not make concurrent left connection resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&right) {
		return pbt.error("could not make concurrent right connection resident")
	}

	left_checkpoint, left_checkpoint_ok := vev.db(&left)
	if !left_checkpoint_ok {return pbt.error("could not retain concurrent left checkpoint")}
	defer vev.close(&left_checkpoint)
	right_checkpoint, right_checkpoint_ok := vev.db(&right)
	if !right_checkpoint_ok {return pbt.error("could not retain concurrent right checkpoint")}
	defer vev.close(&right_checkpoint)

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	left_worker := Concurrent_Connection_Worker{
		connection = &left,
		barrier = &barrier,
		rounds = rounds,
		entity_base = 1000,
		value = MODEL_NAMES[left_value_index],
	}
	right_worker := Concurrent_Connection_Worker{
		connection = &right,
		barrier = &barrier,
		rounds = rounds,
		entity_base = 2000,
		value = MODEL_NAMES[right_value_index],
	}
	left_thread := thread.create_and_start_with_poly_data(&left_worker, concurrent_connection_worker_run)
	if left_thread == nil {return pbt.error("could not start concurrent left worker")}
	right_thread := thread.create_and_start_with_poly_data(&right_worker, concurrent_connection_worker_run)
	if right_thread == nil {
		thread.destroy(left_thread)
		return pbt.error("could not start concurrent right worker")
	}
	thread.join(left_thread)
	thread.join(right_thread)
	thread.destroy(left_thread)
	thread.destroy(right_thread)
	defer if len(left_worker.last_error) > 0 {delete(left_worker.last_error)}
	defer if len(right_worker.last_error) > 0 {delete(right_worker.last_error)}
	if left_worker.failures != 0 || right_worker.failures != 0 {
		return pbt.fail(fmt.tprintf(
			"concurrent writers lost commits: rounds=%d resident-mode=%d failures=%d/%d last-basis=%d/%d",
			rounds,
			resident_mode,
			left_worker.failures,
			right_worker.failures,
			left_worker.last_basis,
			right_worker.last_basis,
		))
	}

	expected_basis := u64(1 + rounds * 2)
	if result := multi_connection_metadata_check(t, &left, &right, expected_basis, "after concurrent writers"); result.status != .Pass {
		return result
	}
	if result := concurrent_connection_checkpoint_check(t, &left_checkpoint, rounds, 1000, "left retained checkpoint"); result.status != .Pass {
		return result
	}
	if result := concurrent_connection_checkpoint_check(t, &right_checkpoint, rounds, 2000, "right retained checkpoint"); result.status != .Pass {
		return result
	}

	vev.close(&left)
	vev.close(&right)
	left, left_ok = vev.connect(&library, path)
	right, right_ok = vev.connect(&library, path)
	if !left_ok || !right_ok {return pbt.error("could not reopen concurrent connections")}
	connections := [?]^vev.Durable_Connection{&left, &right}
	for connection, connection_index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened concurrent database")}
		result := concurrent_connection_final_check(
			t,
			&database,
			rounds,
			MODEL_NAMES[left_value_index],
			MODEL_NAMES[right_value_index],
			expected_basis,
			fmt.tprintf("reopened concurrent connection %d", connection_index),
		)
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	left_log, left_log_ok := index_maintenance_log_edn(t, &left)
	right_log, right_log_ok := index_maintenance_log_edn(t, &right)
	if !left_log_ok || !right_log_ok || left_log != right_log {
		return pbt.fail("concurrent writers produced divergent reopened transaction logs")
	}
	return pbt.pass()
}

concurrent_connection_worker_run :: proc(worker: ^Concurrent_Connection_Worker) {
	for round in 0 ..< worker.rounds {
		sync.barrier_wait(worker.barrier)
		tx := fmt.tprintf(
			`[[:db/add %d :race/value "%s"]]`,
			worker.entity_base + round,
			worker.value,
		)
		report, ok := vev.transact(worker.connection, tx)
		if !ok {
			worker.failures += 1
			if len(worker.last_error) > 0 {delete(worker.last_error)}
			worker.last_error = strings.clone(report)
			if strings.contains(report, "basis changed") {
				worker.basis_conflicts += 1
			} else {
				worker.other_failures += 1
			}
		} else {
			basis, basis_ok := vev.connection_basis_t(worker.connection)
			if !basis_ok || basis <= worker.last_basis {
				worker.failures += 1
			} else {
				worker.last_basis = basis
			}
		}
		delete(report)
		sync.barrier_wait(worker.barrier)
	}
}

concurrent_maintenance_property :: proc(t: ^pbt.T) -> pbt.Result {
	rounds := pbt.draw(t, pbt.int_range(2, CONCURRENT_CONNECTION_MAX_ROUNDS))
	steps := pbt.draw(t, pbt.int_range(0, 4))
	compact_first := pbt.draw(t, pbt.boolean())
	writer_resident := pbt.draw(t, pbt.boolean())
	maintenance_resident := pbt.draw(t, pbt.boolean())
	value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	pbt.cover(t, rounds >= 5, 45, "concurrent-maintenance-many-rounds")
	pbt.cover(t, steps == 0, 10, "concurrent-maintenance-zero-budget")
	pbt.cover(t, steps > 0, 60, "concurrent-maintenance-positive-budget")
	pbt.cover(t, compact_first, 35, "concurrent-maintenance-compact-first")
	pbt.cover(t, writer_resident, 35, "concurrent-maintenance-resident-writer")
	pbt.cover(t, maintenance_resident, 35, "concurrent-maintenance-resident-peer")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-maintenance path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not open concurrent-maintenance seed")}
	seed_report, schema_ok := vev.transact(&seed, CONCURRENT_CONNECTION_SCHEMA, t.value_allocator)
	vev.close(&seed)
	if !schema_ok {return pbt.error(fmt.tprintf("could not install concurrent-maintenance schema: %s", seed_report))}

	writer, writer_ok := vev.connect(&library, path)
	if !writer_ok {return pbt.error("could not open concurrent-maintenance writer")}
	defer vev.close(&writer)
	maintenance, maintenance_ok := vev.connect(&library, path)
	if !maintenance_ok {return pbt.error("could not open concurrent-maintenance peer")}
	defer vev.close(&maintenance)
	if writer_resident && !vev.ensure_resident(&writer) {
		return pbt.error("could not make maintenance-race writer resident")
	}
	if maintenance_resident && !vev.ensure_resident(&maintenance) {
		return pbt.error("could not make maintenance-race peer resident")
	}
	checkpoint, checkpoint_ok := vev.db(&maintenance)
	if !checkpoint_ok {return pbt.error("could not retain maintenance-race checkpoint")}
	defer vev.close(&checkpoint)

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	write_worker := Concurrent_Connection_Worker{
		connection = &writer,
		barrier = &barrier,
		rounds = rounds,
		entity_base = 1000,
		value = MODEL_NAMES[value_index],
	}
	maintenance_worker := Concurrent_Maintenance_Worker{
		connection = &maintenance,
		barrier = &barrier,
		rounds = rounds,
		steps = steps,
		compact_first = compact_first,
	}
	write_thread := thread.create_and_start_with_poly_data(&write_worker, concurrent_connection_worker_run)
	if write_thread == nil {return pbt.error("could not start maintenance-race writer")}
	maintenance_thread := thread.create_and_start_with_poly_data(&maintenance_worker, concurrent_maintenance_worker_run)
	if maintenance_thread == nil {
		thread.destroy(write_thread)
		return pbt.error("could not start concurrent maintenance worker")
	}
	thread.join(write_thread)
	thread.join(maintenance_thread)
	thread.destroy(write_thread)
	thread.destroy(maintenance_thread)
	defer if len(write_worker.last_error) > 0 {delete(write_worker.last_error)}
	if write_worker.failures != 0 || maintenance_worker.failures != 0 {
		return pbt.fail(fmt.tprintf(
			"writer/maintenance race failed: rounds=%d steps=%d resident=%v/%v failures=%d/%d writer-basis=%d writer-other=%d error=%s",
			rounds,
			steps,
			writer_resident,
			maintenance_resident,
			write_worker.failures,
			maintenance_worker.failures,
			write_worker.basis_conflicts,
			write_worker.other_failures,
			write_worker.last_error,
		))
	}
	expected_basis := u64(rounds + 1)
	if result := multi_connection_metadata_check(t, &writer, &maintenance, expected_basis, "after concurrent maintenance"); result.status != .Pass {
		return result
	}
	if result := concurrent_connection_checkpoint_check(t, &checkpoint, rounds, 1000, "maintenance-race checkpoint"); result.status != .Pass {
		return result
	}

	vev.close(&writer)
	vev.close(&maintenance)
	writer, writer_ok = vev.connect(&library, path)
	maintenance, maintenance_ok = vev.connect(&library, path)
	if !writer_ok || !maintenance_ok {return pbt.error("could not reopen maintenance-race connections")}
	connections := [?]^vev.Durable_Connection{&writer, &maintenance}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened maintenance-race database")}
		result := concurrent_maintenance_final_check(
			t,
			&database,
			rounds,
			MODEL_NAMES[value_index],
			expected_basis,
			fmt.tprintf("reopened maintenance-race connection %d", index),
		)
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	writer_log, writer_log_ok := index_maintenance_log_edn(t, &writer)
	maintenance_log, maintenance_log_ok := index_maintenance_log_edn(t, &maintenance)
	if !writer_log_ok || !maintenance_log_ok || writer_log != maintenance_log {
		return pbt.fail("concurrent maintenance changed the logical transaction log")
	}
	return concurrent_connection_checkpoint_check(t, &checkpoint, rounds, 1000, "maintenance checkpoint after reopen")
}

concurrent_maintenance_worker_run :: proc(worker: ^Concurrent_Maintenance_Worker) {
	for round in 0 ..< worker.rounds {
		sync.barrier_wait(worker.barrier)
		compact := (round % 2 == 0) == worker.compact_first
		ok := false
		if compact {
			ok = vev.compact_indexes(worker.connection)
		} else {
			ok = vev.maintain_indexes(worker.connection, worker.steps)
		}
		if !ok {worker.failures += 1}
		sync.barrier_wait(worker.barrier)
	}
}

concurrent_maintenance_final_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	rounds: int,
	expected_value: string,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != expected_basis {
		return pbt.fail(fmt.tprintf("%s basis: expected=%d actual=%d", label, expected_basis, basis))
	}
	for round in 0 ..< rounds {
		actual := query_name_attr(t, database, u64(1000 + round), ":race/value")
		if !actual.ok {return pbt.error(fmt.tprintf("%s query failed at round %d", label, round))}
		if !actual.found || actual.name != expected_value {
			return pbt.fail(fmt.tprintf("%s lost round %d: found=%v value=%q", label, round, actual.found, actual.name))
		}
	}
	return pbt.pass()
}

concurrent_connection_checkpoint_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	rounds, entity_base: int,
	label: string,
) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 1 {return pbt.fail(fmt.tprintf("%s basis changed: %d", label, basis))}
	for round in 0 ..< rounds {
		actual := query_name_attr(t, database, u64(entity_base + round), ":race/value")
		if !actual.ok {return pbt.error(fmt.tprintf("%s query failed", label))}
		if actual.found {return pbt.fail(fmt.tprintf("%s observed later entity %d", label, entity_base + round))}
	}
	return pbt.pass()
}

concurrent_connection_final_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	rounds: int,
	left_value, right_value: string,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != expected_basis {
		return pbt.fail(fmt.tprintf("%s basis: expected=%d actual=%d", label, expected_basis, basis))
	}
	for round in 0 ..< rounds {
		left_actual := query_name_attr(t, database, u64(1000 + round), ":race/value")
		right_actual := query_name_attr(t, database, u64(2000 + round), ":race/value")
		if !left_actual.ok || !right_actual.ok {
			return pbt.error(fmt.tprintf("%s race query failed at round %d", label, round))
		}
		if !left_actual.found || left_actual.name != left_value ||
		   !right_actual.found || right_actual.name != right_value {
			return pbt.fail(fmt.tprintf(
				"%s lost round %d: left=%v/%q right=%v/%q",
				label,
				round,
				left_actual.found,
				left_actual.name,
				right_actual.found,
				right_actual.name,
			))
		}
	}
	return pbt.pass()
}
