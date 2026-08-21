// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

LOOKUP_MODEL_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "lookup-ref", "identity", "upsert", "atomic", "failure", "log"}
LOOKUP_KEY_COUNT :: MODEL_ENTITY_COUNT + 1

LOOKUP_SCHEMA :: `[
	{:db/id 100 :db/ident :item/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :item/tags :db/valueType :db.type/string :db/cardinality :db.cardinality/many}
	{:db/id 102 :db/ident :item/key :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
]`

LOOKUP_SEED :: `[
	{:db/id 1 :item/key "key-1"}
	{:db/id 2 :item/key "key-2"}
	{:db/id 3 :item/key "key-3"}
	{:db/id 4 :item/key "key-4"}
]`

Lookup_Command_Kind :: enum {
	Add_Name,
	Retract_Name,
	Identity_Upsert,
}

Lookup_Command :: struct {
	kind:        Lookup_Command_Kind,
	key_index:   int,
	value_index: int,
}

transaction_lookup_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx := Model_Context{compare_durable = true, reopen_durable = true, track_log = true}
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create lookup-model resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate lookup-model durable store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open lookup-model durable connection: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	if result := transaction_lookup_setup(t, &ctx.connection, &ctx.durable); result.status != .Pass {
		return result
	}
	resident_checkpoint, resident_checkpoint_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := transaction_cas_durable_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish a shared lookup-ref checkpoint")
	}

	model := pbt.State_Model(Model_State, Lookup_Command, Cas_Observation){
		target = &ctx,
		initial = transaction_model_initial,
		command = transaction_lookup_command,
		run = transaction_lookup_run,
		next_state = transaction_lookup_next_state,
		postcondition = transaction_lookup_postcondition,
		invariant = transaction_model_invariant,
		command_name = transaction_lookup_command_name,
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
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.connection, resident_checkpoint, "resident lookup refs"); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable lookup refs"); result.status != .Pass {
		return result
	}
	if result := transaction_model_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened lookup refs")
}

transaction_lookup_setup :: proc(
	t: ^pbt.T,
	resident: ^vev.Connection,
	durable: ^vev.Durable_Connection,
) -> pbt.Result {
	setup_transactions := [?]string{LOOKUP_SCHEMA, LOOKUP_SEED}
	for tx in setup_transactions {
		resident_report, resident_call_ok := vev.transact(resident, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize lookup model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	return pbt.pass()
}

transaction_lookup_command :: proc(t: ^pbt.T, state: Model_State) -> Lookup_Command {
	kind := Lookup_Command_Kind(pbt.draw(t, pbt.int_range(0, int(Lookup_Command_Kind.Identity_Upsert))))
	key_index := pbt.draw(t, pbt.int_range(1, LOOKUP_KEY_COUNT))
	if kind == .Identity_Upsert && key_index == LOOKUP_KEY_COUNT {
		key_index = MODEL_ENTITY_COUNT
	}
	value_index := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	pbt.classify(t, kind == .Add_Name, "lookup-add")
	pbt.classify(t, kind == .Retract_Name, "lookup-retract")
	pbt.classify(t, kind == .Identity_Upsert, "identity-upsert")
	pbt.classify(t, key_index <= MODEL_ENTITY_COUNT, "lookup-found")
	pbt.classify(t, key_index == LOOKUP_KEY_COUNT, "lookup-missing")
	return Lookup_Command{kind = kind, key_index = key_index, value_index = value_index}
}

transaction_lookup_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Model_State,
	command: Lookup_Command,
) -> Cas_Observation {
	ctx := cast(^Model_Context)target
	resident_before, resident_before_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_before, durable_before_ok := transaction_cas_durable_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	tx := transaction_lookup_edn(command)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_after, resident_after_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_after, durable_after_ok := transaction_cas_durable_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf("lookup=%s resident=%s durable=%s", tx, resident_report, durable_report))
	return Cas_Observation{
		resident_call_ok = resident_call_ok,
		resident_committed = resident_call_ok && strings.contains(resident_report, ":ok true"),
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

transaction_lookup_edn :: proc(command: Lookup_Command) -> string {
	key := fmt.tprintf("key-%d", command.key_index)
	switch command.kind {
	case .Add_Name:
		return fmt.tprintf(
			`[[:db/add [:item/key "%s"] :item/name "%s"]]`,
			key,
			MODEL_NAMES[command.value_index],
		)
	case .Retract_Name:
		return fmt.tprintf(`[[:db.fn/retractAttribute [:item/key "%s"] :item/name]]`, key)
	case .Identity_Upsert:
		body := fmt.tprintf(
			`:db/id "upsert" :item/key "%s" :item/name "%s"`,
			key,
			MODEL_NAMES[command.value_index],
		)
		return strings.concatenate([]string{"[{", body, "}]"})
	}
	return "[]"
}

transaction_lookup_next_state :: proc(
	state: Model_State,
	command: Lookup_Command,
	observation: Cas_Observation,
) -> Model_State {
	if !observation.resident_committed || !observation.durable_committed {
		return state
	}
	next := state
	if command.key_index <= MODEL_ENTITY_COUNT {
		switch command.kind {
		case .Add_Name, .Identity_Upsert:
			next.names[command.key_index - 1] = command.value_index + 1
		case .Retract_Name:
			next.names[command.key_index - 1] = 0
		}
	}
	next.ctx.final_names = next.names
	transaction_model_record_transaction(next.ctx, observation.resident_basis_after)
	transaction_batch_record_log_diff(next.ctx, state, next, observation.resident_basis_after)
	return next
}

transaction_lookup_postcondition :: proc(
	state: Model_State,
	command: Lookup_Command,
	observation: Cas_Observation,
) -> pbt.Result {
	expected_commit := command.kind != .Add_Name || command.key_index <= MODEL_ENTITY_COUNT
	return transaction_conditional_result(observation, expected_commit, "lookup-ref")
}

transaction_lookup_command_name :: proc(command: Lookup_Command) -> string {
	switch command.kind {
	case .Add_Name:
		return "lookup-add"
	case .Retract_Name:
		return "lookup-retract"
	case .Identity_Upsert:
		return "identity-upsert"
	}
	return "lookup"
}
