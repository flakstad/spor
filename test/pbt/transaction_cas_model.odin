// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CAS_MODEL_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "cas", "atomic", "failure", "log"}

Cas_Command :: struct {
	entity:            int,
	expected_name:     int,
	replacement_name:  int,
}

Cas_Observation :: struct {
	resident_call_ok:       bool,
	resident_committed:     bool,
	resident_report:        string,
	durable_committed:      bool,
	durable_report:         string,
	resident_basis_before:  u64,
	resident_basis_after:   u64,
	durable_basis_before:   u64,
	durable_basis_after:    u64,
	durable_count_before:   u64,
	durable_count_after:    u64,
	coordinates_ok:         bool,
}

transaction_cas_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx := Model_Context{compare_durable = true, reopen_durable = true, track_log = true}
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create CAS-model resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate CAS-model durable store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open CAS-model durable connection: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	resident_schema, resident_schema_ok := vev.transact(&ctx.connection, MODEL_SCHEMA, t.value_allocator)
	if !resident_schema_ok || !strings.contains(resident_schema, ":ok true") {
		return pbt.error(fmt.tprintf("could not install resident CAS schema: %s", resident_schema))
	}
	durable_schema, durable_schema_ok := vev.transact(&ctx.durable, MODEL_SCHEMA, t.value_allocator)
	if !durable_schema_ok {
		return pbt.error(fmt.tprintf("could not install durable CAS schema: %s", durable_schema))
	}

	resident_schema_basis, resident_basis_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_schema_basis, durable_basis_ok := transaction_cas_durable_basis(&ctx.durable)
	if !resident_basis_ok || !durable_basis_ok || resident_schema_basis != durable_schema_basis {
		return pbt.error("could not establish a shared CAS schema basis")
	}

	model := pbt.State_Model(Model_State, Cas_Command, Cas_Observation){
		target = &ctx,
		initial = transaction_model_initial,
		command = transaction_cas_command,
		run = transaction_cas_run,
		next_state = transaction_cas_next_state,
		postcondition = transaction_cas_postcondition,
		invariant = transaction_model_invariant,
		command_name = transaction_cas_command_name,
		state_detail = transaction_model_state_detail,
		value_detail = transaction_cas_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 1,
		max_len = MODEL_TRANSACTION_COUNT,
		max_success_events = MODEL_TRANSACTION_COUNT,
		compact_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.connection, resident_schema_basis, "resident CAS"); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_schema_basis, "durable CAS"); result.status != .Pass {
		return result
	}
	if result := transaction_model_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_schema_basis, "durable reopened CAS")
}

transaction_cas_command :: proc(t: ^pbt.T, state: Model_State) -> Cas_Command {
	entity := pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT))
	current := state.names[entity - 1]
	matching := pbt.draw(t, pbt.int_range(0, 3)) != 0
	expected := current
	if !matching {
		expected = (current + 1) % (MODEL_VALUE_COUNT + 1)
	}
	replacement := pbt.draw(t, pbt.int_range(1, MODEL_VALUE_COUNT))
	pbt.classify(t, matching, "cas-match")
	pbt.classify(t, !matching, "cas-stale")
	pbt.classify(t, current == 0, "cas-absent")
	pbt.classify(t, current != 0, "cas-present")
	pbt.classify(t, matching && replacement == current, "cas-same-value")
	return Cas_Command{
		entity = entity,
		expected_name = expected,
		replacement_name = replacement,
	}
}

transaction_cas_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Model_State,
	command: Cas_Command,
) -> Cas_Observation {
	ctx := cast(^Model_Context)target
	resident_before, resident_before_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_before, durable_before_ok := transaction_cas_durable_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	tx := transaction_cas_edn(command)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_after, resident_after_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_after, durable_after_ok := transaction_cas_durable_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	pbt.note(t, fmt.tprintf(
		"cas=%s resident=%s durable=%s",
		tx,
		resident_report,
		durable_report,
	))
	return Cas_Observation{
		resident_call_ok = resident_call_ok,
		resident_committed = resident_committed,
		resident_report = resident_report,
		durable_committed = durable_committed,
		durable_report = durable_report,
		resident_basis_before = resident_before,
		resident_basis_after = resident_after,
		durable_basis_before = durable_before,
		durable_basis_after = durable_after,
		durable_count_before = count_before,
		durable_count_after = count_after,
		coordinates_ok = resident_before_ok && resident_after_ok && durable_before_ok &&
		                 durable_after_ok && count_before_ok && count_after_ok,
	}
}

transaction_cas_resident_basis :: proc(connection: ^vev.Connection) -> (basis: u64, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return 0, false
	}
	defer vev.close(&database)
	return vev.basis_t(&database)
}

transaction_cas_durable_basis :: proc(connection: ^vev.Durable_Connection) -> (basis: u64, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return 0, false
	}
	defer vev.close(&database)
	return vev.basis_t(&database)
}

transaction_cas_edn :: proc(command: Cas_Command) -> string {
	expected := "nil"
	if command.expected_name != 0 {
		expected = fmt.tprintf(`"%s"`, MODEL_NAMES[command.expected_name - 1])
	}
	return fmt.tprintf(
		`[[:db.fn/cas %d :item/name %s "%s"]]`,
		command.entity,
		expected,
		MODEL_NAMES[command.replacement_name - 1],
	)
}

transaction_cas_next_state :: proc(
	state: Model_State,
	command: Cas_Command,
	observation: Cas_Observation,
) -> Model_State {
	if !observation.resident_committed || !observation.durable_committed {
		return state
	}
	next := state
	next.names[command.entity - 1] = command.replacement_name
	next.ctx.final_names = next.names
	transaction_model_record_transaction(next.ctx, observation.resident_basis_after)
	transaction_batch_record_log_diff(next.ctx, state, next, observation.resident_basis_after)
	return next
}

transaction_cas_postcondition :: proc(
	state: Model_State,
	command: Cas_Command,
	observation: Cas_Observation,
) -> pbt.Result {
	expected_commit := state.names[command.entity - 1] == command.expected_name
	return transaction_conditional_result(observation, expected_commit, "CAS")
}

transaction_conditional_result :: proc(
	observation: Cas_Observation,
	expected_commit: bool,
	operation: string,
) -> pbt.Result {
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident %s API call did not return a report", operation))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("could not read %s transaction coordinates", operation))
	}
	if observation.resident_committed != expected_commit ||
	   observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"%s commit mismatch: expected=%v resident=%v durable=%v",
			operation,
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	expected_delta := u64(0)
	if expected_commit {
		expected_delta = 1
	}
	if observation.resident_basis_after != observation.resident_basis_before + expected_delta ||
	   observation.durable_basis_after != observation.durable_basis_before + expected_delta ||
	   observation.durable_count_after != observation.durable_count_before + expected_delta {
		return pbt.fail(fmt.tprintf(
			"%s coordinates changed incorrectly: resident=%d->%d durable=%d->%d count=%d->%d",
			operation,
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if observation.resident_basis_after != observation.durable_basis_after {
		return pbt.fail(fmt.tprintf("resident and durable %s coordinates differ", operation))
	}
	return pbt.pass()
}

transaction_cas_command_name :: proc(command: Cas_Command) -> string {
	if command.expected_name == 0 {
		return "cas-nil"
	}
	return "cas-value"
}

transaction_cas_value_detail :: proc(observation: Cas_Observation) -> string {
	if observation.resident_committed && observation.durable_committed {
		return "cas-committed"
	}
	return "cas-rejected"
}
