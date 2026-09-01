package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

IDENTITY_CONFLICT_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "identity", "upsert", "tempid", "conflict", "atomic", "failure", "log"}

IDENTITY_CONFLICT_SCHEMA :: `[
	{:db/id 100 :db/ident :item/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :item/key-a :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
	{:db/id 102 :db/ident :item/key-b :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
]`

IDENTITY_CONFLICT_SEED :: `[
	{:db/id 1 :item/key-a "a-1" :item/key-b "b-1"}
	{:db/id 2 :item/key-a "a-2" :item/key-b "b-2"}
	{:db/id 3 :item/key-a "a-3" :item/key-b "b-3"}
	{:db/id 4 :item/key-a "a-4" :item/key-b "b-4"}
]`

Identity_Conflict_Command :: struct {
	left_entity:       int,
	right_entity:      int,
	prefix_entity:     int,
	prefix_name:       int,
	upsert_name:       int,
}

identity_conflict_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx := Model_Context{compare_durable = true, reopen_durable = true, track_log = true}
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create identity-conflict resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate identity-conflict store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open identity-conflict store: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	if result := identity_conflict_setup(t, &ctx.connection, &ctx.durable); result.status != .Pass {
		return result
	}
	resident_checkpoint, resident_checkpoint_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := transaction_cas_durable_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish identity-conflict checkpoint")
	}

	model := pbt.State_Model(Model_State, Identity_Conflict_Command, Cas_Observation){
		target = &ctx,
		initial = transaction_model_initial,
		command = identity_conflict_command,
		run = identity_conflict_run,
		next_state = identity_conflict_next_state,
		postcondition = identity_conflict_postcondition,
		invariant = identity_conflict_invariant,
		command_name = identity_conflict_command_name,
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
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.connection, resident_checkpoint, "resident identity conflicts"); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable identity conflicts"); result.status != .Pass {
		return result
	}
	if result := transaction_model_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	if result := identity_conflict_refs_invariant(t, &ctx.durable, "durable reopened"); result.status != .Pass {
		return result
	}
	return transaction_model_tx_range_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened identity conflicts")
}

identity_conflict_setup :: proc(
	t: ^pbt.T,
	resident: ^vev.Connection,
	durable: ^vev.Durable_Connection,
) -> pbt.Result {
	transactions := [?]string{IDENTITY_CONFLICT_SCHEMA, IDENTITY_CONFLICT_SEED}
	for tx in transactions {
		resident_report, resident_ok := vev.transact(resident, tx, t.value_allocator)
		durable_report, durable_ok := vev.transact(durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_ok {
			return pbt.error(fmt.tprintf(
				"could not initialize identity conflicts: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	return pbt.pass()
}

identity_conflict_command :: proc(t: ^pbt.T, state: Model_State) -> Identity_Conflict_Command {
	command := Identity_Conflict_Command{
		left_entity = pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT)),
		right_entity = pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT)),
		prefix_entity = pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT)),
		prefix_name = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1)),
		upsert_name = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1)),
	}
	merges := command.left_entity == command.right_entity
	pbt.cover(t, merges, 15, "identity-merge")
	pbt.cover(t, !merges, 60, "identity-conflict")
	pbt.cover(t, merges && command.prefix_entity == command.left_entity, 3, "identity-last-write")
	return command
}

identity_conflict_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Model_State,
	command: Identity_Conflict_Command,
) -> Cas_Observation {
	ctx := cast(^Model_Context)target
	resident_before, resident_before_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_before, durable_before_ok := transaction_cas_durable_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	tx := identity_conflict_edn(command)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_after, resident_after_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_after, durable_after_ok := transaction_cas_durable_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf("identity-conflict=%s resident=%s durable=%s", tx, resident_report, durable_report))
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

identity_conflict_edn :: proc(command: Identity_Conflict_Command) -> string {
	upsert_body := fmt.tprintf(
		`:db/id "identity-merge" :item/key-a "a-%d" :item/key-b "b-%d" :item/name "%s"`,
		command.left_entity,
		command.right_entity,
		MODEL_NAMES[command.upsert_name],
	)
	prefix := fmt.tprintf(
		`[[:db/add %d :item/name "%s"] `,
		command.prefix_entity,
		MODEL_NAMES[command.prefix_name],
	)
	return strings.concatenate([]string{
		prefix,
		"{",
		upsert_body,
		"}]",
	})
}

identity_conflict_next_state :: proc(
	state: Model_State,
	command: Identity_Conflict_Command,
	observation: Cas_Observation,
) -> Model_State {
	if !observation.resident_committed || !observation.durable_committed {
		return state
	}
	next := state
	next.names[command.prefix_entity - 1] = command.prefix_name + 1
	next.names[command.left_entity - 1] = command.upsert_name + 1
	next.ctx.final_names = next.names
	transaction_model_record_transaction(next.ctx, observation.resident_basis_after)
	transaction_batch_record_log_diff(next.ctx, state, next, observation.resident_basis_after)
	return next
}

identity_conflict_postcondition :: proc(
	state: Model_State,
	command: Identity_Conflict_Command,
	observation: Cas_Observation,
) -> pbt.Result {
	expected_commit := command.left_entity == command.right_entity
	if result := transaction_conditional_result(observation, expected_commit, "identity merge"); result.status != .Pass {
		return result
	}
	if expected_commit {
		tempid_mapping := fmt.tprintf(`"identity-merge" [:vev/entity %d]`, command.left_entity)
		if !strings.contains(observation.resident_report, tempid_mapping) ||
		   !strings.contains(observation.durable_report, tempid_mapping) {
			return pbt.fail(fmt.tprintf("identity merge tempid mapping missing: %s", tempid_mapping))
		}
		return pbt.pass()
	}
	if !strings.contains(observation.resident_report, "conflicting upsert") ||
	   !strings.contains(observation.durable_report, "conflicting upsert") {
		return pbt.fail("identity conflict did not report conflicting upsert on both backends")
	}
	return pbt.pass()
}

identity_conflict_invariant :: proc(t: ^pbt.T, state: Model_State) -> pbt.Result {
	if result := transaction_model_invariant(t, state); result.status != .Pass {
		return result
	}
	if result := identity_conflict_refs_invariant(t, &state.ctx.connection, "resident"); result.status != .Pass {
		return result
	}
	return identity_conflict_refs_invariant(t, &state.ctx.durable, "durable")
}

identity_conflict_refs_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s identity database", backend))
	}
	defer vev.close(&database)
	attributes := [?]string{":item/key-a", ":item/key-b"}
	prefixes := [?]string{"a", "b"}
	for attribute, attribute_index in attributes {
		for entity in 1 ..= MODEL_ENTITY_COUNT {
			lookup, lookup_ok := vev.entity_lookup_ref(
				&database,
				attribute,
				fmt.tprintf(`"%s-%d"`, prefixes[attribute_index], entity),
			)
			if !lookup_ok {
				return pbt.fail(fmt.tprintf("%s did not resolve %s for entity %d", backend, attribute, entity))
			}
			actual, actual_ok := vev.entity_id(&lookup)
			vev.close(&lookup)
			if !actual_ok || actual != u64(entity) {
				return pbt.fail(fmt.tprintf(
					"%s %s resolved to %d instead of %d",
					backend,
					attribute,
					actual,
					entity,
				))
			}
		}
	}
	return pbt.pass()
}

identity_conflict_command_name :: proc(command: Identity_Conflict_Command) -> string {
	if command.left_entity == command.right_entity {
		return "identity-merge"
	}
	return "identity-conflict"
}
