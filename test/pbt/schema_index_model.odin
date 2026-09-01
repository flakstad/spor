package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

SCHEMA_INDEX_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "schema", "index", "avet", "rollback", "model", "durable", "differential", "log", "reopen"}
SCHEMA_INDEX_COMMAND_COUNT :: 12

SCHEMA_INDEX_SCHEMA :: `[
	{:db/id 100 :db/ident :indexed/value :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/index false}
	{:db/id 101 :db/ident :indexed/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Schema_Index_State :: enum {
	Off_A,
	On_A,
	Off_B,
	On_B,
}

Schema_Index_Event :: enum {
	Enable_Index,
	Disable_Index,
	Write_A,
	Write_B,
	Attempt_Non_Boolean,
}

Schema_Index_Observation :: struct {
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

Schema_Index_Context :: struct {
	chart:               sc.Chart(Schema_Index_State, Schema_Index_Event),
	model:               sc.Instance(Schema_Index_State, Schema_Index_Event),
	connection:          vev.Connection,
	durable:             vev.Durable_Connection,
	durable_path:        string,
	value_a:             string,
	value_b:             string,
	value_2:             string,
	value_3:             string,
	successful_tx_count: int,
}

SCHEMA_INDEX_STATES := [?]sc.State_Def(Schema_Index_State) {
	{id = .Off_A},
	{id = .On_A},
	{id = .Off_B},
	{id = .On_B},
}

SCHEMA_INDEX_TRANSITIONS := [?]sc.Transition_Def(Schema_Index_State, Schema_Index_Event) {
	{source = .Off_A, target = .On_A, trigger = .Enable_Index},
	{source = .Off_A, target = .Off_B, trigger = .Write_B},
	{source = .Off_A, target = .Off_A, trigger = .Attempt_Non_Boolean},
	{source = .On_A, target = .Off_A, trigger = .Disable_Index},
	{source = .On_A, target = .On_B, trigger = .Write_B},
	{source = .On_A, target = .On_A, trigger = .Attempt_Non_Boolean},
	{source = .Off_B, target = .On_B, trigger = .Enable_Index},
	{source = .Off_B, target = .Off_A, trigger = .Write_A},
	{source = .Off_B, target = .Off_B, trigger = .Attempt_Non_Boolean},
	{source = .On_B, target = .Off_B, trigger = .Disable_Index},
	{source = .On_B, target = .On_A, trigger = .Write_A},
	{source = .On_B, target = .On_B, trigger = .Attempt_Non_Boolean},
}

schema_index_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Schema_Index_Context
	if !schema_index_statechart_init(&ctx) {
		return pbt.error("could not initialize index-schema statechart")
	}
	defer schema_index_statechart_destroy(&ctx)
	stem := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))
	ctx.value_a = fmt.tprintf("%s-a", stem)
	ctx.value_b = fmt.tprintf("%s-b", stem)
	ctx.value_2 = fmt.tprintf("%s-two", stem)
	ctx.value_3 = fmt.tprintf("%s-three", stem)

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create index-schema resident connection")
	}
	defer vev.close(&ctx.connection)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate index-schema durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create index-schema durable connection")
	}
	defer vev.close(&ctx.durable)

	seed := fmt.tprintf(
		`[
			[:db/add 1 :indexed/value "%s"]
			[:db/add 2 :indexed/value "%s"]
			[:db/add 3 :indexed/value "%s"]
		]`,
		ctx.value_a,
		ctx.value_2,
		ctx.value_3,
	)
	setup_transactions := [?]string{SCHEMA_INDEX_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize index-schema backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish index-schema checkpoint")
	}

	model := pbt.State_Model(^Schema_Index_Context, Schema_Index_Event, Schema_Index_Observation) {
		target = &ctx,
		initial = schema_index_initial,
		command = schema_index_command,
		run = schema_index_run,
		next_state = schema_index_next_state,
		postcondition = schema_index_postcondition,
		invariant = schema_index_invariant,
		command_name = schema_index_event_name,
		state_detail = schema_index_state_detail,
		value_detail = schema_index_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = SCHEMA_INDEX_COMMAND_COUNT,
		max_success_events = SCHEMA_INDEX_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := schema_index_log_count(t, &ctx, &ctx.connection, resident_checkpoint, "resident index-schema"); result.status != .Pass {
		return result
	}
	if result := schema_index_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable index-schema"); result.status != .Pass {
		return result
	}
	if result := schema_index_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return schema_index_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened index-schema")
}

schema_index_statechart_init :: proc(ctx: ^Schema_Index_Context) -> bool {
	definition := sc.Chart_Def(Schema_Index_State, Schema_Index_Event) {
		initial = .Off_A,
		states = SCHEMA_INDEX_STATES[:],
		transitions = SCHEMA_INDEX_TRANSITIONS[:],
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

schema_index_statechart_destroy :: proc(ctx: ^Schema_Index_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

schema_index_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Schema_Index_Context {
	return cast(^Schema_Index_Context)target
}

schema_index_command :: proc(t: ^pbt.T, state: ^Schema_Index_Context) -> Schema_Index_Event {
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Schema_Index_Event.Enable_Index)
	before := schema_index_model_state(state)
	pbt.cover(t, event == .Enable_Index, 25, "index-schema-enable")
	pbt.cover(t, event == .Disable_Index, 15, "index-schema-disable")
	pbt.cover(t, event == .Write_A || event == .Write_B, 35, "index-schema-write")
	pbt.cover(t, schema_index_state_enabled(before) && (event == .Write_A || event == .Write_B), 15, "index-schema-write-enabled")
	pbt.cover(t, !schema_index_state_enabled(before) && (event == .Write_A || event == .Write_B), 15, "index-schema-write-disabled")
	pbt.cover(t, event == .Attempt_Non_Boolean, 25, "index-schema-reject-non-boolean")
	return event
}

schema_index_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Schema_Index_Context,
	event: Schema_Index_Event,
) -> Schema_Index_Observation {
	ctx := cast(^Schema_Index_Context)target
	before_state := schema_index_model_state(ctx)
	tx := schema_index_event_tx(ctx, event)
	expected_commit := event != .Attempt_Non_Boolean
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, schema_index_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"index-schema state=%v event=%s expected-commit=%v tx=%s resident=%s durable=%s",
		before_state,
		schema_index_event_name(event),
		expected_commit,
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && expected_commit && resident_committed && durable_committed {
		ctx.successful_tx_count += 1
	}
	return Schema_Index_Observation {
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

schema_index_next_state :: proc(
	state: ^Schema_Index_Context,
	event: Schema_Index_Event,
	observation: Schema_Index_Observation,
) -> ^Schema_Index_Context {
	return state
}

schema_index_postcondition :: proc(
	state: ^Schema_Index_Context,
	event: Schema_Index_Event,
	observation: Schema_Index_Observation,
) -> pbt.Result {
	expected_commit := event != .Attempt_Non_Boolean
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident did not return a report for %s", schema_index_event_name(event)))
	}
	if observation.resident_committed != expected_commit || observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"index-schema %s commit mismatch: expected=%v resident=%v durable=%v",
			schema_index_event_name(event),
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("index-schema %s coordinates unavailable", schema_index_event_name(event)))
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
			"index-schema %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			schema_index_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if !expected_commit &&
	   (!strings.contains(observation.resident_report, "schema boolean value must be boolean") ||
	    !strings.contains(observation.durable_report, "schema boolean value must be boolean")) {
		return pbt.fail(fmt.tprintf(
			"index-schema error mismatch: resident=%s durable=%s",
			observation.resident_report,
			observation.durable_report,
		))
	}
	return pbt.pass()
}

schema_index_invariant :: proc(t: ^pbt.T, state: ^Schema_Index_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident index-schema database")
	}
	defer vev.close(&resident)
	if result := schema_index_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable index-schema database")
	}
	defer vev.close(&durable)
	return schema_index_database_invariant(t, state, &durable, "durable")
}

schema_index_database_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Index_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	state := schema_index_model_state(ctx)
	expected_value := ctx.value_a
	if schema_index_state_value_b(state) {
		expected_value = ctx.value_b
	}
	value_result, value_ok := vev.query(database, `[:find ?value . :where [1 :indexed/value ?value]]`)
	if !value_ok {
		return pbt.error(fmt.tprintf("%s index-schema value query failed", backend))
	}
	defer vev.close(&value_result)
	value, retained_value_ok := vev.value(&value_result)
	actual_value, actual_value_ok := vev.as_string(value, t.value_allocator)
	if !retained_value_ok || !actual_value_ok || actual_value != expected_value {
		return pbt.fail(fmt.tprintf(
			"%s index-schema value: expected=%s actual=%s state=%v",
			backend,
			expected_value,
			actual_value,
			state,
		))
	}
	index_result, index_ok := vev.index_range(database, ":indexed/value", "nil", "nil")
	expected_index := schema_index_state_enabled(state)
	if !index_ok {
		return pbt.error(fmt.tprintf("%s index-schema AVET range failed", backend))
	}
	defer vev.close(&index_result)
	index_value, index_value_ok := vev.value(&index_result)
	expected_count := 0
	if expected_index {
		expected_count = 3
	}
	if !index_value_ok || vev.item_count(index_value) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s index-schema AVET count: expected=%d actual=%d state=%v",
			backend,
			expected_count,
			vev.item_count(index_value),
			state,
		))
	}
	indexed_result, indexed_ok := vev.query(database, `[:find ?indexed . :where [100 :db/index ?indexed]]`)
	if !indexed_ok {
		return pbt.error(fmt.tprintf("%s index-schema boolean query failed", backend))
	}
	defer vev.close(&indexed_result)
	indexed_value, retained_indexed_ok := vev.value(&indexed_result)
	actual_indexed, actual_indexed_ok := vev.as_bool(indexed_value)
	if !retained_indexed_ok || !actual_indexed_ok || actual_indexed != expected_index {
		return pbt.fail(fmt.tprintf(
			"%s index-schema boolean: expected=%v actual=%v state=%v",
			backend,
			expected_index,
			actual_indexed,
			state,
		))
	}
	markers, markers_ok := vev.query(database, `[:find ?marker :where [98 :indexed/marker ?marker]]`)
	if !markers_ok {
		return pbt.error(fmt.tprintf("%s index-schema marker query failed", backend))
	}
	defer vev.close(&markers)
	markers_value, markers_value_ok := vev.value(&markers)
	if !markers_value_ok || vev.item_count(markers_value) != 0 {
		return pbt.fail(fmt.tprintf("%s index-schema rollback marker survived", backend))
	}
	return pbt.pass()
}

schema_index_event_tx :: proc(ctx: ^Schema_Index_Context, event: Schema_Index_Event) -> string {
	switch event {
	case .Enable_Index:
		return `[[:db/add 100 :db/index true]]`
	case .Disable_Index:
		return `[[:db/add 100 :db/index false]]`
	case .Write_A:
		return fmt.tprintf(`[[:db/add 1 :indexed/value "%s"]]`, ctx.value_a)
	case .Write_B:
		return fmt.tprintf(`[[:db/add 1 :indexed/value "%s"]]`, ctx.value_b)
	case .Attempt_Non_Boolean:
		return `[[:db/add 98 :indexed/marker "must-rollback"] [:db/add 100 :db/index "true"]]`
	}
	return "[]"
}

schema_index_log_count :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Index_Context,
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

schema_index_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Schema_Index_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read index-schema coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen index-schema durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"index-schema coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened index-schema database")
	}
	defer vev.close(&database)
	if result := schema_index_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "index-schema-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		schema_index_model_state(ctx),
	))
	return pbt.pass()
}

schema_index_model_state :: proc(ctx: ^Schema_Index_Context) -> Schema_Index_State {
	if sc.is_active(&ctx.model, Schema_Index_State.On_A) {
		return .On_A
	}
	if sc.is_active(&ctx.model, Schema_Index_State.Off_B) {
		return .Off_B
	}
	if sc.is_active(&ctx.model, Schema_Index_State.On_B) {
		return .On_B
	}
	return .Off_A
}

schema_index_state_enabled :: proc(state: Schema_Index_State) -> bool {
	return state == .On_A || state == .On_B
}

schema_index_state_value_b :: proc(state: Schema_Index_State) -> bool {
	return state == .Off_B || state == .On_B
}

schema_index_event_name :: proc(event: Schema_Index_Event) -> string {
	switch event {
	case .Enable_Index:
		return "enable-index"
	case .Disable_Index:
		return "disable-index"
	case .Write_A:
		return "write-a"
	case .Write_B:
		return "write-b"
	case .Attempt_Non_Boolean:
		return "attempt-non-boolean"
	}
	return "unknown"
}

schema_index_state_detail :: proc(state: ^Schema_Index_Context) -> string {
	return fmt.tprintf(
		"state=%v successful-transactions=%d",
		schema_index_model_state(state),
		state.successful_tx_count,
	)
}

schema_index_value_detail :: proc(observation: Schema_Index_Observation) -> string {
	return fmt.tprintf(
		"resident-committed=%v durable-committed=%v basis=%d/%d",
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
