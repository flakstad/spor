package main

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CONCURRENT_CONFLICT_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "cas", "unique", "atomic", "failure", "linearizable", "snapshot", "log", "reopen", "model"}

Concurrent_Conflict_Kind :: enum {
	CAS,
	Unique,
	Replace,
}

Concurrent_Conflict_Worker :: struct {
	connection: ^vev.Durable_Connection,
	barrier:    ^sync.Barrier,
	tx:         string,
	report:     string,
	committed:  bool,
}

concurrent_conflict_property :: proc(t: ^pbt.T) -> pbt.Result {
	kind := Concurrent_Conflict_Kind(pbt.draw(t, pbt.int_range(0, 2)))
	resident_mode := pbt.draw(t, pbt.int_range(0, 3))
	left_value_index := pbt.draw(t, pbt.int_range(1, MODEL_VALUE_COUNT - 1))
	right_offset := pbt.draw(t, pbt.int_range(1, MODEL_VALUE_COUNT - 2))
	right_value_index := 1 + ((left_value_index - 1 + right_offset) % (MODEL_VALUE_COUNT - 1))
	pbt.cover(t, kind == .CAS, 20, "concurrent-conflict-cas")
	pbt.cover(t, kind == .Unique, 20, "concurrent-conflict-unique")
	pbt.cover(t, kind == .Replace, 20, "concurrent-conflict-replace")
	pbt.cover(t, resident_mode == 0, 15, "concurrent-conflict-source-backed")
	pbt.cover(t, resident_mode == 1, 15, "concurrent-conflict-left-resident")
	pbt.cover(t, resident_mode == 2, 15, "concurrent-conflict-right-resident")
	pbt.cover(t, resident_mode == 3, 15, "concurrent-conflict-both-resident")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate concurrent-conflict path")}
	defer transaction_model_remove_store(path)
	seed, seed_ok := vev.connect(&library, path)
	if !seed_ok {return pbt.error("could not open concurrent-conflict seed")}
	setup := [?]string{
		MULTI_CONNECTION_CONFLICT_SCHEMA,
		`[{:db/id 1 :conflict/name "ada"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(&seed, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			vev.close(&seed)
			return pbt.error(fmt.tprintf("could not initialize concurrent conflict: %s", report))
		}
	}
	vev.close(&seed)

	left, left_ok := vev.connect(&library, path)
	if !left_ok {return pbt.error("could not open concurrent-conflict left connection")}
	defer vev.close(&left)
	right, right_ok := vev.connect(&library, path)
	if !right_ok {return pbt.error("could not open concurrent-conflict right connection")}
	defer vev.close(&right)
	if (resident_mode == 1 || resident_mode == 3) && !vev.ensure_resident(&left) {
		return pbt.error("could not make concurrent-conflict left connection resident")
	}
	if (resident_mode == 2 || resident_mode == 3) && !vev.ensure_resident(&right) {
		return pbt.error("could not make concurrent-conflict right connection resident")
	}
	checkpoint, checkpoint_ok := vev.db(&left)
	if !checkpoint_ok {return pbt.error("could not retain concurrent-conflict checkpoint")}
	defer vev.close(&checkpoint)

	left_tx := concurrent_conflict_tx(kind, true, MODEL_NAMES[left_value_index])
	right_tx := concurrent_conflict_tx(kind, false, MODEL_NAMES[right_value_index])
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	left_worker := Concurrent_Conflict_Worker{connection = &left, barrier = &barrier, tx = left_tx}
	right_worker := Concurrent_Conflict_Worker{connection = &right, barrier = &barrier, tx = right_tx}
	left_thread := thread.create_and_start_with_poly_data(&left_worker, concurrent_conflict_worker_run)
	if left_thread == nil {return pbt.error("could not start concurrent-conflict left worker")}
	right_thread := thread.create_and_start_with_poly_data(&right_worker, concurrent_conflict_worker_run)
	if right_thread == nil {
		thread.destroy(left_thread)
		return pbt.error("could not start concurrent-conflict right worker")
	}
	thread.join(left_thread)
	thread.join(right_thread)
	thread.destroy(left_thread)
	thread.destroy(right_thread)
	defer delete(left_worker.report)
	defer delete(right_worker.report)

	commit_count := int(left_worker.committed) + int(right_worker.committed)
	expected_commits := 1
	if kind == .Replace {expected_commits = 2}
	if commit_count != expected_commits {
		return pbt.fail(fmt.tprintf(
			"concurrent conflict was not linearizable: kind=%v resident=%d committed=%v/%v reports=%s / %s",
			kind,
			resident_mode,
			left_worker.committed,
			right_worker.committed,
			left_worker.report,
			right_worker.report,
		))
	}
	if kind != .Replace {
		loser_report := right_worker.report
		if !left_worker.committed {loser_report = left_worker.report}
		expected_error := ":db.fn/cas failed"
		if kind == .Unique {expected_error = "schema unique conflict"}
		if !strings.contains(loser_report, ":ok false") || !strings.contains(loser_report, expected_error) {
			return pbt.fail(fmt.tprintf("concurrent conflict loser returned wrong error: expected=%q report=%s", expected_error, loser_report))
		}
	}

	expected_basis := u64(2 + expected_commits)
	if result := multi_connection_metadata_check(t, &left, &right, expected_basis, "after concurrent conflict"); result.status != .Pass {
		return result
	}
	if result := concurrent_conflict_checkpoint_check(t, &checkpoint); result.status != .Pass {
		return result
	}

	vev.close(&left)
	vev.close(&right)
	left, left_ok = vev.connect(&library, path)
	right, right_ok = vev.connect(&library, path)
	if !left_ok || !right_ok {return pbt.error("could not reopen concurrent-conflict connections")}
	connections := [?]^vev.Durable_Connection{&left, &right}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened concurrent-conflict database")}
		result := concurrent_conflict_final_check(
			t,
			&database,
			kind,
			left_worker.committed,
			right_worker.committed,
			MODEL_NAMES[left_value_index],
			MODEL_NAMES[right_value_index],
			expected_basis,
			fmt.tprintf("reopened concurrent conflict %d", index),
		)
		vev.close(&database)
		if result.status != .Pass {return result}
	}
	left_log, left_log_ok := index_maintenance_log_edn(t, &left)
	right_log, right_log_ok := index_maintenance_log_edn(t, &right)
	if !left_log_ok || !right_log_ok || left_log != right_log {
		return pbt.fail("concurrent conflicts produced divergent transaction logs")
	}
	return concurrent_conflict_checkpoint_check(t, &checkpoint)
}

concurrent_conflict_worker_run :: proc(worker: ^Concurrent_Conflict_Worker) {
	sync.barrier_wait(worker.barrier)
	report, committed := vev.transact(worker.connection, worker.tx)
	worker.report = strings.clone(report)
	worker.committed = committed
	delete(report)
}

concurrent_conflict_tx :: proc(kind: Concurrent_Conflict_Kind, left: bool, value: string) -> string {
	marker_entity := 3
	if left {marker_entity = 2}
	marker := fmt.tprintf(`[:db/add %d :conflict/marker "%s"]`, marker_entity, value)
	if kind == .CAS {
		return fmt.tprintf(`[%s [:db.fn/cas 1 :conflict/name "ada" "%s"]]`, marker, value)
	}
	if kind == .Unique {
		return fmt.tprintf(`[%s [:db/add %d :conflict/email "shared@example.test"]]`, marker, marker_entity)
	}
	return fmt.tprintf(`[%s [:db/add 1 :conflict/name "%s"]]`, marker, value)
}

concurrent_conflict_checkpoint_check :: proc(t: ^pbt.T, database: ^vev.DB) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != 2 {return pbt.fail(fmt.tprintf("concurrent-conflict checkpoint basis changed: %d", basis))}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":conflict/name", "ada", true, "concurrent-conflict checkpoint"); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, database, 2, ":conflict/marker", "", false, "concurrent-conflict checkpoint"); result.status != .Pass {
		return result
	}
	return multi_connection_conflict_attr_check(t, database, 3, ":conflict/marker", "", false, "concurrent-conflict checkpoint")
}

concurrent_conflict_final_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	kind: Concurrent_Conflict_Kind,
	left_committed, right_committed: bool,
	left_value, right_value: string,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != expected_basis {
		return pbt.fail(fmt.tprintf("%s basis: expected=%d actual=%d", label, expected_basis, basis))
	}
	expected_name := "ada"
	if kind == .CAS {
		if left_committed {expected_name = left_value} else {expected_name = right_value}
	} else if kind == .Replace {
		actual := query_name_attr(t, database, 1, ":conflict/name")
		if !actual.ok {return pbt.error(fmt.tprintf("%s could not query replacement winner", label))}
		if !actual.found || (actual.name != left_value && actual.name != right_value) {
			return pbt.fail(fmt.tprintf("%s replacement has impossible winner: %v/%q", label, actual.found, actual.name))
		}
		expected_name = actual.name
	}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":conflict/name", expected_name, true, label); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, database, 2, ":conflict/marker", left_value, left_committed, label); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, database, 3, ":conflict/marker", right_value, right_committed, label); result.status != .Pass {
		return result
	}
	if kind == .Unique {
		if result := multi_connection_conflict_attr_check(t, database, 2, ":conflict/email", "shared@example.test", left_committed, label); result.status != .Pass {
			return result
		}
		return multi_connection_conflict_attr_check(t, database, 3, ":conflict/email", "shared@example.test", right_committed, label)
	}
	return pbt.pass()
}
