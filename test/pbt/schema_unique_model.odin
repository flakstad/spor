package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

SCHEMA_UNIQUE_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "schema", "unique", "rollback", "model", "durable", "differential", "log", "reopen"}
SCHEMA_UNIQUE_COMMAND_COUNT :: 12
SCHEMA_UNIQUE_LOG_DATOM_COUNT :: SCHEMA_UNIQUE_COMMAND_COUNT * 2

SCHEMA_UNIQUE_SCHEMA :: `[
	{:db/id 100 :db/ident :schema/email :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :schema/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Schema_Unique_State :: enum {
	Duplicates,
	Distinct,
	Unique_Value,
	Unique_Identity,
}

Schema_Unique_Event :: enum {
	Make_Distinct,
	Make_Duplicate,
	Enable_Value,
	Enable_Identity,
	Attempt_Enable_Value,
	Attempt_Enable_Identity,
	Disable_Value,
	Disable_Identity,
	Switch_To_Value,
	Switch_To_Identity,
	Attempt_Duplicate_Value,
	Attempt_Duplicate_Identity,
}

Schema_Unique_Attribute :: enum {
	Email,
	Unique,
}

Schema_Unique_Log_Datom :: struct {
	entity:    u64,
	attribute: Schema_Unique_Attribute,
	value:     int,
	basis:     u64,
	added:     bool,
}

Schema_Unique_Observation :: struct {
	resident_report:       string,
	durable_report:        string,
	resident_call_ok:      bool,
	resident_committed:    bool,
	durable_committed:     bool,
	coordinates_ok:        bool,
	resident_basis_before: u64,
	resident_basis_after:  u64,
	durable_basis_before:  u64,
	durable_basis_after:   u64,
	durable_count_before:  u64,
	durable_count_after:   u64,
	model_state:           Schema_Unique_State,
}

Schema_Unique_Context :: struct {
	chart:             sc.Chart(Schema_Unique_State, Schema_Unique_Event),
	model:             sc.Instance(Schema_Unique_State, Schema_Unique_Event),
	connection:        vev.Connection,
	durable:           vev.Durable_Connection,
	durable_path:      string,
	email_a:           string,
	email_b:           string,
	transaction_basis: [SCHEMA_UNIQUE_COMMAND_COUNT]u64,
	transaction_count: int,
	log_datoms:        [SCHEMA_UNIQUE_LOG_DATOM_COUNT]Schema_Unique_Log_Datom,
	log_datom_count:   int,
}

SCHEMA_UNIQUE_STATES := [?]sc.State_Def(Schema_Unique_State) {
	{id = .Duplicates},
	{id = .Distinct},
	{id = .Unique_Value},
	{id = .Unique_Identity},
}

SCHEMA_UNIQUE_TRANSITIONS := [?]sc.Transition_Def(Schema_Unique_State, Schema_Unique_Event) {
	{source = .Duplicates, target = .Distinct, trigger = .Make_Distinct},
	{source = .Duplicates, target = .Duplicates, trigger = .Attempt_Enable_Value},
	{source = .Duplicates, target = .Duplicates, trigger = .Attempt_Enable_Identity},
	{source = .Distinct, target = .Duplicates, trigger = .Make_Duplicate},
	{source = .Distinct, target = .Unique_Value, trigger = .Enable_Value},
	{source = .Distinct, target = .Unique_Identity, trigger = .Enable_Identity},
	{source = .Unique_Value, target = .Distinct, trigger = .Disable_Value},
	{source = .Unique_Value, target = .Unique_Identity, trigger = .Switch_To_Identity},
	{source = .Unique_Value, target = .Unique_Value, trigger = .Attempt_Duplicate_Value},
	{source = .Unique_Identity, target = .Distinct, trigger = .Disable_Identity},
	{source = .Unique_Identity, target = .Unique_Value, trigger = .Switch_To_Value},
	{source = .Unique_Identity, target = .Unique_Identity, trigger = .Attempt_Duplicate_Identity},
}

schema_unique_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Schema_Unique_Context
	if !schema_unique_statechart_init(&ctx) {
		return pbt.error("could not initialize unique-schema statechart")
	}
	defer schema_unique_statechart_destroy(&ctx)
	stem := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))
	ctx.email_a = fmt.tprintf("%s-a@example.com", stem)
	ctx.email_b = fmt.tprintf("%s-b@example.com", stem)

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create unique-schema resident connection")
	}
	defer vev.close(&ctx.connection)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate unique-schema durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create unique-schema durable connection")
	}
	defer vev.close(&ctx.durable)

	seed := fmt.tprintf(
		`[[:db/add 1 :schema/email "%s"] [:db/add 2 :schema/email "%s"]]`,
		ctx.email_a,
		ctx.email_a,
	)
	setup_transactions := [?]string{SCHEMA_UNIQUE_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize unique-schema backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish unique-schema checkpoint")
	}

	model := pbt.State_Model(^Schema_Unique_Context, Schema_Unique_Event, Schema_Unique_Observation) {
		target = &ctx,
		initial = schema_unique_initial,
		command = schema_unique_command,
		run = schema_unique_run,
		next_state = schema_unique_next_state,
		postcondition = schema_unique_postcondition,
		invariant = schema_unique_invariant,
		command_name = schema_unique_event_name,
		state_detail = schema_unique_state_detail,
		value_detail = schema_unique_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = SCHEMA_UNIQUE_COMMAND_COUNT,
		max_success_events = SCHEMA_UNIQUE_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := schema_unique_log_invariant(t, &ctx, &ctx.connection, resident_checkpoint, "resident unique-schema"); result.status != .Pass {
		return result
	}
	if result := schema_unique_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable unique-schema"); result.status != .Pass {
		return result
	}
	if result := schema_unique_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return schema_unique_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened unique-schema")
}

schema_unique_statechart_init :: proc(ctx: ^Schema_Unique_Context) -> bool {
	definition := sc.Chart_Def(Schema_Unique_State, Schema_Unique_Event) {
		initial = .Duplicates,
		states = SCHEMA_UNIQUE_STATES[:],
		transitions = SCHEMA_UNIQUE_TRANSITIONS[:],
	}
	compile_result := sc.compile(&ctx.chart, definition)
	defer sc.destroy_compile_result(&compile_result)
	if !compile_result.ok {
		return false
	}
	if !sc.init(&ctx.model, &ctx.chart) {
		sc.destroy_chart(&ctx.chart)
		return false
	}
	initial := sc.enter_initial(&ctx.model)
	defer sc.destroy_dispatch_result(&initial)
	if initial.status != .Transitioned {
		sc.destroy_instance(&ctx.model)
		sc.destroy_chart(&ctx.chart)
		return false
	}
	return true
}

schema_unique_statechart_destroy :: proc(ctx: ^Schema_Unique_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

schema_unique_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Schema_Unique_Context {
	return cast(^Schema_Unique_Context)target
}

schema_unique_command :: proc(t: ^pbt.T, state: ^Schema_Unique_Context) -> Schema_Unique_Event {
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Schema_Unique_Event.Make_Distinct)
	pbt.cover(t, event == .Make_Distinct, 20, "schema-make-distinct")
	pbt.cover(t, event == .Make_Duplicate, 8, "schema-make-duplicate")
	pbt.cover(t, event == .Enable_Value, 8, "schema-enable-value")
	pbt.cover(t, event == .Enable_Identity, 8, "schema-enable-identity")
	pbt.cover(t, event == .Attempt_Enable_Value, 15, "schema-reject-value-on-duplicates")
	pbt.cover(t, event == .Attempt_Enable_Identity, 15, "schema-reject-identity-on-duplicates")
	pbt.cover(t, event == .Disable_Value || event == .Disable_Identity, 10, "schema-disable-unique")
	pbt.cover(t, event == .Switch_To_Value || event == .Switch_To_Identity, 8, "schema-switch-unique-kind")
	pbt.cover(t, event == .Attempt_Duplicate_Value, 5, "schema-reject-unique-value-duplicate")
	pbt.cover(t, event == .Attempt_Duplicate_Identity, 5, "schema-reject-identity-duplicate")
	return event
}

schema_unique_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Schema_Unique_Context,
	event: Schema_Unique_Event,
) -> Schema_Unique_Observation {
	ctx := cast(^Schema_Unique_Context)target
	before_state := schema_unique_model_state(ctx)
	tx := schema_unique_event_tx(ctx, event)
	expected_commit := schema_unique_event_commits(event)
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, schema_unique_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"unique-schema state=%v event=%s expected-commit=%v tx=%s resident=%s durable=%s",
		before_state,
		schema_unique_event_name(event),
		expected_commit,
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && expected_commit && resident_committed && durable_committed {
		schema_unique_record_transaction(ctx, event, resident_after)
	}
	return Schema_Unique_Observation {
		resident_report = resident_report,
		durable_report = durable_report,
		resident_call_ok = resident_call_ok,
		resident_committed = resident_committed,
		durable_committed = durable_committed,
		coordinates_ok = resident_before_ok && resident_after_ok && durable_before_ok &&
		                 durable_after_ok && count_before_ok && count_after_ok &&
		                 dispatch.status == .Transitioned,
		resident_basis_before = resident_before,
		resident_basis_after = resident_after,
		durable_basis_before = durable_before,
		durable_basis_after = durable_after,
		durable_count_before = count_before,
		durable_count_after = count_after,
		model_state = schema_unique_model_state(ctx),
	}
}

schema_unique_next_state :: proc(
	state: ^Schema_Unique_Context,
	event: Schema_Unique_Event,
	observation: Schema_Unique_Observation,
) -> ^Schema_Unique_Context {
	return state
}

schema_unique_postcondition :: proc(
	state: ^Schema_Unique_Context,
	event: Schema_Unique_Event,
	observation: Schema_Unique_Observation,
) -> pbt.Result {
	expected_commit := schema_unique_event_commits(event)
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident did not return a report for %s", schema_unique_event_name(event)))
	}
	if observation.resident_committed != expected_commit || observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"unique-schema %s commit mismatch: expected=%v resident=%v durable=%v",
			schema_unique_event_name(event),
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("unique-schema %s coordinates unavailable", schema_unique_event_name(event)))
	}
	delta := u64(0)
	if expected_commit {
		delta = 1
	}
	if observation.resident_basis_after != observation.resident_basis_before + delta ||
	   observation.durable_basis_after != observation.durable_basis_before + delta ||
	   observation.durable_count_after != observation.durable_count_before + delta ||
	   observation.resident_basis_after != observation.durable_basis_after {
		return pbt.fail(fmt.tprintf(
			"unique-schema %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			schema_unique_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if !expected_commit {
		expected_error := schema_unique_event_error(event)
		if !strings.contains(observation.resident_report, expected_error) ||
		   !strings.contains(observation.durable_report, expected_error) {
			return pbt.fail(fmt.tprintf(
				"unique-schema %s error mismatch: expected=%s resident=%s durable=%s",
				schema_unique_event_name(event),
				expected_error,
				observation.resident_report,
				observation.durable_report,
			))
		}
	}
	return pbt.pass()
}

schema_unique_invariant :: proc(t: ^pbt.T, state: ^Schema_Unique_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident unique-schema database")
	}
	defer vev.close(&resident)
	if result := schema_unique_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable unique-schema database")
	}
	defer vev.close(&durable)
	return schema_unique_database_invariant(t, state, &durable, "durable")
}

schema_unique_database_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Unique_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	state := schema_unique_model_state(ctx)
	emails, emails_ok := vev.query(database, `[:find ?e ?email :where [?e :schema/email ?email]]`)
	if !emails_ok {
		return pbt.error(fmt.tprintf("%s unique-schema email query failed", backend))
	}
	defer vev.close(&emails)
	emails_value, emails_value_ok := vev.value(&emails)
	if !emails_value_ok || vev.item_count(emails_value) != 2 {
		return pbt.fail(fmt.tprintf("%s unique-schema email count is not two", backend))
	}
	seen: [3]bool
	for row_index in 0 ..< vev.item_count(emails_value) {
		row, row_ok := vev.item(emails_value, row_index)
		entity_value, entity_ok := vev.item(row, 0)
		email_value, email_ok := vev.item(row, 1)
		entity, entity_value_ok := vev.as_int(entity_value)
		email, email_value_ok := vev.as_string(email_value, t.value_allocator)
		expected := ctx.email_a
		if state != .Duplicates && entity == 2 {
			expected = ctx.email_b
		}
		if !row_ok || !entity_ok || !email_ok || !entity_value_ok || !email_value_ok ||
		   entity < 1 || entity > 2 || seen[entity] || email != expected {
			return pbt.fail(fmt.tprintf(
				"%s unique-schema email mismatch: entity=%d value=%s state=%v",
				backend,
				entity,
				email,
				state,
			))
		}
		seen[entity] = true
	}
	if !seen[1] || !seen[2] {
		return pbt.fail(fmt.tprintf("%s unique-schema email entity missing", backend))
	}
	unique_result, unique_ok := vev.query(database, `[:find ?kind . :where [100 :db/unique ?kind]]`)
	if !unique_ok {
		return pbt.error(fmt.tprintf("%s unique-schema kind query failed", backend))
	}
	defer vev.close(&unique_result)
	unique_value, unique_value_ok := vev.value(&unique_result)
	expected_kind := schema_unique_state_kind(state)
	if expected_kind == "" {
		if !unique_value_ok || vev.kind(unique_value) != .Nil {
			return pbt.fail(fmt.tprintf("%s unique-schema kind should be absent", backend))
		}
	} else {
		actual_kind, actual_kind_ok := vev.as_string(unique_value, t.value_allocator)
		if !unique_value_ok || !actual_kind_ok || actual_kind != expected_kind {
			return pbt.fail(fmt.tprintf(
				"%s unique-schema kind: expected=%s actual=%s",
				backend,
				expected_kind,
				actual_kind,
			))
		}
	}
	markers, markers_ok := vev.query(database, `[:find ?marker :where [3 :schema/marker ?marker]]`)
	if !markers_ok {
		return pbt.error(fmt.tprintf("%s unique-schema marker query failed", backend))
	}
	defer vev.close(&markers)
	markers_value, markers_value_ok := vev.value(&markers)
	if !markers_value_ok || vev.item_count(markers_value) != 0 {
		return pbt.fail(fmt.tprintf("%s unique-schema rollback marker survived", backend))
	}
	return pbt.pass()
}

schema_unique_event_tx :: proc(ctx: ^Schema_Unique_Context, event: Schema_Unique_Event) -> string {
	switch event {
	case .Make_Distinct:
		return fmt.tprintf(`[[:db/add 2 :schema/email "%s"]]`, ctx.email_b)
	case .Make_Duplicate:
		return fmt.tprintf(`[[:db/add 2 :schema/email "%s"]]`, ctx.email_a)
	case .Enable_Value:
		return `[[:db/add 100 :db/unique :db.unique/value]]`
	case .Enable_Identity:
		return `[[:db/add 100 :db/unique :db.unique/identity]]`
	case .Attempt_Enable_Value:
		return `[[:db/add 3 :schema/marker "must-rollback"] [:db/add 100 :db/unique :db.unique/value]]`
	case .Attempt_Enable_Identity:
		return `[[:db/add 3 :schema/marker "must-rollback"] [:db/add 100 :db/unique :db.unique/identity]]`
	case .Disable_Value:
		return `[[:db/retract 100 :db/unique :db.unique/value]]`
	case .Disable_Identity:
		return `[[:db/retract 100 :db/unique :db.unique/identity]]`
	case .Switch_To_Value:
		return `[[:db/add 100 :db/unique :db.unique/value]]`
	case .Switch_To_Identity:
		return `[[:db/add 100 :db/unique :db.unique/identity]]`
	case .Attempt_Duplicate_Value, .Attempt_Duplicate_Identity:
		return fmt.tprintf(
			`[[:db/add 3 :schema/marker "must-rollback"] [:db/add 2 :schema/email "%s"]]`,
			ctx.email_a,
		)
	}
	return "[]"
}

schema_unique_event_commits :: proc(event: Schema_Unique_Event) -> bool {
	switch event {
	case .Attempt_Enable_Value, .Attempt_Enable_Identity,
	     .Attempt_Duplicate_Value, .Attempt_Duplicate_Identity:
		return false
	case .Make_Distinct, .Make_Duplicate, .Enable_Value, .Enable_Identity,
	     .Disable_Value, .Disable_Identity, .Switch_To_Value, .Switch_To_Identity:
		return true
	}
	return false
}

schema_unique_event_error :: proc(event: Schema_Unique_Event) -> string {
	if event == .Attempt_Duplicate_Identity {
		return "conflicting upsert"
	}
	return "schema unique conflict"
}

schema_unique_record_transaction :: proc(
	ctx: ^Schema_Unique_Context,
	event: Schema_Unique_Event,
	basis: u64,
) {
	ctx.transaction_basis[ctx.transaction_count] = basis
	ctx.transaction_count += 1
	switch event {
	case .Make_Distinct:
		schema_unique_record_email(ctx, 0, basis, false)
		schema_unique_record_email(ctx, 1, basis, true)
	case .Make_Duplicate:
		schema_unique_record_email(ctx, 1, basis, false)
		schema_unique_record_email(ctx, 0, basis, true)
	case .Enable_Value:
		schema_unique_record_kind(ctx, 0, basis, true)
	case .Enable_Identity:
		schema_unique_record_kind(ctx, 1, basis, true)
	case .Disable_Value:
		schema_unique_record_kind(ctx, 0, basis, false)
	case .Disable_Identity:
		schema_unique_record_kind(ctx, 1, basis, false)
	case .Switch_To_Value:
		schema_unique_record_kind(ctx, 1, basis, false)
		schema_unique_record_kind(ctx, 0, basis, true)
	case .Switch_To_Identity:
		schema_unique_record_kind(ctx, 0, basis, false)
		schema_unique_record_kind(ctx, 1, basis, true)
	case .Attempt_Enable_Value, .Attempt_Enable_Identity,
	     .Attempt_Duplicate_Value, .Attempt_Duplicate_Identity:
	}
}

schema_unique_record_email :: proc(ctx: ^Schema_Unique_Context, value: int, basis: u64, added: bool) {
	ctx.log_datoms[ctx.log_datom_count] = Schema_Unique_Log_Datom {
		entity = 2,
		attribute = .Email,
		value = value,
		basis = basis,
		added = added,
	}
	ctx.log_datom_count += 1
}

schema_unique_record_kind :: proc(ctx: ^Schema_Unique_Context, value: int, basis: u64, added: bool) {
	ctx.log_datoms[ctx.log_datom_count] = Schema_Unique_Log_Datom {
		entity = 100,
		attribute = .Unique,
		value = value,
		basis = basis,
		added = added,
	}
	ctx.log_datom_count += 1
}

schema_unique_log_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Unique_Context,
	connection: ^$Connection,
	checkpoint: u64,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s log", backend))
	}
	defer vev.close(&log_value)
	current_basis := checkpoint
	if ctx.transaction_count > 0 {
		current_basis = ctx.transaction_basis[ctx.transaction_count - 1]
	}
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, current_basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s log range failed", backend))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != ctx.transaction_count {
		return pbt.fail(fmt.tprintf(
			"%s transaction count: expected=%d actual=%d",
			backend,
			ctx.transaction_count,
			vev.item_count(transactions_value),
		))
	}
	matched: [SCHEMA_UNIQUE_LOG_DATOM_COUNT]bool
	for transaction_index in 0 ..< ctx.transaction_count {
		transaction, transaction_ok := vev.item(transactions_value, transaction_index)
		t_value, t_ok := vev.get(transaction, ":t")
		data, data_ok := vev.get(transaction, ":data")
		basis, basis_ok := vev.as_int(t_value)
		expected_basis := ctx.transaction_basis[transaction_index]
		if !transaction_ok || !t_ok || !data_ok || !basis_ok || basis < 0 ||
		   u64(basis) != expected_basis || vev.kind(data) != .Vector {
			return pbt.error(fmt.tprintf("%s transaction %d is malformed", backend, transaction_index))
		}
		actual_count := 0
		for datom_index in 0 ..< vev.item_count(data) {
			value, datom_ok := vev.item(data, datom_index)
			actual, application, parse_ok := schema_unique_log_datom(t, ctx, value, expected_basis)
			if !datom_ok || !parse_ok {
				return pbt.error(fmt.tprintf("%s transaction %d has malformed datom", backend, transaction_index))
			}
			if !application {
				continue
			}
			actual_count += 1
			found := false
			for expected_index in 0 ..< ctx.log_datom_count {
				if !matched[expected_index] && schema_unique_log_equal(actual, ctx.log_datoms[expected_index]) {
					matched[expected_index] = true
					found = true
					break
				}
			}
			if !found {
				return pbt.fail(fmt.tprintf("%s transaction %d has unexpected schema datom", backend, transaction_index))
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
			return pbt.fail(fmt.tprintf("%s omitted unique-schema datom %d", backend, expected_index))
		}
	}
	return pbt.pass()
}

schema_unique_log_datom :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Unique_Context,
	value: vev.Value,
	basis: u64,
) -> (datom: Schema_Unique_Log_Datom, application, ok: bool) {
	if vev.kind(value) != .Vector || vev.item_count(value) != 5 {
		return {}, false, false
	}
	entity_value, entity_ok := vev.item(value, 0)
	attribute_value, attribute_ok := vev.item(value, 1)
	fact_value, fact_ok := vev.item(value, 2)
	tx_value, tx_ok := vev.item(value, 3)
	added_value, added_ok := vev.item(value, 4)
	attribute, attribute_value_ok := vev.as_string(attribute_value, t.value_allocator)
	if !entity_ok || !attribute_ok || !fact_ok || !tx_ok || !added_ok || !attribute_value_ok {
		return {}, false, false
	}
	if attribute != ":schema/email" && attribute != ":db/unique" {
		return {}, false, true
	}
	entity, entity_value_ok := vev.as_entity(entity_value)
	tx, tx_value_ok := vev.as_entity(tx_value)
	added, added_value_ok := vev.as_bool(added_value)
	if !entity_value_ok || !tx_value_ok || !added_value_ok || tx != vev.t_to_tx(basis) {
		return {}, true, false
	}
	if attribute == ":schema/email" {
		email, email_ok := vev.as_string(fact_value, t.value_allocator)
		email_index := -1
		if email == ctx.email_a {
			email_index = 0
		} else if email == ctx.email_b {
			email_index = 1
		}
		if !email_ok || entity != 2 || email_index < 0 {
			return {}, true, false
		}
		return Schema_Unique_Log_Datom {
			entity = entity,
			attribute = .Email,
			value = email_index,
			basis = basis,
			added = added,
		}, true, true
	}
	kind, kind_ok := vev.as_string(fact_value, t.value_allocator)
	kind_index := -1
	if kind == ":db.unique/value" {
		kind_index = 0
	} else if kind == ":db.unique/identity" {
		kind_index = 1
	}
	if !kind_ok || entity != 100 || kind_index < 0 {
		return {}, true, false
	}
	return Schema_Unique_Log_Datom {
		entity = entity,
		attribute = .Unique,
		value = kind_index,
		basis = basis,
		added = added,
	}, true, true
}

schema_unique_log_equal :: proc(left, right: Schema_Unique_Log_Datom) -> bool {
	return left.entity == right.entity && left.attribute == right.attribute &&
	       left.value == right.value && left.basis == right.basis && left.added == right.added
}

schema_unique_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Schema_Unique_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read unique-schema coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen unique-schema durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"unique-schema coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened unique-schema database")
	}
	defer vev.close(&database)
	if result := schema_unique_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "unique-schema-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		schema_unique_model_state(ctx),
	))
	return pbt.pass()
}

schema_unique_model_state :: proc(ctx: ^Schema_Unique_Context) -> Schema_Unique_State {
	if sc.is_active(&ctx.model, Schema_Unique_State.Distinct) {
		return .Distinct
	}
	if sc.is_active(&ctx.model, Schema_Unique_State.Unique_Value) {
		return .Unique_Value
	}
	if sc.is_active(&ctx.model, Schema_Unique_State.Unique_Identity) {
		return .Unique_Identity
	}
	return .Duplicates
}

schema_unique_state_kind :: proc(state: Schema_Unique_State) -> string {
	if state == .Unique_Value {
		return ":db.unique/value"
	}
	if state == .Unique_Identity {
		return ":db.unique/identity"
	}
	return ""
}

schema_unique_event_name :: proc(event: Schema_Unique_Event) -> string {
	switch event {
	case .Make_Distinct:
		return "make-distinct"
	case .Make_Duplicate:
		return "make-duplicate"
	case .Enable_Value:
		return "enable-value"
	case .Enable_Identity:
		return "enable-identity"
	case .Attempt_Enable_Value:
		return "reject-enable-value"
	case .Attempt_Enable_Identity:
		return "reject-enable-identity"
	case .Disable_Value:
		return "disable-value"
	case .Disable_Identity:
		return "disable-identity"
	case .Switch_To_Value:
		return "switch-to-value"
	case .Switch_To_Identity:
		return "switch-to-identity"
	case .Attempt_Duplicate_Value:
		return "reject-value-duplicate"
	case .Attempt_Duplicate_Identity:
		return "reject-identity-duplicate"
	}
	return "unknown"
}

schema_unique_state_detail :: proc(state: ^Schema_Unique_Context) -> string {
	return fmt.tprintf("state=%v committed=%d", schema_unique_model_state(state), state.transaction_count)
}

schema_unique_value_detail :: proc(observation: Schema_Unique_Observation) -> string {
	return fmt.tprintf(
		"state=%v resident=%v durable=%v basis=%d/%d",
		observation.model_state,
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
