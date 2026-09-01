package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

SCHEMA_VALUE_TYPE_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "schema", "value-type", "rollback", "model", "durable", "differential", "log", "reopen"}
SCHEMA_VALUE_TYPE_COMMAND_COUNT :: 12

SCHEMA_VALUE_TYPE_SCHEMA :: `[
	{:db/id 100 :db/ident :typed/value :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :typed/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Schema_Value_Type_State :: enum {
	String_String,
	Long_String,
	Long_Long,
	String_Long,
}

Schema_Value_Type_Event :: enum {
	Switch_Long,
	Switch_String,
	Write_Long,
	Write_String,
	Readd_Stale_String,
	Readd_Stale_Long,
	Attempt_Long,
	Attempt_String,
}

Schema_Value_Type_Observation :: struct {
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

Schema_Value_Type_Context :: struct {
	chart:               sc.Chart(Schema_Value_Type_State, Schema_Value_Type_Event),
	model:               sc.Instance(Schema_Value_Type_State, Schema_Value_Type_Event),
	connection:          vev.Connection,
	durable:             vev.Durable_Connection,
	durable_path:        string,
	string_value:        string,
	long_value:          int,
	successful_tx_count: int,
}

SCHEMA_VALUE_TYPE_STATES := [?]sc.State_Def(Schema_Value_Type_State) {
	{id = .String_String},
	{id = .Long_String},
	{id = .Long_Long},
	{id = .String_Long},
}

SCHEMA_VALUE_TYPE_TRANSITIONS := [?]sc.Transition_Def(Schema_Value_Type_State, Schema_Value_Type_Event) {
	{source = .String_String, target = .Long_String, trigger = .Switch_Long},
	{source = .String_String, target = .String_String, trigger = .Write_String},
	{source = .String_String, target = .String_String, trigger = .Attempt_Long},
	{source = .Long_String, target = .Long_Long, trigger = .Write_Long},
	{source = .Long_String, target = .Long_String, trigger = .Readd_Stale_String},
	{source = .Long_Long, target = .String_Long, trigger = .Switch_String},
	{source = .Long_Long, target = .Long_Long, trigger = .Write_Long},
	{source = .Long_Long, target = .Long_Long, trigger = .Attempt_String},
	{source = .String_Long, target = .String_String, trigger = .Write_String},
	{source = .String_Long, target = .String_Long, trigger = .Readd_Stale_Long},
}

schema_value_type_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Schema_Value_Type_Context
	if !schema_value_type_statechart_init(&ctx) {
		return pbt.error("could not initialize value-type schema statechart")
	}
	defer schema_value_type_statechart_destroy(&ctx)
	stem := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))
	ctx.string_value = fmt.tprintf("%s-value", stem)
	ctx.long_value = pbt.draw(t, pbt.int_range(-1_000_000, 1_000_000))

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create value-type resident connection")
	}
	defer vev.close(&ctx.connection)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate value-type durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create value-type durable connection")
	}
	defer vev.close(&ctx.durable)

	seed := fmt.tprintf(`[[:db/add 1 :typed/value "%s"]]`, ctx.string_value)
	setup_transactions := [?]string{SCHEMA_VALUE_TYPE_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize value-type backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish value-type checkpoint")
	}

	model := pbt.State_Model(^Schema_Value_Type_Context, Schema_Value_Type_Event, Schema_Value_Type_Observation) {
		target = &ctx,
		initial = schema_value_type_initial,
		command = schema_value_type_command,
		run = schema_value_type_run,
		next_state = schema_value_type_next_state,
		postcondition = schema_value_type_postcondition,
		invariant = schema_value_type_invariant,
		command_name = schema_value_type_event_name,
		state_detail = schema_value_type_state_detail,
		value_detail = schema_value_type_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = SCHEMA_VALUE_TYPE_COMMAND_COUNT,
		max_success_events = SCHEMA_VALUE_TYPE_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := schema_value_type_log_count(t, &ctx, &ctx.connection, resident_checkpoint, "resident value-type"); result.status != .Pass {
		return result
	}
	if result := schema_value_type_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable value-type"); result.status != .Pass {
		return result
	}
	if result := schema_value_type_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return schema_value_type_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened value-type")
}

schema_value_type_statechart_init :: proc(ctx: ^Schema_Value_Type_Context) -> bool {
	definition := sc.Chart_Def(Schema_Value_Type_State, Schema_Value_Type_Event) {
		initial = .String_String,
		states = SCHEMA_VALUE_TYPE_STATES[:],
		transitions = SCHEMA_VALUE_TYPE_TRANSITIONS[:],
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

schema_value_type_statechart_destroy :: proc(ctx: ^Schema_Value_Type_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

schema_value_type_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Schema_Value_Type_Context {
	return cast(^Schema_Value_Type_Context)target
}

schema_value_type_command :: proc(t: ^pbt.T, state: ^Schema_Value_Type_Context) -> Schema_Value_Type_Event {
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Schema_Value_Type_Event.Switch_Long)
	pbt.cover(t, event == .Switch_Long, 30, "value-type-switch-long")
	pbt.cover(t, event == .Switch_String, 15, "value-type-switch-string")
	pbt.cover(t, event == .Write_Long, 25, "value-type-write-long")
	pbt.cover(t, event == .Write_String, 25, "value-type-write-string")
	pbt.cover(t, event == .Readd_Stale_String, 10, "value-type-readd-stale-string")
	pbt.cover(t, event == .Readd_Stale_Long, 5, "value-type-readd-stale-long")
	pbt.cover(t, event == .Attempt_Long, 20, "value-type-reject-long")
	pbt.cover(t, event == .Attempt_String, 10, "value-type-reject-string")
	return event
}

schema_value_type_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Schema_Value_Type_Context,
	event: Schema_Value_Type_Event,
) -> Schema_Value_Type_Observation {
	ctx := cast(^Schema_Value_Type_Context)target
	before_state := schema_value_type_model_state(ctx)
	tx := schema_value_type_event_tx(ctx, event)
	expected_commit := event != .Attempt_Long && event != .Attempt_String
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, schema_value_type_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"value-type state=%v event=%s expected-commit=%v tx=%s resident=%s durable=%s",
		before_state,
		schema_value_type_event_name(event),
		expected_commit,
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && expected_commit && resident_committed && durable_committed {
		ctx.successful_tx_count += 1
	}
	return Schema_Value_Type_Observation {
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

schema_value_type_next_state :: proc(
	state: ^Schema_Value_Type_Context,
	event: Schema_Value_Type_Event,
	observation: Schema_Value_Type_Observation,
) -> ^Schema_Value_Type_Context {
	return state
}

schema_value_type_postcondition :: proc(
	state: ^Schema_Value_Type_Context,
	event: Schema_Value_Type_Event,
	observation: Schema_Value_Type_Observation,
) -> pbt.Result {
	expected_commit := event != .Attempt_Long && event != .Attempt_String
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident did not return a report for %s", schema_value_type_event_name(event)))
	}
	if observation.resident_committed != expected_commit || observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"value-type %s commit mismatch: expected=%v resident=%v durable=%v",
			schema_value_type_event_name(event),
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("value-type %s coordinates unavailable", schema_value_type_event_name(event)))
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
			"value-type %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			schema_value_type_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if !expected_commit &&
	   (!strings.contains(observation.resident_report, "schema value type mismatch") ||
	    !strings.contains(observation.durable_report, "schema value type mismatch")) {
		return pbt.fail(fmt.tprintf(
			"value-type error mismatch: resident=%s durable=%s",
			observation.resident_report,
			observation.durable_report,
		))
	}
	return pbt.pass()
}

schema_value_type_invariant :: proc(t: ^pbt.T, state: ^Schema_Value_Type_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident value-type database")
	}
	defer vev.close(&resident)
	if result := schema_value_type_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable value-type database")
	}
	defer vev.close(&durable)
	return schema_value_type_database_invariant(t, state, &durable, "durable")
}

schema_value_type_database_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Value_Type_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	state := schema_value_type_model_state(ctx)
	value_result, value_ok := vev.query(database, `[:find ?value . :where [1 :typed/value ?value]]`)
	if !value_ok {
		return pbt.error(fmt.tprintf("%s value-type value query failed", backend))
	}
	defer vev.close(&value_result)
	value, retained_value_ok := vev.value(&value_result)
	if !retained_value_ok {
		return pbt.error(fmt.tprintf("%s value-type value unavailable", backend))
	}
	if schema_value_type_state_has_string(state) {
		actual, actual_ok := vev.as_string(value, t.value_allocator)
		if !actual_ok || actual != ctx.string_value {
			return pbt.fail(fmt.tprintf("%s value-type string mismatch state=%v actual=%s", backend, state, actual))
		}
	} else {
		actual, actual_ok := vev.as_int(value)
		if !actual_ok || actual != i64(ctx.long_value) {
			return pbt.fail(fmt.tprintf("%s value-type long mismatch state=%v actual=%d", backend, state, actual))
		}
	}
	type_result, type_ok := vev.query(database, `[:find ?kind . :where [100 :db/valueType ?kind]]`)
	if !type_ok {
		return pbt.error(fmt.tprintf("%s value-type schema query failed", backend))
	}
	defer vev.close(&type_result)
	type_value, retained_type_ok := vev.value(&type_result)
	actual_type, actual_type_ok := vev.as_string(type_value, t.value_allocator)
	expected_type := ":db.type/string"
	if schema_value_type_state_schema_long(state) {
		expected_type = ":db.type/long"
	}
	if !retained_type_ok || !actual_type_ok || actual_type != expected_type {
		return pbt.fail(fmt.tprintf(
			"%s value-type schema: expected=%s actual=%s state=%v",
			backend,
			expected_type,
			actual_type,
			state,
		))
	}
	markers, markers_ok := vev.query(database, `[:find ?marker :where [2 :typed/marker ?marker]]`)
	if !markers_ok {
		return pbt.error(fmt.tprintf("%s value-type marker query failed", backend))
	}
	defer vev.close(&markers)
	markers_value, markers_value_ok := vev.value(&markers)
	if !markers_value_ok || vev.item_count(markers_value) != 0 {
		return pbt.fail(fmt.tprintf("%s value-type rollback marker survived", backend))
	}
	return pbt.pass()
}

schema_value_type_event_tx :: proc(ctx: ^Schema_Value_Type_Context, event: Schema_Value_Type_Event) -> string {
	switch event {
	case .Switch_Long:
		return `[[:db/add 100 :db/valueType :db.type/long]]`
	case .Switch_String:
		return `[[:db/add 100 :db/valueType :db.type/string]]`
	case .Write_Long:
		return fmt.tprintf(`[[:db/add 1 :typed/value %d]]`, ctx.long_value)
	case .Write_String:
		return fmt.tprintf(`[[:db/add 1 :typed/value "%s"]]`, ctx.string_value)
	case .Readd_Stale_String:
		return fmt.tprintf(`[[:db/add 1 :typed/value "%s"]]`, ctx.string_value)
	case .Readd_Stale_Long:
		return fmt.tprintf(`[[:db/add 1 :typed/value %d]]`, ctx.long_value)
	case .Attempt_Long:
		return fmt.tprintf(
			`[[:db/add 2 :typed/marker "must-rollback"] [:db/add 1 :typed/value %d]]`,
			ctx.long_value,
		)
	case .Attempt_String:
		return fmt.tprintf(
			`[[:db/add 2 :typed/marker "must-rollback"] [:db/add 1 :typed/value "%s"]]`,
			ctx.string_value,
		)
	}
	return "[]"
}

schema_value_type_log_count :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Value_Type_Context,
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

schema_value_type_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Schema_Value_Type_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read value-type coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen value-type durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"value-type coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened value-type database")
	}
	defer vev.close(&database)
	if result := schema_value_type_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "value-type-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		schema_value_type_model_state(ctx),
	))
	return pbt.pass()
}

schema_value_type_model_state :: proc(ctx: ^Schema_Value_Type_Context) -> Schema_Value_Type_State {
	if sc.is_active(&ctx.model, Schema_Value_Type_State.Long_String) {
		return .Long_String
	}
	if sc.is_active(&ctx.model, Schema_Value_Type_State.Long_Long) {
		return .Long_Long
	}
	if sc.is_active(&ctx.model, Schema_Value_Type_State.String_Long) {
		return .String_Long
	}
	return .String_String
}

schema_value_type_state_schema_long :: proc(state: Schema_Value_Type_State) -> bool {
	return state == .Long_String || state == .Long_Long
}

schema_value_type_state_has_string :: proc(state: Schema_Value_Type_State) -> bool {
	return state == .String_String || state == .Long_String
}

schema_value_type_event_name :: proc(event: Schema_Value_Type_Event) -> string {
	switch event {
	case .Switch_Long:
		return "switch-long"
	case .Switch_String:
		return "switch-string"
	case .Write_Long:
		return "write-long"
	case .Write_String:
		return "write-string"
	case .Readd_Stale_String:
		return "readd-stale-string"
	case .Readd_Stale_Long:
		return "readd-stale-long"
	case .Attempt_Long:
		return "attempt-long"
	case .Attempt_String:
		return "attempt-string"
	}
	return "unknown"
}

schema_value_type_state_detail :: proc(state: ^Schema_Value_Type_Context) -> string {
	return fmt.tprintf(
		"state=%v successful-transactions=%d",
		schema_value_type_model_state(state),
		state.successful_tx_count,
	)
}

schema_value_type_value_detail :: proc(observation: Schema_Value_Type_Observation) -> string {
	return fmt.tprintf(
		"resident-committed=%v durable-committed=%v basis=%d/%d",
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
