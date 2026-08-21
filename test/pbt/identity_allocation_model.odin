// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

IDENTITY_ALLOCATION_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "identity", "upsert", "tempid", "allocation", "log"}
IDENTITY_SLOT_COUNT :: 4
IDENTITY_LOG_DATOM_COUNT :: MODEL_TRANSACTION_COUNT * 3

IDENTITY_SCHEMA :: `[
	{:db/id 100 :db/ident :item/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :item/key :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
]`

Identity_Attribute :: enum {
	Key,
	Name,
}

Identity_Command :: struct {
	slot:        int,
	value_index: int,
}

Identity_Log_Datom :: struct {
	entity:      u64,
	attribute:   Identity_Attribute,
	value_index: int,
	basis:       u64,
	added:       bool,
}

Identity_Context :: struct {
	connection:        vev.Connection,
	durable:           vev.Durable_Connection,
	durable_path:      string,
	final_entities:    [IDENTITY_SLOT_COUNT]u64,
	final_names:       [IDENTITY_SLOT_COUNT]int,
	transaction_basis: [MODEL_TRANSACTION_COUNT]u64,
	transaction_count: int,
	log_datoms:        [IDENTITY_LOG_DATOM_COUNT]Identity_Log_Datom,
	log_datom_count:   int,
}

Identity_State :: struct {
	ctx:      ^Identity_Context,
	entities: [IDENTITY_SLOT_COUNT]u64,
	names:    [IDENTITY_SLOT_COUNT]int,
}

Identity_Observation :: struct {
	conditional:          Cas_Observation,
	resident_entity:      u64,
	resident_entity_ok:   bool,
	durable_entity:       u64,
	durable_entity_ok:    bool,
	durable_tempid:       u64,
	durable_tempid_ok:    bool,
}

identity_allocation_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Identity_Context
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create identity-allocation resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate identity-allocation store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open identity-allocation store: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	resident_schema, resident_schema_ok := vev.transact(&ctx.connection, IDENTITY_SCHEMA, t.value_allocator)
	durable_schema, durable_schema_ok := vev.transact(&ctx.durable, IDENTITY_SCHEMA, t.value_allocator)
	if !resident_schema_ok || !strings.contains(resident_schema, ":ok true") || !durable_schema_ok {
		return pbt.error(fmt.tprintf(
			"could not install identity schema: resident=%s durable=%s",
			resident_schema,
			durable_schema,
		))
	}
	resident_checkpoint, resident_checkpoint_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := transaction_cas_durable_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish identity-allocation checkpoint")
	}

	model := pbt.State_Model(Identity_State, Identity_Command, Identity_Observation){
		target = &ctx,
		initial = identity_allocation_initial,
		command = identity_allocation_command,
		run = identity_allocation_run,
		next_state = identity_allocation_next_state,
		postcondition = identity_allocation_postcondition,
		invariant = identity_allocation_invariant,
		command_name = identity_allocation_command_name,
		state_detail = identity_allocation_state_detail,
		value_detail = identity_allocation_value_detail,
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
	if result := identity_allocation_log_invariant(t, &ctx, &ctx.connection, resident_checkpoint, "resident identity upserts"); result.status != .Pass {
		return result
	}
	if result := identity_allocation_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable identity upserts"); result.status != .Pass {
		return result
	}
	if result := identity_allocation_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return identity_allocation_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened identity upserts")
}

identity_allocation_initial :: proc(t: ^pbt.T, target: rawptr) -> Identity_State {
	return Identity_State{ctx = cast(^Identity_Context)target}
}

identity_allocation_command :: proc(t: ^pbt.T, state: Identity_State) -> Identity_Command {
	command := Identity_Command{
		slot = pbt.draw(t, pbt.int_range(0, IDENTITY_SLOT_COUNT - 1)),
		value_index = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1)),
	}
	pbt.cover(t, state.entities[command.slot] == 0, 95, "identity-create")
	pbt.cover(t, state.entities[command.slot] != 0, 60, "identity-update")
	pbt.cover(t, state.names[command.slot] == command.value_index + 1, 25, "identity-same-value")
	return command
}

identity_allocation_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Identity_State,
	command: Identity_Command,
) -> Identity_Observation {
	ctx := cast(^Identity_Context)target
	resident_before, resident_before_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_before, durable_before_ok := transaction_cas_durable_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	tx := identity_allocation_edn(command)
	tempid := identity_allocation_tempid(command.slot)
	tempid_edn := fmt.tprintf(`"%s"`, tempid)

	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_native, durable_call_ok := vev.transact_report_durable(&ctx.durable, tx)
	durable_report := ""
	durable_report_ok := false
	durable_tempid: u64
	durable_tempid_ok := false
	if durable_call_ok {
		defer vev.close(&durable_native)
		durable_report, durable_report_ok = vev.tx_report_edn(&durable_native, t.value_allocator)
		durable_tempid, durable_tempid_ok = vev.tx_report_resolve_tempid(&durable_native, tempid_edn)
	}

	resident_after, resident_after_ok := transaction_cas_resident_basis(&ctx.connection)
	durable_after, durable_after_ok := transaction_cas_durable_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	resident_entity, resident_entity_ok := identity_allocation_lookup(&ctx.connection, command.slot)
	durable_entity, durable_entity_ok := identity_allocation_lookup(&ctx.durable, command.slot)
	pbt.note(t, fmt.tprintf("identity=%s resident=%s durable=%s", tx, resident_report, durable_report))

	return Identity_Observation{
		conditional = Cas_Observation{
			resident_call_ok = resident_call_ok,
			resident_committed = resident_call_ok && strings.contains(resident_report, ":ok true"),
			resident_report = resident_report,
			durable_committed = durable_call_ok && durable_report_ok && strings.contains(durable_report, ":ok true"),
			durable_report = durable_report,
			resident_basis_before = resident_before,
			resident_basis_after = resident_after,
			durable_basis_before = durable_before,
			durable_basis_after = durable_after,
			durable_count_before = count_before,
			durable_count_after = count_after,
			coordinates_ok = resident_before_ok && resident_after_ok && durable_before_ok &&
			                 durable_after_ok && count_before_ok && count_after_ok,
		},
		resident_entity = resident_entity,
		resident_entity_ok = resident_entity_ok,
		durable_entity = durable_entity,
		durable_entity_ok = durable_entity_ok,
		durable_tempid = durable_tempid,
		durable_tempid_ok = durable_tempid_ok,
	}
}

identity_allocation_edn :: proc(command: Identity_Command) -> string {
	body := fmt.tprintf(
		`:db/id "%s" :item/key "%s" :item/name "%s"`,
		identity_allocation_tempid(command.slot),
		identity_allocation_key(command.slot),
		MODEL_NAMES[command.value_index],
	)
	return strings.concatenate([]string{"[{", body, "}]"})
}

identity_allocation_tempid :: proc(slot: int) -> string {
	return fmt.tprintf("identity-%d", slot + 1)
}

identity_allocation_key :: proc(slot: int) -> string {
	return fmt.tprintf("new-key-%d", slot + 1)
}

identity_allocation_lookup :: proc(connection: ^$Connection, slot: int) -> (entity: u64, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return 0, false
	}
	defer vev.close(&database)
	entity_value, entity_ok := vev.entity_lookup_ref(
		&database,
		":item/key",
		fmt.tprintf(`"%s"`, identity_allocation_key(slot)),
	)
	if !entity_ok {
		return 0, false
	}
	defer vev.close(&entity_value)
	return vev.entity_id(&entity_value)
}

identity_allocation_next_state :: proc(
	state: Identity_State,
	command: Identity_Command,
	observation: Identity_Observation,
) -> Identity_State {
	if !observation.conditional.resident_committed || !observation.conditional.durable_committed {
		return state
	}
	next := state
	old_name := state.names[command.slot]
	if next.entities[command.slot] == 0 {
		next.entities[command.slot] = observation.resident_entity
		identity_allocation_record_log(next.ctx, Identity_Log_Datom{
			entity = observation.resident_entity,
			attribute = .Key,
			value_index = command.slot,
			basis = observation.conditional.resident_basis_after,
			added = true,
		})
	}
	if old_name != command.value_index + 1 {
		if old_name != 0 {
			identity_allocation_record_log(next.ctx, Identity_Log_Datom{
				entity = observation.resident_entity,
				attribute = .Name,
				value_index = old_name - 1,
				basis = observation.conditional.resident_basis_after,
				added = false,
			})
		}
		identity_allocation_record_log(next.ctx, Identity_Log_Datom{
			entity = observation.resident_entity,
			attribute = .Name,
			value_index = command.value_index,
			basis = observation.conditional.resident_basis_after,
			added = true,
		})
	}
	next.names[command.slot] = command.value_index + 1
	next.ctx.final_entities = next.entities
	next.ctx.final_names = next.names
	next.ctx.transaction_basis[next.ctx.transaction_count] = observation.conditional.resident_basis_after
	next.ctx.transaction_count += 1
	return next
}

identity_allocation_record_log :: proc(ctx: ^Identity_Context, datom: Identity_Log_Datom) {
	ctx.log_datoms[ctx.log_datom_count] = datom
	ctx.log_datom_count += 1
}

identity_allocation_postcondition :: proc(
	state: Identity_State,
	command: Identity_Command,
	observation: Identity_Observation,
) -> pbt.Result {
	if result := transaction_conditional_result(observation.conditional, true, "identity upsert"); result.status != .Pass {
		return result
	}
	if !observation.resident_entity_ok || !observation.durable_entity_ok ||
	   !observation.durable_tempid_ok {
		return pbt.error("identity upsert did not expose lookup-ref and tempid entities")
	}
	if observation.resident_entity != observation.durable_entity ||
	   observation.resident_entity != observation.durable_tempid {
		return pbt.fail(fmt.tprintf(
			"identity entity mismatch: resident=%d durable=%d tempid=%d",
			observation.resident_entity,
			observation.durable_entity,
			observation.durable_tempid,
		))
	}
	if state.entities[command.slot] != 0 &&
	   observation.resident_entity != state.entities[command.slot] {
		return pbt.fail(fmt.tprintf(
			"identity slot %d changed entity: expected=%d actual=%d",
			command.slot + 1,
			state.entities[command.slot],
			observation.resident_entity,
		))
	}
	if state.entities[command.slot] == 0 {
		for entity in state.entities {
			if entity != 0 && entity == observation.resident_entity {
				return pbt.fail(fmt.tprintf("new identity reused entity %d from another key", entity))
			}
		}
	}
	tempid_mapping := fmt.tprintf(
		`"%s" [:vev/entity %d]`,
		identity_allocation_tempid(command.slot),
		observation.resident_entity,
	)
	if !strings.contains(observation.conditional.resident_report, tempid_mapping) ||
	   !strings.contains(observation.conditional.durable_report, tempid_mapping) {
		return pbt.fail(fmt.tprintf("identity tempid mapping missing: %s", tempid_mapping))
	}
	return pbt.pass()
}

identity_allocation_invariant :: proc(t: ^pbt.T, state: Identity_State) -> pbt.Result {
	resident, resident_ok := vev.db(&state.ctx.connection)
	if !resident_ok {
		return pbt.error("could not retain resident identity database")
	}
	defer vev.close(&resident)
	if result := identity_allocation_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.ctx.durable)
	if !durable_ok {
		return pbt.error("could not retain durable identity database")
	}
	defer vev.close(&durable)
	return identity_allocation_database_invariant(t, state, &durable, "durable")
}

identity_allocation_database_invariant :: proc(
	t: ^pbt.T,
	state: Identity_State,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	result, query_ok := vev.query(database, `[:find ?e ?key ?name :where [?e :item/key ?key] [?e :item/name ?name]]`)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s identity relation query failed", backend))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s identity relation unavailable", backend))
	}
	expected_count := 0
	for entity in state.entities {
		if entity != 0 {
			expected_count += 1
		}
	}
	if vev.item_count(relation) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s identity count: expected=%d actual=%d",
			backend,
			expected_count,
			vev.item_count(relation),
		))
	}
	seen: [IDENTITY_SLOT_COUNT]bool
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		if !row_ok || vev.item_count(row) != 3 {
			return pbt.error(fmt.tprintf("%s identity row %d is malformed", backend, row_index))
		}
		entity_value, entity_ok := vev.item(row, 0)
		key_value, key_ok := vev.item(row, 1)
		name_value, name_ok := vev.item(row, 2)
		entity, entity_value_ok := vev.as_int(entity_value)
		key, key_value_ok := vev.as_string(key_value, t.value_allocator)
		name, name_value_ok := vev.as_string(name_value, t.value_allocator)
		slot := identity_allocation_key_index(key)
		if !entity_ok || !key_ok || !name_ok || !entity_value_ok || !key_value_ok ||
		   !name_value_ok || entity <= 0 || slot < 0 {
			return pbt.error(fmt.tprintf("%s identity row %d has unexpected values", backend, row_index))
		}
		if seen[slot] || state.entities[slot] != u64(entity) || state.names[slot] == 0 ||
		   MODEL_NAMES[state.names[slot] - 1] != name {
			return pbt.fail(fmt.tprintf(
				"%s identity row mismatch: entity=%d key=%s name=%s",
				backend,
				entity,
				key,
				name,
			))
		}
		seen[slot] = true
	}
	for slot in 0 ..< IDENTITY_SLOT_COUNT {
		lookup, lookup_ok := vev.entity_lookup_ref(
			database,
			":item/key",
			fmt.tprintf(`"%s"`, identity_allocation_key(slot)),
		)
		if state.entities[slot] == 0 {
			if lookup_ok {
				vev.close(&lookup)
				return pbt.fail(fmt.tprintf("%s unexpectedly resolved identity slot %d", backend, slot + 1))
			}
			continue
		}
		if !lookup_ok {
			return pbt.fail(fmt.tprintf("%s did not resolve identity slot %d", backend, slot + 1))
		}
		lookup_entity, lookup_entity_ok := vev.entity_id(&lookup)
		vev.close(&lookup)
		if !lookup_entity_ok || lookup_entity != state.entities[slot] {
			return pbt.fail(fmt.tprintf(
				"%s lookup entity for slot %d: expected=%d actual=%d",
				backend,
				slot + 1,
				state.entities[slot],
				lookup_entity,
			))
		}
	}
	return pbt.pass()
}

identity_allocation_key_index :: proc(key: string) -> int {
	for slot in 0 ..< IDENTITY_SLOT_COUNT {
		if key == identity_allocation_key(slot) {
			return slot
		}
	}
	return -1
}

identity_allocation_log_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Identity_Context,
	connection: ^$Connection,
	checkpoint_basis: u64,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s log", backend))
	}
	defer vev.close(&log_value)
	current_basis := checkpoint_basis
	if ctx.transaction_count > 0 {
		current_basis = ctx.transaction_basis[ctx.transaction_count - 1]
	}
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint_basis + 1, current_basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s transaction range failed", backend))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.kind(transactions_value) != .Vector {
		return pbt.error(fmt.tprintf("%s transaction range is not a vector", backend))
	}
	if vev.item_count(transactions_value) != ctx.transaction_count {
		return pbt.fail(fmt.tprintf(
			"%s transaction count: expected=%d actual=%d",
			backend,
			ctx.transaction_count,
			vev.item_count(transactions_value),
		))
	}
	matched: [IDENTITY_LOG_DATOM_COUNT]bool
	for transaction_index in 0 ..< ctx.transaction_count {
		transaction, transaction_ok := vev.item(transactions_value, transaction_index)
		if !transaction_ok || vev.kind(transaction) != .Map {
			return pbt.error(fmt.tprintf("%s transaction %d is malformed", backend, transaction_index))
		}
		t_value, t_ok := vev.get(transaction, ":t")
		data, data_ok := vev.get(transaction, ":data")
		basis, basis_ok := vev.as_int(t_value)
		expected_basis := ctx.transaction_basis[transaction_index]
		if !t_ok || !data_ok || !basis_ok || basis < 0 || u64(basis) != expected_basis ||
		   vev.kind(data) != .Vector {
			return pbt.fail(fmt.tprintf("%s transaction %d has wrong coordinate", backend, transaction_index))
		}
		actual_count := 0
		for datom_index in 0 ..< vev.item_count(data) {
			value, datom_ok := vev.item(data, datom_index)
			actual, application, parse_ok := identity_allocation_log_datom(t, value, expected_basis)
			if !datom_ok || !parse_ok {
				return pbt.error(fmt.tprintf("%s transaction %d has malformed datom", backend, transaction_index))
			}
			if !application {
				continue
			}
			actual_count += 1
			found := false
			for expected_index in 0 ..< ctx.log_datom_count {
				if !matched[expected_index] && identity_allocation_log_equal(actual, ctx.log_datoms[expected_index]) {
					matched[expected_index] = true
					found = true
					break
				}
			}
			if !found {
				return pbt.fail(fmt.tprintf("%s transaction %d has unexpected identity datom", backend, transaction_index))
			}
		}
		expected_count := 0
		for expected in ctx.log_datoms[:ctx.log_datom_count] {
			if expected.basis == expected_basis {
				expected_count += 1
			}
		}
		if actual_count != expected_count {
			return pbt.fail(fmt.tprintf(
				"%s transaction %d application datoms: expected=%d actual=%d",
				backend,
				transaction_index,
				expected_count,
				actual_count,
			))
		}
	}
	for expected_index in 0 ..< ctx.log_datom_count {
		if !matched[expected_index] {
			return pbt.fail(fmt.tprintf("%s omitted identity datom %d", backend, expected_index))
		}
	}
	return pbt.pass()
}

identity_allocation_log_datom :: proc(
	t: ^pbt.T,
	value: vev.Value,
	expected_basis: u64,
) -> (datom: Identity_Log_Datom, application: bool, ok: bool) {
	if vev.kind(value) != .Vector || vev.item_count(value) != 5 {
		return {}, false, false
	}
	entity_value, entity_ok := vev.item(value, 0)
	attribute_value, attribute_ok := vev.item(value, 1)
	fact_value, fact_ok := vev.item(value, 2)
	tx_value, tx_ok := vev.item(value, 3)
	added_value, added_ok := vev.item(value, 4)
	attribute, attribute_string_ok := vev.as_string(attribute_value, t.value_allocator)
	if !entity_ok || !attribute_ok || !fact_ok || !tx_ok || !added_ok || !attribute_string_ok {
		return {}, false, false
	}
	if attribute != ":item/key" && attribute != ":item/name" {
		return {}, false, true
	}
	entity, entity_value_ok := vev.as_entity(entity_value)
	fact, fact_string_ok := vev.as_string(fact_value, t.value_allocator)
	tx, tx_entity_ok := vev.as_entity(tx_value)
	added, added_bool_ok := vev.as_bool(added_value)
	if !entity_value_ok || !fact_string_ok || !tx_entity_ok || !added_bool_ok ||
	   tx != vev.t_to_tx(expected_basis) {
		return {}, true, false
	}
	if attribute == ":item/key" {
		slot := identity_allocation_key_index(fact)
		if slot < 0 {
			return {}, true, false
		}
		return Identity_Log_Datom{
			entity = entity,
			attribute = .Key,
			value_index = slot,
			basis = expected_basis,
			added = added,
		}, true, true
	}
	value_index := transaction_model_value_index(fact, MODEL_NAMES[:])
	if value_index < 0 {
		return {}, true, false
	}
	return Identity_Log_Datom{
		entity = entity,
		attribute = .Name,
		value_index = value_index,
		basis = expected_basis,
		added = added,
	}, true, true
}

identity_allocation_log_equal :: proc(left, right: Identity_Log_Datom) -> bool {
	return left.entity == right.entity && left.attribute == right.attribute &&
	       left.value_index == right.value_index && left.basis == right.basis &&
	       left.added == right.added
}

identity_allocation_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Identity_Context) -> pbt.Result {
	basis_before, basis_before_ok := vev.connection_basis_t(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read identity coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen identity-allocation store")
	}
	basis_after, basis_after_ok := vev.connection_basis_t(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"identity coordinates changed across reopen: basis=%d->%d count=%d->%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened identity database")
	}
	defer vev.close(&database)
	state := Identity_State{ctx = ctx, entities = ctx.final_entities, names = ctx.final_names}
	if result := identity_allocation_database_invariant(t, state, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "identity-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d",
		basis_after,
		count_after,
	))
	return pbt.pass()
}

identity_allocation_command_name :: proc(command: Identity_Command) -> string {
	return "identity-upsert-allocation"
}

identity_allocation_state_detail :: proc(state: Identity_State) -> string {
	created := 0
	for entity in state.entities {
		if entity != 0 {
			created += 1
		}
	}
	return fmt.tprintf("created=%d", created)
}

identity_allocation_value_detail :: proc(observation: Identity_Observation) -> string {
	return fmt.tprintf(
		"resident=%d durable=%d tempid=%d",
		observation.resident_entity,
		observation.durable_entity,
		observation.durable_tempid,
	)
}
