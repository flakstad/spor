package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

MULTI_CONNECTION_ENTITY_COUNT :: 4
MULTI_CONNECTION_VALUE_COUNT :: 4
MULTI_CONNECTION_MAX_STEPS :: 12

MULTI_CONNECTION_VALUES := [?]string{"ada", "grace", "barbara", "hedy"}
MULTI_CONNECTION_TAGS := [?]string{"core", "stateful", "transaction", "durable", "multi-connection", "snapshot", "log", "reopen", "model"}

MULTI_CONNECTION_SCHEMA :: `[
	{:db/id 100 :db/ident :shared/value :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Multi_Connection_Command :: struct {
	writes_right: bool,
	retracts:     bool,
	entity:       int,
	value_index:  int,
}

multi_connection_property :: proc(t: ^pbt.T) -> pbt.Result {
	step_count := pbt.draw(t, pbt.int_range(3, MULTI_CONNECTION_MAX_STEPS))
	checkpoint_step := pbt.draw(t, pbt.int_range(1, step_count - 1))
	reopen_step := pbt.draw(t, pbt.int_range(1, step_count))
	reopen_right := pbt.draw(t, pbt.boolean())
	resident_right := pbt.draw(t, pbt.boolean())
	compact_at_end := pbt.draw(t, pbt.boolean())
	commands: [MULTI_CONNECTION_MAX_STEPS]Multi_Connection_Command
	wrote_left, wrote_right, switched_writer, same_entity_conflict := false, false, false, false
	for index in 0 ..< step_count {
		commands[index] = Multi_Connection_Command{
			writes_right = pbt.draw(t, pbt.boolean()),
			retracts = pbt.draw(t, pbt.int_range(0, 3)) == 0,
			entity = pbt.draw(t, pbt.int_range(1, MULTI_CONNECTION_ENTITY_COUNT)),
			value_index = pbt.draw(t, pbt.int_range(0, MULTI_CONNECTION_VALUE_COUNT - 1)),
		}
		wrote_right = wrote_right || commands[index].writes_right
		wrote_left = wrote_left || !commands[index].writes_right
		if index > 0 {
			switched_writer = switched_writer || commands[index].writes_right != commands[index - 1].writes_right
			same_entity_conflict = same_entity_conflict ||
				(commands[index].entity == commands[index - 1].entity &&
				 commands[index].writes_right != commands[index - 1].writes_right)
		}
	}
	pbt.cover(t, wrote_left && wrote_right, 60, "multi-connection-both-writers")
	pbt.cover(t, switched_writer, 55, "multi-connection-writer-switch")
	pbt.cover(t, same_entity_conflict, 10, "multi-connection-same-entity-handoff")
	pbt.cover(t, resident_right, 35, "multi-connection-resident-peer")
	pbt.cover(t, compact_at_end, 35, "multi-connection-compaction")
	pbt.cover(t, reopen_right, 35, "multi-connection-reopen-right")
	pbt.cover(t, !reopen_right, 35, "multi-connection-reopen-left")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate multi-connection path")}
	defer transaction_model_remove_store(path)
	left, left_ok := vev.connect(&library, path)
	if !left_ok {return pbt.error("could not open left durable connection")}
	defer vev.close(&left)
	right, right_ok := vev.connect(&library, path)
	if !right_ok {return pbt.error("could not open right durable connection")}
	defer vev.close(&right)

	// Install the schema only through left. Right deliberately remains open on
	// the empty generation so its first operation must notice an external commit.
	schema_report, schema_ok := vev.transact(&left, MULTI_CONNECTION_SCHEMA, t.value_allocator)
	if !schema_ok || !strings.contains(schema_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not install multi-connection schema: %s", schema_report))
	}
	model: [MULTI_CONNECTION_ENTITY_COUNT]int
	if result := multi_connection_live_check(t, &left, &right, model, 1, "after external schema"); result.status != .Pass {
		return result
	}
	if resident_right && !vev.ensure_resident(&right) {
		return pbt.fail("right connection could not enter resident mode")
	}

	checkpoint: vev.DB
	checkpoint_open := false
	checkpoint_model: [MULTI_CONNECTION_ENTITY_COUNT]int
	checkpoint_basis := u64(0)
	defer if checkpoint_open {vev.close(&checkpoint)}

	for command, index in commands[:step_count] {
		writer := &left
		writer_name := "left"
		if command.writes_right {
			writer = &right
			writer_name = "right"
		}
		tx := fmt.tprintf(
			`[[:db/add %d :shared/value "%s"]]`,
			command.entity,
			MULTI_CONNECTION_VALUES[command.value_index],
		)
		if command.retracts {
			tx = fmt.tprintf(`[[:db/retract %d :shared/value]]`, command.entity)
		}
		report, ok := vev.transact(writer, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			return pbt.fail(fmt.tprintf(
				"%s stale-generation transaction failed at step %d: tx=%s report=%s",
				writer_name,
				index + 1,
				tx,
				report,
			))
		}
		if command.retracts {
			model[command.entity - 1] = 0
		} else {
			model[command.entity - 1] = command.value_index + 1
		}
		expected_basis := u64(index + 2)
		if result := multi_connection_writer_check(
			t,
			&left,
			&right,
			writer,
			model,
			expected_basis,
			fmt.tprintf("after %s step %d", writer_name, index + 1),
		); result.status != .Pass {
			return result
		}

		if index + 1 == checkpoint_step {
			checkpoint_model = model
			checkpoint_basis = expected_basis
			checkpoint, checkpoint_open = vev.db(writer)
			if !checkpoint_open {return pbt.error("could not retain shared-history checkpoint")}
		}
		if checkpoint_open {
			if result := multi_connection_database_check(t, &checkpoint, checkpoint_model, checkpoint_basis, "held checkpoint"); result.status != .Pass {
				return result
			}
		}

		if index + 1 == reopen_step {
			if reopen_right {
				vev.close(&right)
				right, right_ok = vev.connect(&library, path)
				if !right_ok {return pbt.error("could not reopen right connection mid-history")}
			} else {
				vev.close(&left)
				left, left_ok = vev.connect(&library, path)
				if !left_ok {return pbt.error("could not reopen left connection mid-history")}
			}
			reopened := &left
			if reopen_right {reopened = &right}
			if result := multi_connection_writer_check(t, &left, &right, reopened, model, expected_basis, "after mid-history reopen"); result.status != .Pass {
				return result
			}
		}
	}

	if compact_at_end {
		maintenance := &left
		peer := &right
		if reopen_right {
			maintenance = &right
			peer = &left
		}
		if !vev.compact_indexes(maintenance) || !vev.ensure_resident(peer) {
			return pbt.fail("shared-history maintenance failed")
		}
	}
	final_basis := u64(step_count + 1)
	last_writer := &left
	if commands[step_count - 1].writes_right {last_writer = &right}
	if result := multi_connection_writer_check(t, &left, &right, last_writer, model, final_basis, "final live"); result.status != .Pass {
		return result
	}

	vev.close(&left)
	vev.close(&right)
	left, left_ok = vev.connect(&library, path)
	right, right_ok = vev.connect(&library, path)
	if !left_ok || !right_ok {return pbt.error("could not reopen both final connections")}
	if result := multi_connection_live_check(t, &left, &right, model, final_basis, "final reopened"); result.status != .Pass {
		return result
	}
	left_log, left_log_ok := index_maintenance_log_edn(t, &left)
	right_log, right_log_ok := index_maintenance_log_edn(t, &right)
	if !left_log_ok || !right_log_ok || left_log != right_log {
		return pbt.fail("reopened connections disagree on exact transaction log")
	}
	return multi_connection_database_check(t, &checkpoint, checkpoint_model, checkpoint_basis, "checkpoint after final reopen")
}

multi_connection_writer_check :: proc(
	t: ^pbt.T,
	left, right, writer: ^vev.Durable_Connection,
	expected: [MULTI_CONNECTION_ENTITY_COUNT]int,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	if result := multi_connection_metadata_check(t, left, right, expected_basis, label); result.status != .Pass {
		return result
	}
	writer_basis, writer_basis_ok := vev.connection_basis_t(writer)
	if !writer_basis_ok || writer_basis != vev.t_to_tx(expected_basis) {
		return pbt.fail(fmt.tprintf(
			"%s writer basis: expected=%d actual=%d ok=%v",
			label,
			vev.t_to_tx(expected_basis),
			writer_basis,
			writer_basis_ok,
		))
	}
	database, database_ok := vev.db(writer)
	if !database_ok {return pbt.error(fmt.tprintf("could not retain %s writer database", label))}
	defer vev.close(&database)
	return multi_connection_database_check(t, &database, expected, expected_basis, fmt.tprintf("%s writer", label))
}

multi_connection_metadata_check :: proc(
	t: ^pbt.T,
	left, right: ^vev.Durable_Connection,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	left_count, left_count_ok := vev.connection_tx_count(left)
	right_count, right_count_ok := vev.connection_tx_count(right)
	left_ids, left_ids_ok := vev.connection_tx_ids(left, t.value_allocator)
	right_ids, right_ids_ok := vev.connection_tx_ids(right, t.value_allocator)
	if !left_count_ok || !right_count_ok || !left_ids_ok || !right_ids_ok {
		return pbt.error(fmt.tprintf("could not inspect %s shared metadata", label))
	}
	if left_count != expected_basis || right_count != expected_basis ||
	   !backup_tx_ids_equal(left_ids[:], right_ids[:]) || len(left_ids) != int(expected_basis) {
		return pbt.fail(fmt.tprintf(
			"%s metadata disagree: expected=%d count=%d/%d ids=%v/%v",
			label,
			expected_basis,
			left_count,
			right_count,
			left_ids,
			right_ids,
		))
	}
	return pbt.pass()
}

multi_connection_live_check :: proc(
	t: ^pbt.T,
	left, right: ^vev.Durable_Connection,
	expected: [MULTI_CONNECTION_ENTITY_COUNT]int,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	if result := multi_connection_metadata_check(t, left, right, expected_basis, label); result.status != .Pass {
		return result
	}
	left_basis, left_basis_ok := vev.connection_basis_t(left)
	right_basis, right_basis_ok := vev.connection_basis_t(right)
	if !left_basis_ok || !right_basis_ok {
		return pbt.error(fmt.tprintf("could not inspect %s shared coordinates", label))
	}
	if left_basis != vev.t_to_tx(expected_basis) || right_basis != vev.t_to_tx(expected_basis) {
		return pbt.fail(fmt.tprintf(
			"%s connections disagree: expected=%d basis=%d/%d",
			label,
			vev.t_to_tx(expected_basis),
			left_basis,
			right_basis,
		))
	}
	left_db, left_ok := vev.db(left)
	if !left_ok {return pbt.error(fmt.tprintf("could not retain %s left database", label))}
	defer vev.close(&left_db)
	right_db, right_ok := vev.db(right)
	if !right_ok {return pbt.error(fmt.tprintf("could not retain %s right database", label))}
	defer vev.close(&right_db)
	if result := multi_connection_database_check(t, &left_db, expected, expected_basis, fmt.tprintf("%s left", label)); result.status != .Pass {
		return result
	}
	return multi_connection_database_check(t, &right_db, expected, expected_basis, fmt.tprintf("%s right", label))
}

multi_connection_database_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	expected: [MULTI_CONNECTION_ENTITY_COUNT]int,
	expected_basis: u64,
	label: string,
) -> pbt.Result {
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != expected_basis {
		return pbt.fail(fmt.tprintf("%s basis: expected=%d actual=%d ok=%v", label, expected_basis, basis, basis_ok))
	}
	for expected_value, entity_index in expected {
		actual := query_name_attr(t, database, u64(entity_index + 1), ":shared/value")
		if !actual.ok {return pbt.error(fmt.tprintf("%s entity %d query failed", label, entity_index + 1))}
		if expected_value == 0 {
			if actual.found {return pbt.fail(fmt.tprintf("%s entity %d expected nil, found %q", label, entity_index + 1, actual.name))}
		} else if !actual.found || actual.name != MULTI_CONNECTION_VALUES[expected_value - 1] {
			return pbt.fail(fmt.tprintf(
				"%s entity %d expected %q, found=%v value=%q",
				label,
				entity_index + 1,
				MULTI_CONNECTION_VALUES[expected_value - 1],
				actual.found,
				actual.name,
			))
		}
	}
	return pbt.pass()
}
