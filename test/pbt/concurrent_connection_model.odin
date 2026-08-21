// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:sync"
import "core:thread"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CONCURRENT_CONNECTION_MAX_ROUNDS :: 8
CONCURRENT_CONNECTION_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "concurrent", "race", "resident", "snapshot", "log", "reopen", "model"}

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
	last_basis: u64,
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
		_, ok := vev.transact(worker.connection, tx)
		if !ok {
			worker.failures += 1
		} else {
			basis, basis_ok := vev.connection_basis_t(worker.connection)
			if !basis_ok || basis <= worker.last_basis {
				worker.failures += 1
			} else {
				worker.last_basis = basis
			}
		}
		sync.barrier_wait(worker.barrier)
	}
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
