// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:os"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

MODEL_ENTITY_COUNT :: 4
MODEL_VALUE_COUNT :: 4
MODEL_TRANSACTION_COUNT :: 12
MODEL_LOG_DATOM_COUNT :: MODEL_TRANSACTION_COUNT * (MODEL_VALUE_COUNT + 1)

MODEL_NAMES := [?]string{"ada", "grace", "barbara", "hedy"}
MODEL_TAGS := [?]string{"red", "green", "blue", "gold"}
TRANSACTION_MODEL_TAGS := [?]string{"core", "stateful", "transaction", "model"}
DIFFERENTIAL_MODEL_TAGS := [?]string{"core", "stateful", "transaction", "model", "durable", "differential", "history", "snapshot", "since", "audit", "log", "tx-range"}

MODEL_SCHEMA :: `[
	{:db/id 100 :db/ident :item/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :item/tags :db/valueType :db.type/string :db/cardinality :db.cardinality/many}
]`

Model_Command_Kind :: enum {
	Add_Name,
	Add_Tag,
	Retract_Name,
	Retract_Tag,
	Retract_Name_Attribute,
	Retract_Tags_Attribute,
	Retract_Entity,
}

Model_Command :: struct {
	kind:        Model_Command_Kind,
	entity:      int,
	value_index: int,
}

Model_Attribute :: enum {
	Name,
	Tag,
}

Model_Log_Datom :: struct {
	entity:      int,
	attribute:   Model_Attribute,
	value_index: int,
	basis:       u64,
	added:       bool,
}

Model_Context :: struct {
	connection:       vev.Connection,
	durable:          vev.Durable_Connection,
	compare_durable:  bool,
	reopen_durable:   bool,
	durable_path:     string,
	final_names:      [MODEL_ENTITY_COUNT]int,
	final_tags:       [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool,
	track_since:      bool,
	since_names:      [MODEL_ENTITY_COUNT]int,
	since_tags:       [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool,
	track_log:        bool,
	transaction_basis: [MODEL_TRANSACTION_COUNT]u64,
	transaction_count: int,
	log_datoms:        [MODEL_LOG_DATOM_COUNT]Model_Log_Datom,
	log_datom_count:   int,
	suffix_tx_start:   int,
	suffix_datom_start: int,
}

Model_State :: struct {
	ctx:   ^Model_Context,
	names: [MODEL_ENTITY_COUNT]int,
	tags:  [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool,
}

Model_Observation :: struct {
	ok:             bool,
	report:         string,
	durable_ok:     bool,
	durable_report: string,
	basis:          u64,
	basis_ok:       bool,
	durable_basis:  u64,
	durable_basis_ok: bool,
}

Model_History_Fact :: struct {
	seen:  bool,
	basis: u64,
	added: bool,
}

transaction_model_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Model_Context
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create transaction-model connection")
	}
	defer vev.close(&ctx.connection)

	schema_result, schema_ok := vev.transact(
		&ctx.connection,
		MODEL_SCHEMA,
		t.value_allocator,
	)
	if !schema_ok {
		return pbt.error(fmt.tprintf("could not install transaction-model schema: %s", schema_result))
	}

	return run_transaction_model(t, &ctx)
}

transaction_differential_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx := Model_Context{compare_durable = true, reopen_durable = true, track_log = true}
	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create differential resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate temporary durable store path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)

	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not open differential durable connection: %s", error_text))
	}
	defer vev.close(&ctx.durable)

	resident_schema, resident_schema_ok := vev.transact(
		&ctx.connection,
		MODEL_SCHEMA,
		t.value_allocator,
	)
	if !resident_schema_ok {
		return pbt.error(fmt.tprintf("could not install resident schema: %s", resident_schema))
	}
	durable_schema, durable_schema_ok := vev.transact(
		&ctx.durable,
		MODEL_SCHEMA,
		t.value_allocator,
	)
	if !durable_schema_ok {
		return pbt.error(fmt.tprintf("could not install durable schema: %s", durable_schema))
	}

	return run_transaction_history_model(t, &ctx)
}

run_transaction_model :: proc(t: ^pbt.T, ctx: ^Model_Context) -> pbt.Result {
	max_len := 30
	if ctx.compare_durable {
		max_len = 12
	}
	result := run_transaction_model_phase(t, ctx, 1, max_len)
	if result.status != .Pass || !ctx.reopen_durable {
		return result
	}
	return transaction_model_reopen_invariant(t, ctx)
}

run_transaction_model_phase :: proc(
	t: ^pbt.T,
	ctx: ^Model_Context,
	min_len, max_len: int,
) -> pbt.Result {
	model := pbt.State_Model(Model_State, Model_Command, Model_Observation){
		target = ctx,
		initial = transaction_model_initial,
		command = transaction_model_command,
		run = transaction_model_run,
		next_state = transaction_model_next_state,
		postcondition = transaction_model_postcondition,
		invariant = transaction_model_invariant,
		command_name = transaction_model_command_name,
		state_detail = transaction_model_state_detail,
		value_detail = transaction_model_value_detail,
	}
	return pbt.run_commands(t, model, {
		min_len = min_len,
		max_len = max_len,
		max_success_events = 12,
		compact_success_events = true,
	})
}

run_transaction_history_model :: proc(t: ^pbt.T, ctx: ^Model_Context) -> pbt.Result {
	if result := run_transaction_model_phase(t, ctx, 1, 6); result.status != .Pass {
		return result
	}

	checkpoint := Model_State{
		ctx = ctx,
		names = ctx.final_names,
		tags = ctx.final_tags,
	}
	resident_snapshot, resident_ok := vev.db(&ctx.connection)
	if !resident_ok {
		return pbt.error("could not retain resident history checkpoint")
	}
	defer vev.close(&resident_snapshot)
	durable_snapshot, durable_ok := vev.db(&ctx.durable)
	if !durable_ok {
		return pbt.error("could not retain durable history checkpoint")
	}
	defer vev.close(&durable_snapshot)

	resident_basis, resident_basis_ok := vev.basis_t(&resident_snapshot)
	durable_basis, durable_basis_ok := vev.basis_t(&durable_snapshot)
	if !resident_basis_ok || !durable_basis_ok {
		return pbt.error("could not read history checkpoint coordinates")
	}
	if resident_basis != durable_basis {
		return pbt.fail(fmt.tprintf(
			"history checkpoint basis differs: resident=%d durable=%d",
			resident_basis,
			durable_basis,
		))
	}
	pbt.record_event(t, "history", "checkpoint", "ok", fmt.tprintf("basis=%d", resident_basis))

	ctx.track_since = true
	ctx.since_names = {}
	ctx.since_tags = {}
	ctx.suffix_tx_start = ctx.transaction_count
	ctx.suffix_datom_start = ctx.log_datom_count
	if result := run_transaction_model_phase(t, ctx, 1, 6); result.status != .Pass {
		return result
	}
	if result := transaction_model_database_invariant(t, checkpoint, &resident_snapshot, "resident checkpoint"); result.status != .Pass {
		return result
	}
	if result := transaction_model_database_invariant(t, checkpoint, &durable_snapshot, "durable checkpoint"); result.status != .Pass {
		return result
	}
	if result := transaction_model_as_of_invariant(t, checkpoint, &ctx.connection, resident_basis, "resident"); result.status != .Pass {
		return result
	}
	if result := transaction_model_as_of_invariant(t, checkpoint, &ctx.durable, durable_basis, "durable"); result.status != .Pass {
		return result
	}
	if result := transaction_model_since_invariant(t, ctx, &ctx.connection, resident_basis, "resident"); result.status != .Pass {
		return result
	}
	if result := transaction_model_since_invariant(t, ctx, &ctx.durable, durable_basis, "durable"); result.status != .Pass {
		return result
	}
	if result := transaction_model_history_invariant(t, checkpoint, ctx, &ctx.connection, resident_basis, "resident"); result.status != .Pass {
		return result
	}
	if result := transaction_model_history_invariant(t, checkpoint, ctx, &ctx.durable, durable_basis, "durable"); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, ctx, &ctx.connection, resident_basis, "resident"); result.status != .Pass {
		return result
	}
	if result := transaction_model_tx_range_invariant(t, ctx, &ctx.durable, durable_basis, "durable"); result.status != .Pass {
		return result
	}

	if result := transaction_model_reopen_invariant(t, ctx); result.status != .Pass {
		return result
	}
	if result := transaction_model_as_of_invariant(t, checkpoint, &ctx.durable, durable_basis, "durable reopened"); result.status != .Pass {
		return result
	}
	if result := transaction_model_since_invariant(t, ctx, &ctx.durable, durable_basis, "durable reopened"); result.status != .Pass {
		return result
	}
	if result := transaction_model_history_invariant(t, checkpoint, ctx, &ctx.durable, durable_basis, "durable reopened"); result.status != .Pass {
		return result
	}
	return transaction_model_tx_range_invariant(t, ctx, &ctx.durable, durable_basis, "durable reopened")
}

transaction_model_as_of_invariant :: proc(
	t: ^pbt.T,
	checkpoint: Model_State,
	connection: ^$Connection,
	checkpoint_basis: u64,
	backend: string,
) -> pbt.Result {
	current, current_ok := vev.db(connection)
	if !current_ok {
		return pbt.error(fmt.tprintf("could not retain %s database for as-of", backend))
	}
	defer vev.close(&current)
	current_basis, current_basis_ok := vev.basis_t(&current)
	if !current_basis_ok {
		return pbt.error(fmt.tprintf("could not read %s current basis", backend))
	}
	if current_basis <= checkpoint_basis {
		return pbt.fail(fmt.tprintf(
			"%s did not advance beyond history checkpoint: checkpoint=%d current=%d",
			backend,
			checkpoint_basis,
			current_basis,
		))
	}
	as_of, as_of_ok := vev.as_of(&current, checkpoint_basis)
	if !as_of_ok {
		return pbt.error(fmt.tprintf("could not create %s as-of database", backend))
	}
	defer vev.close(&as_of)

	as_of_basis, basis_present := vev.as_of_t(&as_of)
	if !basis_present || as_of_basis != checkpoint_basis {
		return pbt.fail(fmt.tprintf(
			"%s as-of metadata: expected=%d actual=%d present=%v",
			backend,
			checkpoint_basis,
			as_of_basis,
			basis_present,
		))
	}
	return transaction_model_database_invariant(t, checkpoint, &as_of, fmt.tprintf("%s as-of", backend))
}

transaction_model_since_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Model_Context,
	connection: ^$Connection,
	checkpoint_basis: u64,
	backend: string,
) -> pbt.Result {
	current, current_ok := vev.db(connection)
	if !current_ok {
		return pbt.error(fmt.tprintf("could not retain %s database for since", backend))
	}
	defer vev.close(&current)
	since, since_ok := vev.since(&current, checkpoint_basis)
	if !since_ok {
		return pbt.error(fmt.tprintf("could not create %s since database", backend))
	}
	defer vev.close(&since)

	since_basis, basis_present := vev.since_t(&since)
	if !basis_present || since_basis != checkpoint_basis {
		return pbt.fail(fmt.tprintf(
			"%s since metadata: expected=%d actual=%d present=%v",
			backend,
			checkpoint_basis,
			since_basis,
			basis_present,
		))
	}
	since_state := Model_State{
		ctx = ctx,
		names = ctx.since_names,
		tags = ctx.since_tags,
	}
	return transaction_model_database_invariant(t, since_state, &since, fmt.tprintf("%s since", backend))
}

transaction_model_history_invariant :: proc(
	t: ^pbt.T,
	checkpoint: Model_State,
	ctx: ^Model_Context,
	connection: ^$Connection,
	checkpoint_basis: u64,
	backend: string,
) -> pbt.Result {
	current, current_ok := vev.db(connection)
	if !current_ok {
		return pbt.error(fmt.tprintf("could not retain %s database for history", backend))
	}
	defer vev.close(&current)
	current_basis, current_basis_ok := vev.basis_t(&current)
	if !current_basis_ok {
		return pbt.error(fmt.tprintf("could not read %s basis for history", backend))
	}
	history, history_ok := vev.history(&current)
	if !history_ok {
		return pbt.error(fmt.tprintf("could not create %s history database", backend))
	}
	defer vev.close(&history)
	if !vev.is_history(&history) {
		return pbt.fail(fmt.tprintf("%s history database is missing history metadata", backend))
	}

	checkpoint_names: [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool
	final_names: [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool
	for entity_index in 0 ..< MODEL_ENTITY_COUNT {
		if checkpoint.names[entity_index] != 0 {
			checkpoint_names[entity_index][checkpoint.names[entity_index] - 1] = true
		}
		if ctx.final_names[entity_index] != 0 {
			final_names[entity_index][ctx.final_names[entity_index] - 1] = true
		}
	}
	if result := transaction_model_history_attribute_invariant(
		t,
		&history,
		checkpoint_names,
		final_names,
		checkpoint_basis,
		current_basis,
		":item/name",
		MODEL_NAMES[:],
		backend,
	); result.status != .Pass {
		return result
	}
	return transaction_model_history_attribute_invariant(
		t,
		&history,
		checkpoint.tags,
		ctx.final_tags,
		checkpoint_basis,
		current_basis,
		":item/tags",
		MODEL_TAGS[:],
		backend,
	)
}

transaction_model_history_attribute_invariant :: proc(
	t: ^pbt.T,
	history: ^vev.DB,
	checkpoint_expected, final_expected: [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool,
	checkpoint_basis, current_basis: u64,
	attribute: string,
	values: []string,
	backend: string,
) -> pbt.Result {
	query := fmt.tprintf(
		`[:find ?e ?value ?tx ?added :where [?e %s ?value ?tx ?added]]`,
		attribute,
	)
	result, query_ok := vev.query(history, query)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s history query failed for %s", backend, attribute))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s history relation unavailable for %s", backend, attribute))
	}

	checkpoint_facts: [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]Model_History_Fact
	final_facts: [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]Model_History_Fact
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		if !row_ok || vev.item_count(row) != 4 {
			return pbt.error(fmt.tprintf("%s history row %d is malformed", backend, row_index))
		}
		entity_value, entity_ok := vev.item(row, 0)
		fact_value, fact_ok := vev.item(row, 1)
		tx_value, tx_ok := vev.item(row, 2)
		added_value, added_ok := vev.item(row, 3)
		entity, entity_int_ok := vev.as_int(entity_value)
		fact, fact_string_ok := vev.as_string(fact_value, t.value_allocator)
		tx, tx_int_ok := vev.as_int(tx_value)
		added, added_bool_ok := vev.as_bool(added_value)
		value_index := transaction_model_value_index(fact, values)
		if !entity_ok || !fact_ok || !tx_ok || !added_ok ||
		   !entity_int_ok || !fact_string_ok || !tx_int_ok || !added_bool_ok ||
		   entity < 1 || entity > MODEL_ENTITY_COUNT || tx < 0 || value_index < 0 {
			return pbt.error(fmt.tprintf("%s history row %d has unexpected values", backend, row_index))
		}
		basis := vev.tx_to_t(u64(tx))
		if basis == 0 || basis > current_basis {
			return pbt.fail(fmt.tprintf(
				"%s history row %d has transaction outside basis: tx=%d basis=%d",
				backend,
				row_index,
				tx,
				current_basis,
			))
		}

		entity_index := int(entity) - 1
		if update_result := transaction_model_history_fact_update(
			&final_facts[entity_index][value_index],
			basis,
			added,
			backend,
			attribute,
			entity,
			fact,
		); update_result.status != .Pass {
			return update_result
		}
		if basis <= checkpoint_basis {
			if update_result := transaction_model_history_fact_update(
				&checkpoint_facts[entity_index][value_index],
				basis,
				added,
				backend,
				attribute,
				entity,
				fact,
			); update_result.status != .Pass {
				return update_result
			}
		}
	}

	for entity_index in 0 ..< MODEL_ENTITY_COUNT {
		for value_index in 0 ..< MODEL_VALUE_COUNT {
			checkpoint_actual := checkpoint_facts[entity_index][value_index].seen &&
			                     checkpoint_facts[entity_index][value_index].added
			if checkpoint_actual != checkpoint_expected[entity_index][value_index] {
				return pbt.fail(fmt.tprintf(
					"%s history checkpoint mismatch for entity %d %s %q: expected=%v actual=%v",
					backend,
					entity_index + 1,
					attribute,
					values[value_index],
					checkpoint_expected[entity_index][value_index],
					checkpoint_actual,
				))
			}
			final_actual := final_facts[entity_index][value_index].seen &&
			                final_facts[entity_index][value_index].added
			if final_actual != final_expected[entity_index][value_index] {
				return pbt.fail(fmt.tprintf(
					"%s history final mismatch for entity %d %s %q: expected=%v actual=%v",
					backend,
					entity_index + 1,
					attribute,
					values[value_index],
					final_expected[entity_index][value_index],
					final_actual,
				))
			}
		}
	}
	return pbt.pass()
}

transaction_model_history_fact_update :: proc(
	fact: ^Model_History_Fact,
	basis: u64,
	added: bool,
	backend, attribute: string,
	entity: i64,
	value: string,
) -> pbt.Result {
	if fact.seen && fact.basis == basis && fact.added != added {
		return pbt.fail(fmt.tprintf(
			"%s history has conflicting added states for entity %d %s %q at basis %d",
			backend,
			entity,
			attribute,
			value,
			basis,
		))
	}
	if !fact.seen || basis > fact.basis {
		fact^ = Model_History_Fact{seen = true, basis = basis, added = added}
	}
	return pbt.pass()
}

transaction_model_value_index :: proc(value: string, values: []string) -> int {
	for candidate, index in values {
		if candidate == value {
			return index
		}
	}
	return -1
}

transaction_model_tx_range_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Model_Context,
	connection: ^$Connection,
	checkpoint_basis: u64,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s transaction log", backend))
	}
	defer vev.close(&log_value)
	current_basis := ctx.transaction_basis[ctx.transaction_count - 1]
	transactions, range_ok := vev.tx_range_coordinates(
		&log_value,
		checkpoint_basis + 1,
		current_basis + 1,
	)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s transaction range failed", backend))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.kind(transactions_value) != .Vector {
		return pbt.error(fmt.tprintf("%s transaction range is not a vector", backend))
	}

	expected_transaction_count := ctx.transaction_count - ctx.suffix_tx_start
	if vev.item_count(transactions_value) != expected_transaction_count {
		return pbt.fail(fmt.tprintf(
			"%s transaction range count: expected=%d actual=%d",
			backend,
			expected_transaction_count,
			vev.item_count(transactions_value),
		))
	}
	matched_datoms: [MODEL_LOG_DATOM_COUNT]bool
	for transaction_index in 0 ..< expected_transaction_count {
		transaction, transaction_ok := vev.item(transactions_value, transaction_index)
		if !transaction_ok || vev.kind(transaction) != .Map {
			return pbt.error(fmt.tprintf("%s transaction %d is malformed", backend, transaction_index))
		}
		t_value, t_ok := vev.get(transaction, ":t")
		data, data_ok := vev.get(transaction, ":data")
		basis, basis_ok := vev.as_int(t_value)
		expected_basis := ctx.transaction_basis[ctx.suffix_tx_start + transaction_index]
		if !t_ok || !data_ok || !basis_ok || basis < 0 || u64(basis) != expected_basis ||
		   vev.kind(data) != .Vector {
			return pbt.fail(fmt.tprintf(
				"%s transaction %d coordinate: expected=%d actual=%d",
				backend,
				transaction_index,
				expected_basis,
				basis,
			))
		}

		actual_application_count := 0
		for datom_index in 0 ..< vev.item_count(data) {
			datom_value, datom_ok := vev.item(data, datom_index)
			if !datom_ok {
				return pbt.error(fmt.tprintf("%s transaction %d datom unavailable", backend, transaction_index))
			}
			actual, application_datom, parse_ok := transaction_model_log_datom_value(
				t,
				datom_value,
				expected_basis,
			)
			if !parse_ok {
				return pbt.error(fmt.tprintf("%s transaction %d has malformed datom", backend, transaction_index))
			}
			if !application_datom {
				continue
			}
			actual_application_count += 1
			matched := false
			for expected_index in ctx.suffix_datom_start ..< ctx.log_datom_count {
				expected := ctx.log_datoms[expected_index]
				if !matched_datoms[expected_index] &&
				   transaction_model_log_datoms_equal(actual, expected) {
					matched_datoms[expected_index] = true
					matched = true
					break
				}
			}
			if !matched {
				return pbt.fail(fmt.tprintf(
					"%s transaction %d has unexpected %s datom for entity %d at basis %d",
					backend,
					transaction_index,
					transaction_model_attribute_name(actual.attribute),
					actual.entity,
					actual.basis,
				))
			}
		}

		expected_application_count := 0
		for expected_index in ctx.suffix_datom_start ..< ctx.log_datom_count {
			if ctx.log_datoms[expected_index].basis == expected_basis {
				expected_application_count += 1
			}
		}
		if actual_application_count != expected_application_count {
			return pbt.fail(fmt.tprintf(
				"%s transaction %d application datoms: expected=%d actual=%d",
				backend,
				transaction_index,
				expected_application_count,
				actual_application_count,
			))
		}
	}

	for expected_index in ctx.suffix_datom_start ..< ctx.log_datom_count {
		if !matched_datoms[expected_index] {
			expected := ctx.log_datoms[expected_index]
			return pbt.fail(fmt.tprintf(
				"%s transaction range omitted %s datom for entity %d at basis %d",
				backend,
				transaction_model_attribute_name(expected.attribute),
				expected.entity,
				expected.basis,
			))
		}
	}
	return pbt.pass()
}

transaction_model_log_datom_value :: proc(
	t: ^pbt.T,
	value: vev.Value,
	expected_basis: u64,
) -> (datom: Model_Log_Datom, application: bool, ok: bool) {
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
	if attribute != ":item/name" && attribute != ":item/tags" {
		return {}, false, true
	}
	entity, entity_value_ok := vev.as_entity(entity_value)
	fact, fact_string_ok := vev.as_string(fact_value, t.value_allocator)
	tx, tx_entity_ok := vev.as_entity(tx_value)
	added, added_bool_ok := vev.as_bool(added_value)
	if !entity_value_ok || !fact_string_ok || !tx_entity_ok || !added_bool_ok ||
	   entity < 1 || entity > MODEL_ENTITY_COUNT || tx != vev.t_to_tx(expected_basis) {
		return {}, true, false
	}
	if attribute == ":item/name" {
		value_index := transaction_model_value_index(fact, MODEL_NAMES[:])
		if value_index < 0 {
			return {}, true, false
		}
		return Model_Log_Datom{
			entity = int(entity),
			attribute = .Name,
			value_index = value_index,
			basis = expected_basis,
			added = added,
		}, true, true
	}
	value_index := transaction_model_value_index(fact, MODEL_TAGS[:])
	if value_index < 0 {
		return {}, true, false
	}
	return Model_Log_Datom{
		entity = int(entity),
		attribute = .Tag,
		value_index = value_index,
		basis = expected_basis,
		added = added,
	}, true, true
}

transaction_model_log_datoms_equal :: proc(left, right: Model_Log_Datom) -> bool {
	return left.entity == right.entity &&
	       left.attribute == right.attribute &&
	       left.value_index == right.value_index &&
	       left.basis == right.basis &&
	       left.added == right.added
}

transaction_model_attribute_name :: proc(attribute: Model_Attribute) -> string {
	switch attribute {
	case .Name:
		return "name"
	case .Tag:
		return "tag"
	}
	return "unknown"
}

transaction_model_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Model_Context) -> pbt.Result {
	basis_before, basis_before_ok := vev.connection_basis_t(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read durable coordinates before reopen")
	}

	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		error_text := vev.connection_error(&ctx.durable, t.value_allocator)
		vev.close(&ctx.durable)
		return pbt.error(fmt.tprintf("could not reopen durable transaction-model store: %s", error_text))
	}

	basis_after, basis_after_ok := vev.connection_basis_t(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok {
		return pbt.error("could not read durable coordinates after reopen")
	}
	if basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"durable coordinates changed across reopen: basis %d -> %d, count %d -> %d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}

	pbt.record_event(t, "durable", "reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d",
		basis_after,
		count_after,
	))
	final_state := Model_State{
		ctx = ctx,
		names = ctx.final_names,
		tags = ctx.final_tags,
	}
	return transaction_model_invariant(t, final_state)
}

transaction_model_temp_path :: proc(t: ^pbt.T) -> (path: string, ok: bool) {
	file, create_error := os.create_temp_file("", "vev-pbt-*.sqlite")
	if create_error != nil {
		return "", false
	}
	path = strings.clone(os.name(file), t.value_allocator)
	close_error := os.close(file)
	if close_error != nil {
		_ = os.remove(path)
		return "", false
	}
	remove_error := os.remove(path)
	return path, remove_error == nil
}

transaction_model_remove_store :: proc(path: string) {
	_ = os.remove(path)
	_ = os.remove(fmt.tprintf("%s-wal", path))
	_ = os.remove(fmt.tprintf("%s-shm", path))
}

transaction_model_initial :: proc(t: ^pbt.T, target: rawptr) -> Model_State {
	ctx := cast(^Model_Context)target
	return Model_State{
		ctx = ctx,
		names = ctx.final_names,
		tags = ctx.final_tags,
	}
}

transaction_model_command :: proc(t: ^pbt.T, state: Model_State) -> Model_Command {
	kind := Model_Command_Kind(pbt.draw(t, pbt.int_range(0, int(Model_Command_Kind.Retract_Entity))))
	command := Model_Command{
		kind = kind,
		entity = pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT)),
	}
	if kind == .Add_Name || kind == .Add_Tag ||
	   kind == .Retract_Name || kind == .Retract_Tag {
		command.value_index = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	}
	pbt.classify(t, true, transaction_model_command_name(command))
	return command
}

transaction_model_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: Model_State,
	command: Model_Command,
) -> Model_Observation {
	ctx := cast(^Model_Context)target
	tx := transaction_model_command_edn(command)
	report, ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	observation := Model_Observation{ok = ok, report = report, durable_ok = true}
	if ctx.compare_durable {
		observation.durable_report, observation.durable_ok = vev.transact(
			&ctx.durable,
			tx,
			t.value_allocator,
		)
	}
	if ctx.track_log && observation.ok {
		database, database_ok := vev.db(&ctx.connection)
		if database_ok {
			observation.basis, observation.basis_ok = vev.basis_t(&database)
			vev.close(&database)
		}
		if ctx.compare_durable && observation.durable_ok {
			durable_database, durable_database_ok := vev.db(&ctx.durable)
			if durable_database_ok {
				observation.durable_basis, observation.durable_basis_ok = vev.basis_t(&durable_database)
				vev.close(&durable_database)
			}
		}
	}
	pbt.note(t, fmt.tprintf(
		"command=%s tx=%s resident=%s durable=%s",
		transaction_model_command_name(command),
		tx,
		report,
		observation.durable_report,
	))
	return observation
}

transaction_model_command_edn :: proc(command: Model_Command) -> string {
	switch command.kind {
	case .Add_Name:
		return fmt.tprintf(
			`[[:db/add %d :item/name "%s"]]`,
			command.entity,
			MODEL_NAMES[command.value_index],
		)
	case .Add_Tag:
		return fmt.tprintf(
			`[[:db/add %d :item/tags "%s"]]`,
			command.entity,
			MODEL_TAGS[command.value_index],
		)
	case .Retract_Name:
		return fmt.tprintf(
			`[[:db/retract %d :item/name "%s"]]`,
			command.entity,
			MODEL_NAMES[command.value_index],
		)
	case .Retract_Tag:
		return fmt.tprintf(
			`[[:db/retract %d :item/tags "%s"]]`,
			command.entity,
			MODEL_TAGS[command.value_index],
		)
	case .Retract_Name_Attribute:
		return fmt.tprintf(`[[:db.fn/retractAttribute %d :item/name]]`, command.entity)
	case .Retract_Tags_Attribute:
		return fmt.tprintf(`[[:db.fn/retractAttribute %d :item/tags]]`, command.entity)
	case .Retract_Entity:
		return fmt.tprintf(`[[:db/retractEntity %d]]`, command.entity)
	}
	return "[]"
}

transaction_model_next_state :: proc(
	state: Model_State,
	command: Model_Command,
	observation: Model_Observation,
) -> Model_State {
	if !observation.ok {
		return state
	}
	next := state
	if next.ctx.track_log {
		transaction_model_record_log(next.ctx, state, command, observation)
	}
	if next.ctx.track_since {
		transaction_model_update_since(next.ctx, state, command)
	}
	entity_index := command.entity - 1
	switch command.kind {
	case .Add_Name:
		next.names[entity_index] = command.value_index + 1
	case .Add_Tag:
		next.tags[entity_index][command.value_index] = true
	case .Retract_Name:
		if next.names[entity_index] == command.value_index + 1 {
			next.names[entity_index] = 0
		}
	case .Retract_Tag:
		next.tags[entity_index][command.value_index] = false
	case .Retract_Name_Attribute:
		next.names[entity_index] = 0
	case .Retract_Tags_Attribute:
		next.tags[entity_index] = {}
	case .Retract_Entity:
		next.names[entity_index] = 0
		next.tags[entity_index] = {}
	}
	next.ctx.final_names = next.names
	next.ctx.final_tags = next.tags
	return next
}

transaction_model_record_log :: proc(
	ctx: ^Model_Context,
	state: Model_State,
	command: Model_Command,
	observation: Model_Observation,
) {
	ctx.transaction_basis[ctx.transaction_count] = observation.basis
	ctx.transaction_count += 1
	entity_index := command.entity - 1
	switch command.kind {
	case .Add_Name:
		next_name := command.value_index + 1
		if state.names[entity_index] != next_name {
			if state.names[entity_index] != 0 {
				transaction_model_record_log_datom(
					ctx,
					command.entity,
					.Name,
					state.names[entity_index] - 1,
					observation.basis,
					false,
				)
			}
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Name,
				command.value_index,
				observation.basis,
				true,
			)
		}
	case .Add_Tag:
		if !state.tags[entity_index][command.value_index] {
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Tag,
				command.value_index,
				observation.basis,
				true,
			)
		}
	case .Retract_Name:
		if state.names[entity_index] == command.value_index + 1 {
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Name,
				command.value_index,
				observation.basis,
				false,
			)
		}
	case .Retract_Tag:
		if state.tags[entity_index][command.value_index] {
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Tag,
				command.value_index,
				observation.basis,
				false,
			)
		}
	case .Retract_Name_Attribute:
		if state.names[entity_index] != 0 {
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Name,
				state.names[entity_index] - 1,
				observation.basis,
				false,
			)
		}
	case .Retract_Tags_Attribute:
		for value_index in 0 ..< MODEL_VALUE_COUNT {
			if state.tags[entity_index][value_index] {
				transaction_model_record_log_datom(
					ctx,
					command.entity,
					.Tag,
					value_index,
					observation.basis,
					false,
				)
			}
		}
	case .Retract_Entity:
		if state.names[entity_index] != 0 {
			transaction_model_record_log_datom(
				ctx,
				command.entity,
				.Name,
				state.names[entity_index] - 1,
				observation.basis,
				false,
			)
		}
		for value_index in 0 ..< MODEL_VALUE_COUNT {
			if state.tags[entity_index][value_index] {
				transaction_model_record_log_datom(
					ctx,
					command.entity,
					.Tag,
					value_index,
					observation.basis,
					false,
				)
			}
		}
	}
}

transaction_model_record_log_datom :: proc(
	ctx: ^Model_Context,
	entity: int,
	attribute: Model_Attribute,
	value_index: int,
	basis: u64,
	added: bool,
) {
	ctx.log_datoms[ctx.log_datom_count] = Model_Log_Datom{
		entity = entity,
		attribute = attribute,
		value_index = value_index,
		basis = basis,
		added = added,
	}
	ctx.log_datom_count += 1
}

transaction_model_update_since :: proc(
	ctx: ^Model_Context,
	state: Model_State,
	command: Model_Command,
) {
	entity_index := command.entity - 1
	switch command.kind {
	case .Add_Name:
		next_name := command.value_index + 1
		if state.names[entity_index] != next_name {
			ctx.since_names[entity_index] = next_name
		}
	case .Add_Tag:
		if !state.tags[entity_index][command.value_index] {
			ctx.since_tags[entity_index][command.value_index] = true
		}
	case .Retract_Name:
		if state.names[entity_index] == command.value_index + 1 {
			ctx.since_names[entity_index] = 0
		}
	case .Retract_Tag:
		if state.tags[entity_index][command.value_index] {
			ctx.since_tags[entity_index][command.value_index] = false
		}
	case .Retract_Name_Attribute:
		ctx.since_names[entity_index] = 0
	case .Retract_Tags_Attribute:
		ctx.since_tags[entity_index] = {}
	case .Retract_Entity:
		ctx.since_names[entity_index] = 0
		ctx.since_tags[entity_index] = {}
	}
}

transaction_model_postcondition :: proc(
	state: Model_State,
	command: Model_Command,
	observation: Model_Observation,
) -> pbt.Result {
	if !observation.ok {
		return pbt.error(fmt.tprintf(
			"%s failed for entity %d: %s",
			transaction_model_command_name(command),
			command.entity,
			observation.report,
		))
	}
	if !observation.durable_ok {
		return pbt.error(fmt.tprintf(
			"durable %s failed for entity %d: %s",
			transaction_model_command_name(command),
			command.entity,
			observation.durable_report,
		))
	}
	if state.ctx.track_log && (!observation.basis_ok || !observation.durable_basis_ok) {
		return pbt.error("could not read transaction coordinates for log model")
	}
	if state.ctx.track_log && observation.basis != observation.durable_basis {
		return pbt.fail(fmt.tprintf(
			"transaction basis differs: resident=%d durable=%d",
			observation.basis,
			observation.durable_basis,
		))
	}
	return pbt.pass()
}

transaction_model_invariant :: proc(t: ^pbt.T, state: Model_State) -> pbt.Result {
	database, db_ok := vev.db(&state.ctx.connection)
	if !db_ok {
		return pbt.error("could not retain database while checking transaction model")
	}
	defer vev.close(&database)
	if result := transaction_model_database_invariant(t, state, &database, "resident"); result.status != .Pass {
		return result
	}

	if state.ctx.compare_durable {
		durable_db, durable_db_ok := vev.db(&state.ctx.durable)
		if !durable_db_ok {
			return pbt.error("could not retain durable database while checking transaction model")
		}
		defer vev.close(&durable_db)
		return transaction_model_database_invariant(t, state, &durable_db, "durable")
	}
	return pbt.pass()
}

transaction_model_database_invariant :: proc(
	t: ^pbt.T,
	state: Model_State,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	if result := transaction_model_names_invariant(t, state, database, backend); result.status != .Pass {
		return result
	}
	return transaction_model_tags_invariant(t, state, database, backend)
}

transaction_model_names_invariant :: proc(
	t: ^pbt.T,
	state: Model_State,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	result, query_ok := vev.query(database, `[:find ?e ?name :where [?e :item/name ?name]]`)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s names relation query failed", backend))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s names relation value unavailable", backend))
	}

	expected_count := 0
	for expected in state.names {
		if expected != 0 {
			expected_count += 1
		}
	}
	if vev.item_count(relation) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s names count: model=%d Vev=%d",
			backend,
			expected_count,
			vev.item_count(relation),
		))
	}

	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		if !row_ok || vev.item_count(row) != 2 {
			return pbt.error(fmt.tprintf("%s names row %d is malformed", backend, row_index))
		}
		entity_value, entity_ok := vev.item(row, 0)
		name_value, name_ok := vev.item(row, 1)
		entity, entity_int_ok := vev.as_int(entity_value)
		name, name_string_ok := vev.as_string(name_value, t.value_allocator)
		if !entity_ok || !name_ok || !entity_int_ok || !name_string_ok ||
		   entity < 1 || entity > MODEL_ENTITY_COUNT {
			return pbt.error(fmt.tprintf("%s names row %d has unexpected types", backend, row_index))
		}
		expected_index := state.names[entity - 1]
		if expected_index == 0 || MODEL_NAMES[expected_index - 1] != name {
			return pbt.fail(fmt.tprintf(
				"%s entity %d: unexpected name %q",
				backend,
				entity,
				name,
			))
		}
	}
	return pbt.pass()
}

transaction_model_tags_invariant :: proc(
	t: ^pbt.T,
	state: Model_State,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	result, query_ok := vev.query(database, `[:find ?e ?tag :where [?e :item/tags ?tag]]`)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s tags relation query failed", backend))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s tags relation value unavailable", backend))
	}

	expected_count := 0
	for entity_tags in state.tags {
		for expected in entity_tags {
			if expected {
				expected_count += 1
			}
		}
	}
	if vev.item_count(relation) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s tags count: model=%d Vev=%d",
			backend,
			expected_count,
			vev.item_count(relation),
		))
	}

	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		if !row_ok || vev.item_count(row) != 2 {
			return pbt.error(fmt.tprintf("%s tags row %d is malformed", backend, row_index))
		}
		entity_value, entity_ok := vev.item(row, 0)
		tag_value, tag_ok := vev.item(row, 1)
		entity, entity_int_ok := vev.as_int(entity_value)
		tag, tag_string_ok := vev.as_string(tag_value, t.value_allocator)
		if !entity_ok || !tag_ok || !entity_int_ok || !tag_string_ok ||
		   entity < 1 || entity > MODEL_ENTITY_COUNT {
			return pbt.error(fmt.tprintf("%s tags row %d has unexpected types", backend, row_index))
		}
		tag_index := transaction_model_tag_index(tag)
		if tag_index < 0 || !state.tags[entity - 1][tag_index] {
			return pbt.fail(fmt.tprintf(
				"%s entity %d: unexpected tag %q",
				backend,
				entity,
				tag,
			))
		}
	}
	return pbt.pass()
}

transaction_model_tag_index :: proc(tag: string) -> int {
	for candidate, index in MODEL_TAGS {
		if candidate == tag {
			return index
		}
	}
	return -1
}

transaction_model_command_name :: proc(command: Model_Command) -> string {
	switch command.kind {
	case .Add_Name:
		return "add-name"
	case .Add_Tag:
		return "add-tag"
	case .Retract_Name:
		return "retract-name"
	case .Retract_Tag:
		return "retract-tag"
	case .Retract_Name_Attribute:
		return "retract-name-attribute"
	case .Retract_Tags_Attribute:
		return "retract-tags-attribute"
	case .Retract_Entity:
		return "retract-entity"
	}
	return "unknown"
}

transaction_model_state_detail :: proc(state: Model_State) -> string {
	name_count := 0
	tag_count := 0
	for entity_index in 0 ..< MODEL_ENTITY_COUNT {
		if state.names[entity_index] != 0 {
			name_count += 1
		}
		for tag_index in 0 ..< MODEL_VALUE_COUNT {
			if state.tags[entity_index][tag_index] {
				tag_count += 1
			}
		}
	}
	return fmt.tprintf("names=%d tags=%d", name_count, tag_count)
}

transaction_model_value_detail :: proc(observation: Model_Observation) -> string {
	if observation.ok {
		return "transaction-ok"
	}
	return observation.report
}
