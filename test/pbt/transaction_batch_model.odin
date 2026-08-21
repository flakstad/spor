// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

BATCH_MAX_OPERATIONS :: 4
BATCH_MODEL_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "batch", "atomic"}

Batch_Command :: struct {
	operations: [BATCH_MAX_OPERATIONS]Model_Command,
	count:      int,
}

Batch_Observation :: struct {
	ok:             bool,
	report:         string,
	durable_ok:     bool,
	durable_report: string,
	basis:          u64,
	basis_ok:       bool,
	durable_basis:  u64,
	durable_basis_ok: bool,
}

transaction_batch_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx := Model_Context{compare_durable = true, reopen_durable = true, track_log = true}
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create batch-model resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate batch-model durable store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open batch-model durable connection: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	resident_schema, resident_schema_ok := vev.transact(
		&ctx.connection,
		MODEL_SCHEMA,
		t.value_allocator,
	)
	if !resident_schema_ok {
		return pbt.error(fmt.tprintf("could not install resident batch schema: %s", resident_schema))
	}
	durable_schema, durable_schema_ok := vev.transact(
		&ctx.durable,
		MODEL_SCHEMA,
		t.value_allocator,
	)
	if !durable_schema_ok {
		return pbt.error(fmt.tprintf("could not install durable batch schema: %s", durable_schema))
	}
	resident_schema_db, resident_schema_db_ok := vev.db(&ctx.connection)
	if !resident_schema_db_ok {
		return pbt.error("could not retain resident batch schema database")
	}
	resident_schema_basis, resident_schema_basis_ok := vev.basis_t(&resident_schema_db)
	vev.close(&resident_schema_db)
	durable_schema_db, durable_schema_db_ok := vev.db(&ctx.durable)
	if !durable_schema_db_ok {
		return pbt.error("could not retain durable batch schema database")
	}
	durable_schema_basis, durable_schema_basis_ok := vev.basis_t(&durable_schema_db)
	vev.close(&durable_schema_db)
	if !resident_schema_basis_ok || !durable_schema_basis_ok ||
	   resident_schema_basis != durable_schema_basis {
		return pbt.error("could not establish a shared batch schema basis")
	}

	model := pbt.State_Model(Model_State, Batch_Command, Batch_Observation){
		target = &ctx,
		initial = transaction_model_initial,
		command = transaction_batch_command,
		run = transaction_batch_run,
		next_state = transaction_batch_next_state,
		postcondition = transaction_batch_postcondition,
		invariant = transaction_model_invariant,
		command_name = transaction_batch_command_name,
		state_detail = transaction_model_state_detail,
		value_detail = transaction_batch_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 1,
		max_len = 8,
		max_success_events = 8,
		compact_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(
		t,
		&ctx,
		&ctx.connection,
		resident_schema_basis,
		"resident batches",
	); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(
		t,
		&ctx,
		&ctx.durable,
		durable_schema_basis,
		"durable batches",
	); result.status != .Pass {
		return result
	}
	if result := transaction_model_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return transaction_model_tx_range_invariant(
		t,
		&ctx,
		&ctx.durable,
		durable_schema_basis,
		"durable reopened batches",
	)
}

transaction_batch_command :: proc(t: ^pbt.T, state: Model_State) -> Batch_Command {
	command := Batch_Command{count = pbt.draw(t, pbt.int_range(2, BATCH_MAX_OPERATIONS))}
	for index in 0 ..< command.count {
		command.operations[index] = transaction_model_command(t, state)
	}
	pbt.classify(t, command.count == 2, "batch-2")
	pbt.classify(t, command.count == 3, "batch-3")
	pbt.classify(t, command.count == 4, "batch-4")
	return command
}

transaction_batch_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Model_State,
	command: Batch_Command,
) -> Batch_Observation {
	ctx := cast(^Model_Context)target
	tx := transaction_batch_edn(command)
	report, ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_ok := vev.transact(&ctx.durable, tx, t.value_allocator)
	observation := Batch_Observation{
		ok = ok,
		report = report,
		durable_ok = durable_ok,
		durable_report = durable_report,
	}
	if ok {
		database, database_ok := vev.db(&ctx.connection)
		if database_ok {
			observation.basis, observation.basis_ok = vev.basis_t(&database)
			vev.close(&database)
		}
	}
	if durable_ok {
		database, database_ok := vev.db(&ctx.durable)
		if database_ok {
			observation.durable_basis, observation.durable_basis_ok = vev.basis_t(&database)
			vev.close(&database)
		}
	}
	pbt.note(t, fmt.tprintf(
		"batch=%s resident=%s durable=%s",
		tx,
		report,
		durable_report,
	))
	return observation
}

transaction_batch_edn :: proc(command: Batch_Command) -> string {
	forms: [BATCH_MAX_OPERATIONS]string
	for index in 0 ..< command.count {
		forms[index] = transaction_model_command_form_edn(command.operations[index])
	}
	switch command.count {
	case 2:
		return fmt.tprintf("[%s %s]", forms[0], forms[1])
	case 3:
		return fmt.tprintf("[%s %s %s]", forms[0], forms[1], forms[2])
	case 4:
		return fmt.tprintf("[%s %s %s %s]", forms[0], forms[1], forms[2], forms[3])
	}
	return "[]"
}

transaction_batch_next_state :: proc(
	state: Model_State,
	command: Batch_Command,
	observation: Batch_Observation,
) -> Model_State {
	if !observation.ok || !observation.durable_ok {
		return state
	}
	next := state
	if next.ctx.track_log {
		transaction_model_record_transaction(next.ctx, observation.basis)
	}
	for index in 0 ..< command.count {
		operation := command.operations[index]
		next = transaction_model_apply_command(next, operation)
	}
	if next.ctx.track_log {
		transaction_batch_record_log_diff(next.ctx, state, next, observation.basis)
	}
	return next
}

transaction_batch_record_log_diff :: proc(
	ctx: ^Model_Context,
	before, after: Model_State,
	basis: u64,
) {
	for entity_index in 0 ..< MODEL_ENTITY_COUNT {
		before_name := before.names[entity_index]
		after_name := after.names[entity_index]
		if before_name != after_name {
			if before_name != 0 {
				transaction_model_record_log_datom(
					ctx,
					entity_index + 1,
					.Name,
					before_name - 1,
					basis,
					false,
				)
			}
			if after_name != 0 {
				transaction_model_record_log_datom(
					ctx,
					entity_index + 1,
					.Name,
					after_name - 1,
					basis,
					true,
				)
			}
		}
		for value_index in 0 ..< MODEL_VALUE_COUNT {
			if before.tags[entity_index][value_index] == after.tags[entity_index][value_index] {
				continue
			}
			transaction_model_record_log_datom(
				ctx,
				entity_index + 1,
				.Tag,
				value_index,
				basis,
				after.tags[entity_index][value_index],
			)
		}
	}
}

transaction_batch_postcondition :: proc(
	state: Model_State,
	command: Batch_Command,
	observation: Batch_Observation,
) -> pbt.Result {
	if !observation.ok {
		return pbt.error(fmt.tprintf("resident atomic batch failed: %s", observation.report))
	}
	if !observation.durable_ok {
		return pbt.error(fmt.tprintf("durable atomic batch failed: %s", observation.durable_report))
	}
	if !observation.basis_ok || !observation.durable_basis_ok {
		return pbt.error("could not read atomic batch transaction coordinates")
	}
	if observation.basis != observation.durable_basis {
		return pbt.fail(fmt.tprintf(
			"atomic batch basis differs: resident=%d durable=%d",
			observation.basis,
			observation.durable_basis,
		))
	}
	return pbt.pass()
}

transaction_batch_command_name :: proc(command: Batch_Command) -> string {
	return fmt.tprintf("batch-%d", command.count)
}

transaction_batch_value_detail :: proc(observation: Batch_Observation) -> string {
	if observation.ok && observation.durable_ok {
		return "batch-ok"
	}
	if !observation.ok {
		return observation.report
	}
	return observation.durable_report
}
