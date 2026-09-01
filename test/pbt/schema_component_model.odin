package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

SCHEMA_COMPONENT_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "schema", "component", "cascade", "rollback", "model", "durable", "differential", "log", "reopen"}
SCHEMA_COMPONENT_COMMAND_COUNT :: 12

SCHEMA_COMPONENT_SCHEMA :: `[
	{:db/id 100 :db/ident :owned/child :db/valueType :db.type/ref :db/cardinality :db.cardinality/one :db/isComponent false}
	{:db/id 101 :db/ident :owned/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :owned/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Schema_Component_State :: enum {
	Plain_Full,
	Component_Full,
	Plain_Orphans,
	Component_Empty,
}

Schema_Component_Event :: enum {
	Enable_Component,
	Disable_Component,
	Retract_Root,
	Restore_Tree,
	Attempt_Non_Boolean,
	Attempt_Non_Ref,
}

Schema_Component_Observation :: struct {
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

Schema_Component_Context :: struct {
	chart:               sc.Chart(Schema_Component_State, Schema_Component_Event),
	model:               sc.Instance(Schema_Component_State, Schema_Component_Event),
	connection:          vev.Connection,
	durable:             vev.Durable_Connection,
	durable_path:        string,
	name_stem:           string,
	successful_tx_count: int,
}

SCHEMA_COMPONENT_STATES := [?]sc.State_Def(Schema_Component_State) {
	{id = .Plain_Full},
	{id = .Component_Full},
	{id = .Plain_Orphans},
	{id = .Component_Empty},
}

SCHEMA_COMPONENT_TRANSITIONS := [?]sc.Transition_Def(Schema_Component_State, Schema_Component_Event) {
	{source = .Plain_Full, target = .Component_Full, trigger = .Enable_Component},
	{source = .Plain_Full, target = .Plain_Orphans, trigger = .Retract_Root},
	{source = .Plain_Full, target = .Plain_Full, trigger = .Attempt_Non_Boolean},
	{source = .Component_Full, target = .Plain_Full, trigger = .Disable_Component},
	{source = .Component_Full, target = .Component_Empty, trigger = .Retract_Root},
	{source = .Component_Full, target = .Component_Full, trigger = .Attempt_Non_Boolean},
	{source = .Component_Full, target = .Component_Full, trigger = .Attempt_Non_Ref},
	{source = .Plain_Orphans, target = .Plain_Full, trigger = .Restore_Tree},
	{source = .Plain_Orphans, target = .Plain_Orphans, trigger = .Attempt_Non_Boolean},
	{source = .Component_Empty, target = .Component_Full, trigger = .Restore_Tree},
	{source = .Component_Empty, target = .Component_Empty, trigger = .Attempt_Non_Boolean},
	{source = .Component_Empty, target = .Component_Empty, trigger = .Attempt_Non_Ref},
}

schema_component_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Schema_Component_Context
	if !schema_component_statechart_init(&ctx) {
		return pbt.error("could not initialize component-schema statechart")
	}
	defer schema_component_statechart_destroy(&ctx)
	ctx.name_stem = pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create component-schema resident connection")
	}
	defer vev.close(&ctx.connection)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate component-schema durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create component-schema durable connection")
	}
	defer vev.close(&ctx.durable)

	seed := schema_component_full_tree_tx(&ctx)
	setup_transactions := [?]string{SCHEMA_COMPONENT_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize component-schema backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish component-schema checkpoint")
	}

	model := pbt.State_Model(^Schema_Component_Context, Schema_Component_Event, Schema_Component_Observation) {
		target = &ctx,
		initial = schema_component_initial,
		command = schema_component_command,
		run = schema_component_run,
		next_state = schema_component_next_state,
		postcondition = schema_component_postcondition,
		invariant = schema_component_invariant,
		command_name = schema_component_event_name,
		state_detail = schema_component_state_detail,
		value_detail = schema_component_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = SCHEMA_COMPONENT_COMMAND_COUNT,
		max_success_events = SCHEMA_COMPONENT_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := schema_component_log_count(t, &ctx, &ctx.connection, resident_checkpoint, "resident component-schema"); result.status != .Pass {
		return result
	}
	if result := schema_component_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable component-schema"); result.status != .Pass {
		return result
	}
	if result := schema_component_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return schema_component_log_count(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened component-schema")
}

schema_component_statechart_init :: proc(ctx: ^Schema_Component_Context) -> bool {
	definition := sc.Chart_Def(Schema_Component_State, Schema_Component_Event) {
		initial = .Plain_Full,
		states = SCHEMA_COMPONENT_STATES[:],
		transitions = SCHEMA_COMPONENT_TRANSITIONS[:],
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

schema_component_statechart_destroy :: proc(ctx: ^Schema_Component_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

schema_component_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Schema_Component_Context {
	return cast(^Schema_Component_Context)target
}

schema_component_command :: proc(t: ^pbt.T, state: ^Schema_Component_Context) -> Schema_Component_Event {
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Schema_Component_Event.Enable_Component)
	before := schema_component_model_state(state)
	pbt.cover(t, event == .Enable_Component, 15, "component-schema-enable")
	pbt.cover(t, event == .Disable_Component, 8, "component-schema-disable")
	pbt.cover(t, before == .Plain_Full && event == .Retract_Root, 15, "component-schema-plain-retract")
	pbt.cover(t, before == .Component_Full && event == .Retract_Root, 8, "component-schema-cascade-retract")
	pbt.cover(t, event == .Restore_Tree, 15, "component-schema-restore")
	pbt.cover(t, event == .Attempt_Non_Boolean, 25, "component-schema-reject-non-boolean")
	pbt.cover(t, event == .Attempt_Non_Ref, 8, "component-schema-reject-non-ref")
	return event
}

schema_component_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Schema_Component_Context,
	event: Schema_Component_Event,
) -> Schema_Component_Observation {
	ctx := cast(^Schema_Component_Context)target
	before_state := schema_component_model_state(ctx)
	tx := schema_component_event_tx(ctx, before_state, event)
	expected_commit := event != .Attempt_Non_Boolean && event != .Attempt_Non_Ref
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, schema_component_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"component-schema state=%v event=%s expected-commit=%v tx=%s resident=%s durable=%s",
		before_state,
		schema_component_event_name(event),
		expected_commit,
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && expected_commit && resident_committed && durable_committed {
		ctx.successful_tx_count += 1
	}
	return Schema_Component_Observation {
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

schema_component_next_state :: proc(
	state: ^Schema_Component_Context,
	event: Schema_Component_Event,
	observation: Schema_Component_Observation,
) -> ^Schema_Component_Context {
	return state
}

schema_component_postcondition :: proc(
	state: ^Schema_Component_Context,
	event: Schema_Component_Event,
	observation: Schema_Component_Observation,
) -> pbt.Result {
	expected_commit := event != .Attempt_Non_Boolean && event != .Attempt_Non_Ref
	if !observation.resident_call_ok {
		return pbt.error(fmt.tprintf("resident did not return a report for %s", schema_component_event_name(event)))
	}
	if observation.resident_committed != expected_commit || observation.durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"component-schema %s commit mismatch: expected=%v resident=%v durable=%v",
			schema_component_event_name(event),
			expected_commit,
			observation.resident_committed,
			observation.durable_committed,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("component-schema %s coordinates unavailable", schema_component_event_name(event)))
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
			"component-schema %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			schema_component_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	if event == .Attempt_Non_Boolean &&
	   (!strings.contains(observation.resident_report, "schema boolean value must be boolean") ||
	    !strings.contains(observation.durable_report, "schema boolean value must be boolean")) {
		return pbt.fail(fmt.tprintf(
			"component-schema boolean error mismatch: resident=%s durable=%s",
			observation.resident_report,
			observation.durable_report,
		))
	}
	if event == .Attempt_Non_Ref &&
	   (!strings.contains(observation.resident_report, "invalid component schema") ||
	    !strings.contains(observation.durable_report, "invalid component schema")) {
		return pbt.fail(fmt.tprintf(
			"component-schema ref error mismatch: resident=%s durable=%s",
			observation.resident_report,
			observation.durable_report,
		))
	}
	return pbt.pass()
}

schema_component_invariant :: proc(t: ^pbt.T, state: ^Schema_Component_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident component-schema database")
	}
	defer vev.close(&resident)
	if result := schema_component_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable component-schema database")
	}
	defer vev.close(&durable)
	return schema_component_database_invariant(t, state, &durable, "durable")
}

schema_component_database_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Component_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	state := schema_component_model_state(ctx)
	expect_root := state == .Plain_Full || state == .Component_Full
	expect_children := state != .Component_Empty
	for entity in 1 ..= 3 {
		expected := expect_children
		if entity == 1 {
			expected = expect_root
		}
		if result := schema_component_expect_name(t, ctx, database, u64(entity), expected, backend); result.status != .Pass {
			return result
		}
	}
	if result := schema_component_expect_name(t, ctx, database, 99, true, backend); result.status != .Pass {
		return result
	}
	if result := schema_component_expect_edge(t, database, 1, 2, expect_root, backend); result.status != .Pass {
		return result
	}
	if result := schema_component_expect_edge(t, database, 2, 3, expect_children, backend); result.status != .Pass {
		return result
	}
	type_result, type_ok := vev.query(database, `[:find ?kind . :where [100 :db/valueType ?kind]]`)
	if !type_ok {
		return pbt.error(fmt.tprintf("%s component-schema value type query failed", backend))
	}
	defer vev.close(&type_result)
	type_value, retained_type_ok := vev.value(&type_result)
	actual_type, actual_type_ok := vev.as_string(type_value, t.value_allocator)
	if !retained_type_ok || !actual_type_ok || actual_type != ":db.type/ref" {
		return pbt.fail(fmt.tprintf("%s component-schema value type changed: %s", backend, actual_type))
	}
	component_result, component_ok := vev.query(database, `[:find ?component . :where [100 :db/isComponent ?component]]`)
	if !component_ok {
		return pbt.error(fmt.tprintf("%s component-schema boolean query failed", backend))
	}
	defer vev.close(&component_result)
	component_value, retained_component_ok := vev.value(&component_result)
	actual_component, actual_component_ok := vev.as_bool(component_value)
	expected_component := state == .Component_Full || state == .Component_Empty
	if !retained_component_ok || !actual_component_ok || actual_component != expected_component {
		return pbt.fail(fmt.tprintf(
			"%s component-schema boolean: expected=%v actual=%v state=%v",
			backend,
			expected_component,
			actual_component,
			state,
		))
	}
	markers, markers_ok := vev.query(database, `[:find ?marker :where [98 :owned/marker ?marker]]`)
	if !markers_ok {
		return pbt.error(fmt.tprintf("%s component-schema marker query failed", backend))
	}
	defer vev.close(&markers)
	markers_value, markers_value_ok := vev.value(&markers)
	if !markers_value_ok || vev.item_count(markers_value) != 0 {
		return pbt.fail(fmt.tprintf("%s component-schema rollback marker survived", backend))
	}
	return pbt.pass()
}

schema_component_expect_name :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Component_Context,
	database: ^vev.DB,
	entity: u64,
	expected_present: bool,
	backend: string,
) -> pbt.Result {
	query := fmt.tprintf(`[:find ?name . :where [%d :owned/name ?name]]`, entity)
	result, query_ok := vev.query(database, query)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s component-schema name query failed for %d", backend, entity))
	}
	defer vev.close(&result)
	value, value_ok := vev.value(&result)
	name, name_ok := vev.as_string(value, t.value_allocator)
	if !expected_present {
		if name_ok {
			return pbt.fail(fmt.tprintf("%s component-schema unexpected name for %d: %s", backend, entity, name))
		}
		return pbt.pass()
	}
	expected := schema_component_name(ctx, entity)
	if !value_ok || !name_ok || name != expected {
		return pbt.fail(fmt.tprintf(
			"%s component-schema name for %d: expected=%s actual=%s",
			backend,
			entity,
			expected,
			name,
		))
	}
	return pbt.pass()
}

schema_component_expect_edge :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	parent, child: u64,
	expected_present: bool,
	backend: string,
) -> pbt.Result {
	query := fmt.tprintf(`[:find ?child . :where [%d :owned/child ?child]]`, parent)
	result, query_ok := vev.query(database, query)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s component-schema edge query failed for %d", backend, parent))
	}
	defer vev.close(&result)
	value, value_ok := vev.value(&result)
	actual, actual_ok := vev.as_int(value)
	if actual_ok != expected_present || (expected_present && actual != i64(child)) {
		return pbt.fail(fmt.tprintf(
			"%s component-schema edge %d->%d: expected-present=%v actual-present=%v actual=%d",
			backend,
			parent,
			child,
			expected_present,
			actual_ok,
			actual,
		))
	}
	if expected_present && !value_ok {
		return pbt.error(fmt.tprintf("%s component-schema edge value unavailable", backend))
	}
	return pbt.pass()
}

schema_component_event_tx :: proc(
	ctx: ^Schema_Component_Context,
	state: Schema_Component_State,
	event: Schema_Component_Event,
) -> string {
	switch event {
	case .Enable_Component:
		return `[[:db/add 100 :db/isComponent true]]`
	case .Disable_Component:
		return `[[:db/add 100 :db/isComponent false]]`
	case .Retract_Root:
		return `[[:db.fn/retractEntity 1]]`
	case .Restore_Tree:
		if state == .Plain_Orphans {
			return fmt.tprintf(
				`[[:db/add 1 :owned/name "%s"] [:db/add 1 :owned/child 2]]`,
				schema_component_name(ctx, 1),
			)
		}
		return schema_component_full_tree_tx(ctx)
	case .Attempt_Non_Boolean:
		return `[[:db/add 98 :owned/marker "must-rollback"] [:db/add 100 :db/isComponent "true"]]`
	case .Attempt_Non_Ref:
		return `[[:db/add 98 :owned/marker "must-rollback"] [:db/add 100 :db/valueType :db.type/string]]`
	}
	return "[]"
}

schema_component_full_tree_tx :: proc(ctx: ^Schema_Component_Context) -> string {
	return fmt.tprintf(
		`[
			[:db/add 1 :owned/name "%s"]
			[:db/add 2 :owned/name "%s"]
			[:db/add 3 :owned/name "%s"]
			[:db/add 1 :owned/child 2]
			[:db/add 2 :owned/child 3]
			[:db/add 99 :owned/name "%s"]
		]`,
		schema_component_name(ctx, 1),
		schema_component_name(ctx, 2),
		schema_component_name(ctx, 3),
		schema_component_name(ctx, 99),
	)
}

schema_component_log_count :: proc(
	t: ^pbt.T,
	ctx: ^Schema_Component_Context,
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

schema_component_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Schema_Component_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read component-schema coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen component-schema durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"component-schema coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened component-schema database")
	}
	defer vev.close(&database)
	if result := schema_component_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "component-schema-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		schema_component_model_state(ctx),
	))
	return pbt.pass()
}

schema_component_model_state :: proc(ctx: ^Schema_Component_Context) -> Schema_Component_State {
	if sc.is_active(&ctx.model, Schema_Component_State.Component_Full) {
		return .Component_Full
	}
	if sc.is_active(&ctx.model, Schema_Component_State.Plain_Orphans) {
		return .Plain_Orphans
	}
	if sc.is_active(&ctx.model, Schema_Component_State.Component_Empty) {
		return .Component_Empty
	}
	return .Plain_Full
}

schema_component_name :: proc(ctx: ^Schema_Component_Context, entity: u64) -> string {
	return fmt.tprintf("%s-%d", ctx.name_stem, entity)
}

schema_component_event_name :: proc(event: Schema_Component_Event) -> string {
	switch event {
	case .Enable_Component:
		return "enable-component"
	case .Disable_Component:
		return "disable-component"
	case .Retract_Root:
		return "retract-root"
	case .Restore_Tree:
		return "restore-tree"
	case .Attempt_Non_Boolean:
		return "attempt-non-boolean"
	case .Attempt_Non_Ref:
		return "attempt-non-ref"
	}
	return "unknown"
}

schema_component_state_detail :: proc(state: ^Schema_Component_Context) -> string {
	return fmt.tprintf(
		"state=%v successful-transactions=%d",
		schema_component_model_state(state),
		state.successful_tx_count,
	)
}

schema_component_value_detail :: proc(observation: Schema_Component_Observation) -> string {
	return fmt.tprintf(
		"resident-committed=%v durable-committed=%v basis=%d/%d",
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
