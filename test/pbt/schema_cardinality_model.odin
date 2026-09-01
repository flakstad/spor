package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

SCHEMA_CARDINALITY_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "schema", "cardinality", "rollback", "model", "durable", "differential", "log", "reopen"}
SCHEMA_CARDINALITY_COMMAND_COUNT :: 12

SCHEMA_CARDINALITY_SCHEMA :: `[
	{:db/id 100 :db/ident :card/value :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :card/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Schema_Cardinality_State :: enum {
	One_A,
	One_B,
	One_AB,
	Many_A,
	Many_B,
	Many_AB,
}

Schema_Cardinality_Event :: enum {
	Switch_Many,
	Switch_One,
	Add_A,
	Add_B,
	Retract_A,
	Retract_B,
	Attempt_Invalid,
}

Schema_Cardinality_Observation :: struct {
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
}

Schema_Cardinality_Context :: struct {
	chart:               sc.Chart(Schema_Cardinality_State, Schema_Cardinality_Event),
	model:               sc.Instance(Schema_Cardinality_State, Schema_Cardinality_Event),
	connection:          vev.Connection,
	durable:             vev.Durable_Connection,
	durable_path:        string,
	value_a:             string,
	value_b:             string,
	successful_tx_count: int,
}

SCHEMA_CARDINALITY_STATES := [?]sc.State_Def(Schema_Cardinality_State) {
	{id = .One_A},
	{id = .One_B},
	{id = .One_AB},
	{id = .Many_A},
	{id = .Many_B},
	{id = .Many_AB},
}

SCHEMA_CARDINALITY_TRANSITIONS := [?]sc.Transition_Def(Schema_Cardinality_State, Schema_Cardinality_Event) {
	{source = .One_A, target = .Many_A, trigger = .Switch_Many},
	{source = .One_A, target = .One_A, trigger = .Add_A},
	{source = .One_A, target = .One_B, trigger = .Add_B},
	{source = .One_A, target = .One_A, trigger = .Attempt_Invalid},
	{source = .One_B, target = .Many_B, trigger = .Switch_Many},
	{source = .One_B, target = .One_A, trigger = .Add_A},
	{source = .One_B, target = .One_B, trigger = .Add_B},
	{source = .One_B, target = .One_B, trigger = .Attempt_Invalid},
	{source = .One_AB, target = .Many_AB, trigger = .Switch_Many},
	{source = .One_AB, target = .One_AB, trigger = .Add_A},
	{source = .One_AB, target = .One_AB, trigger = .Add_B},
	{source = .One_AB, target = .One_B, trigger = .Retract_A},
	{source = .One_AB, target = .One_A, trigger = .Retract_B},
	{source = .One_AB, target = .One_AB, trigger = .Attempt_Invalid},
	{source = .Many_A, target = .One_A, trigger = .Switch_One},
	{source = .Many_A, target = .Many_A, trigger = .Add_A},
	{source = .Many_A, target = .Many_AB, trigger = .Add_B},
	{source = .Many_A, target = .Many_A, trigger = .Attempt_Invalid},
	{source = .Many_B, target = .One_B, trigger = .Switch_One},
	{source = .Many_B, target = .Many_AB, trigger = .Add_A},
	{source = .Many_B, target = .Many_B, trigger = .Add_B},
	{source = .Many_B, target = .Many_B, trigger = .Attempt_Invalid},
	{source = .Many_AB, target = .One_AB, trigger = .Switch_One},
	{source = .Many_AB, target = .Many_AB, trigger = .Add_A},
	{source = .Many_AB, target = .Many_AB, trigger = .Add_B},
	{source = .Many_AB, target = .Many_B, trigger = .Retract_A},
	{source = .Many_AB, target = .Many_A, trigger = .Retract_B},
	{source = .Many_AB, target = .Many_AB, trigger = .Attempt_Invalid},
}

schema_cardinality_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Schema_Cardinality_Context
	if !schema_cardinality_statechart_init(&ctx) {
		return pbt.error("could not initialize cardinality-schema statechart")
	}
	defer schema_cardinality_statechart_destroy(&ctx)
	stem := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))
	ctx.value_a = fmt.tprintf("%s-a", stem)
	ctx.value_b = fmt.tprintf("%s-b", stem)

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create cardinality-schema resident connection")
	}
	defer vev.close(&ctx.connection)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate cardinality-schema durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create cardinality-schema durable connection")
	}
	defer vev.close(&ctx.durable)

	seed := fmt.tprintf(`[[:db/add 1 :card/value "%s"]]`, ctx.value_a)
	setup_transactions := [?]string{SCHEMA_CARDINALITY_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize cardinality-schema backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish cardinality-schema checkpoint")
	}

	model := pbt.State_Model(^Schema_Cardinality_Context, Schema_Cardinality_Event, Schema_Cardinality_Observation) {
		target = &ctx,
		initial = schema_cardinality_initial,
		command = schema_cardinality_command,
		run = schema_cardinality_run,
		next_state = schema_cardinality_next_state,
		postcondition = schema_cardinality_postcondition,
		invariant = schema_cardinality_invariant,
		command_name = schema_cardinality_event_name,
		state_detail = schema_cardinality_state_detail,
		value_detail = schema_cardinality_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = SCHEMA_CARDINALITY_COMMAND_COUNT,
		max_success_events = SCHEMA_CARDINALITY_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := schema_cardinality_log_count(t, &ctx, &ctx.connection, resident_checkpoint, "resident cardinality-schema"); result.status != .Pass {
		return result
	}
	if result := schema_cardinality_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable cardinality-schema"); result.status != .Pass {
		return result
	}
	if result := schema_cardinality_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return schema_cardinality_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened cardinality-schema")
}

schema_cardinality_statechart_init :: proc(ctx: ^Schema_Cardinality_Context) -> bool {
	definition := sc.Chart_Def(Schema_Cardinality_State, Schema_Cardinality_Event) {
		initial = .One_A,
		states = SCHEMA_CARDINALITY_STATES[:],
		transitions = SCHEMA_CARDINALITY_TRANSITIONS[:],
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

schema_cardinality_statechart_destroy :: proc(ctx: ^Schema_Cardinality_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

schema_cardinality_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Schema_Cardinality_Context {
	return cast(^Schema_Cardinality_Context)target
}

schema_cardinality_command :: proc(t: ^pbt.T, state: ^Schema_Cardinality_Context) -> Schema_Cardinality_Event {
	before := schema_cardinality_model_state(state)
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Schema_Cardinality_Event.Switch_Many)
	pbt.cover(t, event == .Switch_Many, 12, "cardinality-switch-many")
	pbt.cover(t, event == .Switch_One, 8, "cardinality-switch-one")
	pbt.cover(t, before == .Many_AB && event == .Switch_One, 3, "cardinality-many-pair-to-one")
	pbt.cover(t, (before == .One_A && event == .Add_B) || (before == .One_B && event == .Add_A), 8, "cardinality-one-replacement")
	pbt.cover(t, before == .One_AB && (event == .Add_A || event == .Add_B), 1, "cardinality-one-existing-pair-add")
	pbt.cover(t, (before == .Many_A && event == .Add_B) || (before == .Many_B && event == .Add_A), 8, "cardinality-many-add")
	pbt.cover(t, event == .Retract_A || event == .Retract_B, 8, "cardinality-retract")
	pbt.cover(t, event == .Attempt_Invalid, 20, "cardinality-invalid-rollback")
	return event
}

schema_cardinality_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Schema_Cardinality_Context,
	event: Schema_Cardinality_Event,
) -> Schema_Cardinality_Observation {
	ctx := cast(^Schema_Cardinality_Context)target
	before_state := schema_cardinality_model_state(ctx)
	tx := schema_cardinality_event_tx(ctx, event)
	expected_commit := event != .Attempt_Invalid
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, schema_cardinality_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"cardinality-schema state=%v event=%s expected-commit=%v tx=%s resident=%s durable=%s",
		before_state,
		schema_cardinality_event_name(event),
		expected_commit,
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && expected_commit && resident_committed && durable_committed {
		ctx.successful_tx_count += 1
	}
	return Schema_Cardinality_Observation {
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
	}
}

schema_cardinality_next_state :: proc(
	state: ^Schema_Cardinality_Context,
	event: Schema_Cardinality_Event,
	observation: Schema_Cardinality_Observation,
) -> ^Schema_Cardinality_Context {
	return state
}

schema_cardinality_postcondition :: proc(
	state: ^Schema_Cardinality_Context,
	event: Schema_Cardinality_Event,
	observation: Schema_Cardinality_Observation,
) -> pbt.Result {
	expected_commit := event != .Attempt_Invalid
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident did not return a report for %s", schema_cardinality_event_name(event)))
	}
	if observation.resident_committed != expected_commit || observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"cardinality-schema %s commit mismatch: expected=%v resident=%v durable=%v",
			schema_cardinality_event_name(event),
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("cardinality-schema %s coordinates unavailable", schema_cardinality_event_name(event)))
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
			"cardinality-schema %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			schema_cardinality_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if !expected_commit &&
	   (!strings.contains(observation.resident_report, "invalid schema keyword value") ||
	    !strings.contains(observation.durable_report, "invalid schema keyword value")) {
		return pbt.fail(fmt.tprintf(
			"cardinality-schema invalid error mismatch: resident=%s durable=%s",
			observation.resident_report,
			observation.durable_report,
		))
	}
	return pbt.pass()
}

schema_cardinality_invariant :: proc(t: ^pbt.T, state: ^Schema_Cardinality_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident cardinality-schema database")
	}
	defer vev.close(&resident)
	if result := schema_cardinality_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable cardinality-schema database")
	}
	defer vev.close(&durable)
	return schema_cardinality_database_invariant(t, state, &durable, "durable")
}

schema_cardinality_database_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Cardinality_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	state := schema_cardinality_model_state(ctx)
	expect_a, expect_b := schema_cardinality_state_values(state)
	values, values_ok := vev.query(database, `[:find ?value :where [1 :card/value ?value]]`)
	if !values_ok {
		return pbt.error(fmt.tprintf("%s cardinality-schema value query failed", backend))
	}
	defer vev.close(&values)
	values_value, values_value_ok := vev.value(&values)
	expected_count := 0
	if expect_a {
		expected_count += 1
	}
	if expect_b {
		expected_count += 1
	}
	if !values_value_ok || vev.item_count(values_value) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s cardinality-schema value count: expected=%d actual=%d state=%v",
			backend,
			expected_count,
			vev.item_count(values_value),
			state,
		))
	}
	seen_a, seen_b := false, false
	for row_index in 0 ..< vev.item_count(values_value) {
		row, row_ok := vev.item(values_value, row_index)
		value, value_ok := vev.item(row, 0)
		text_value, text_ok := vev.as_string(value, t.value_allocator)
		if !row_ok || !value_ok || !text_ok {
			return pbt.error(fmt.tprintf("%s cardinality-schema value row malformed", backend))
		}
		if text_value == ctx.value_a && expect_a && !seen_a {
			seen_a = true
		} else if text_value == ctx.value_b && expect_b && !seen_b {
			seen_b = true
		} else {
			return pbt.fail(fmt.tprintf("%s cardinality-schema unexpected value=%s state=%v", backend, text_value, state))
		}
	}
	if seen_a != expect_a || seen_b != expect_b {
		return pbt.fail(fmt.tprintf("%s cardinality-schema value set mismatch state=%v", backend, state))
	}
	cardinality_result, cardinality_ok := vev.query(database, `[:find ?kind . :where [100 :db/cardinality ?kind]]`)
	if !cardinality_ok {
		return pbt.error(fmt.tprintf("%s cardinality-schema kind query failed", backend))
	}
	defer vev.close(&cardinality_result)
	cardinality_value, cardinality_value_ok := vev.value(&cardinality_result)
	actual_cardinality, actual_cardinality_ok := vev.as_string(cardinality_value, t.value_allocator)
	expected_cardinality := ":db.cardinality/one"
	if schema_cardinality_state_many(state) {
		expected_cardinality = ":db.cardinality/many"
	}
	if !cardinality_value_ok || !actual_cardinality_ok || actual_cardinality != expected_cardinality {
		return pbt.fail(fmt.tprintf(
			"%s cardinality-schema kind: expected=%s actual=%s",
			backend,
			expected_cardinality,
			actual_cardinality,
		))
	}
	markers, markers_ok := vev.query(database, `[:find ?marker :where [2 :card/marker ?marker]]`)
	if !markers_ok {
		return pbt.error(fmt.tprintf("%s cardinality-schema marker query failed", backend))
	}
	defer vev.close(&markers)
	markers_value, markers_value_ok := vev.value(&markers)
	if !markers_value_ok || vev.item_count(markers_value) != 0 {
		return pbt.fail(fmt.tprintf("%s cardinality-schema rollback marker survived", backend))
	}
	return pbt.pass()
}

schema_cardinality_event_tx :: proc(ctx: ^Schema_Cardinality_Context, event: Schema_Cardinality_Event) -> string {
	switch event {
	case .Switch_Many:
		return `[[:db/add 100 :db/cardinality :db.cardinality/many]]`
	case .Switch_One:
		return `[[:db/add 100 :db/cardinality :db.cardinality/one]]`
	case .Add_A:
		return fmt.tprintf(`[[:db/add 1 :card/value "%s"]]`, ctx.value_a)
	case .Add_B:
		return fmt.tprintf(`[[:db/add 1 :card/value "%s"]]`, ctx.value_b)
	case .Retract_A:
		return fmt.tprintf(`[[:db/retract 1 :card/value "%s"]]`, ctx.value_a)
	case .Retract_B:
		return fmt.tprintf(`[[:db/retract 1 :card/value "%s"]]`, ctx.value_b)
	case .Attempt_Invalid:
		return `[[:db/add 2 :card/marker "must-rollback"] [:db/add 100 :db/cardinality :db.cardinality/sometimes]]`
	}
	return "[]"
}

schema_cardinality_log_count :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Cardinality_Context,
	connection: ^$Connection,
	checkpoint: u64,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s log", backend))
	}
	defer vev.close(&log_value)
	current_basis, current_basis_ok := tempid_order_basis(connection)
	if !current_basis_ok {
		return pbt.error(fmt.tprintf("could not read %s basis for log", backend))
	}
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, current_basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s log range failed", backend))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != ctx.successful_tx_count {
		return pbt.fail(fmt.tprintf(
			"%s transaction count: expected=%d actual=%d",
			backend,
			ctx.successful_tx_count,
			vev.item_count(transactions_value),
		))
	}
	return pbt.pass()
}

schema_cardinality_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Schema_Cardinality_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read cardinality-schema coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen cardinality-schema durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"cardinality-schema coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened cardinality-schema database")
	}
	defer vev.close(&database)
	if result := schema_cardinality_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "cardinality-schema-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		schema_cardinality_model_state(ctx),
	))
	return pbt.pass()
}

schema_cardinality_model_state :: proc(ctx: ^Schema_Cardinality_Context) -> Schema_Cardinality_State {
	if sc.is_active(&ctx.model, Schema_Cardinality_State.One_B) {
		return .One_B
	}
	if sc.is_active(&ctx.model, Schema_Cardinality_State.One_AB) {
		return .One_AB
	}
	if sc.is_active(&ctx.model, Schema_Cardinality_State.Many_A) {
		return .Many_A
	}
	if sc.is_active(&ctx.model, Schema_Cardinality_State.Many_B) {
		return .Many_B
	}
	if sc.is_active(&ctx.model, Schema_Cardinality_State.Many_AB) {
		return .Many_AB
	}
	return .One_A
}

schema_cardinality_state_many :: proc(state: Schema_Cardinality_State) -> bool {
	return state == .Many_A || state == .Many_B || state == .Many_AB
}

schema_cardinality_state_values :: proc(state: Schema_Cardinality_State) -> (a, b: bool) {
	switch state {
	case .One_A, .Many_A:
		return true, false
	case .One_B, .Many_B:
		return false, true
	case .One_AB, .Many_AB:
		return true, true
	}
	return false, false
}

schema_cardinality_event_name :: proc(event: Schema_Cardinality_Event) -> string {
	switch event {
	case .Switch_Many:
		return "switch-many"
	case .Switch_One:
		return "switch-one"
	case .Add_A:
		return "add-a"
	case .Add_B:
		return "add-b"
	case .Retract_A:
		return "retract-a"
	case .Retract_B:
		return "retract-b"
	case .Attempt_Invalid:
		return "attempt-invalid"
	}
	return "unknown"
}

schema_cardinality_state_detail :: proc(state: ^Schema_Cardinality_Context) -> string {
	return fmt.tprintf(
		"state=%v successful-transactions=%d",
		schema_cardinality_model_state(state),
		state.successful_tx_count,
	)
}

schema_cardinality_value_detail :: proc(observation: Schema_Cardinality_Observation) -> string {
	return fmt.tprintf(
		"resident-committed=%v durable-committed=%v basis=%d/%d",
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
