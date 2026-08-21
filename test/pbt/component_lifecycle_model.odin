// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import pbt_statechart "pbt:pbt_statechart"
import sc "statecharts:statecharts"
import vev "../../clients/odin/vev"

COMPONENT_LIFECYCLE_TAGS := [?]string{"core", "stateful", "statechart", "transaction", "model", "durable", "differential", "component", "cascade", "retract", "log", "reopen"}
COMPONENT_COMMAND_COUNT :: 12
COMPONENT_LOG_DATOM_COUNT :: COMPONENT_COMMAND_COUNT * 3

COMPONENT_SCHEMA :: `[
	{:db/id 100 :db/ident :tree/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :tree/component :db/valueType :db.type/ref :db/cardinality :db.cardinality/one :db/isComponent true}
]`

COMPONENT_SEED :: `[
	{:db/id 1 :tree/name "parent-0"}
	{:db/id 2 :tree/name "child-0"}
	{:db/id 99 :tree/name "sentinel"}
]`

Component_State :: enum {
	Ready,
	Attached,
	Cascaded,
	Deleted,
}

Component_Event :: enum {
	Attach,
	Rename_Parent,
	Rename_Child,
	Retract_Component,
	Retract_Parent,
	Restore_Component,
	Restore_Tree,
}

Component_Attribute :: enum {
	Name,
	Component,
}

Component_Log_Datom :: struct {
	entity:   u64,
	attribute: Component_Attribute,
	revision: int,
	ref:      u64,
	basis:    u64,
	added:    bool,
}

Component_Observation :: struct {
	resident_report:       string,
	durable_report:        string,
	resident_committed:    bool,
	durable_committed:     bool,
	coordinates_ok:        bool,
	resident_basis_before: u64,
	resident_basis_after:  u64,
	durable_basis_before:  u64,
	durable_basis_after:   u64,
	durable_count_before:  u64,
	durable_count_after:   u64,
	model_state:           Component_State,
}

Component_Context :: struct {
	chart:              sc.Chart(Component_State, Component_Event),
	model:              sc.Instance(Component_State, Component_Event),
	connection:         vev.Connection,
	durable:            vev.Durable_Connection,
	durable_path:       string,
	parent_revision:    int,
	child_revision:     int,
	transaction_basis:  [COMPONENT_COMMAND_COUNT]u64,
	transaction_count:  int,
	log_datoms:         [COMPONENT_LOG_DATOM_COUNT]Component_Log_Datom,
	log_datom_count:    int,
}

COMPONENT_STATES := [?]sc.State_Def(Component_State) {
	{id = .Ready},
	{id = .Attached},
	{id = .Cascaded},
	{id = .Deleted},
}

COMPONENT_TRANSITIONS := [?]sc.Transition_Def(Component_State, Component_Event) {
	{source = .Ready, target = .Attached, trigger = .Attach},
	{source = .Attached, target = .Attached, trigger = .Rename_Parent},
	{source = .Attached, target = .Attached, trigger = .Rename_Child},
	{source = .Attached, target = .Cascaded, trigger = .Retract_Component},
	{source = .Attached, target = .Deleted, trigger = .Retract_Parent},
	{source = .Cascaded, target = .Attached, trigger = .Restore_Component},
	{source = .Deleted, target = .Attached, trigger = .Restore_Tree},
}

component_lifecycle_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Component_Context
	if !component_statechart_init(&ctx) {
		return pbt.error("could not initialize component statechart")
	}
	defer component_statechart_destroy(&ctx)

	connection_ok: bool
	ctx.connection, connection_ok = vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create component resident connection")
	}
	defer vev.close(&ctx.connection)

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate component durable path")
	}
	ctx.durable_path = path
	defer transaction_model_remove_store(path)
	durable_ok: bool
	ctx.durable, durable_ok = vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create component durable connection")
	}
	defer vev.close(&ctx.durable)

	setup_transactions := [?]string{COMPONENT_SCHEMA, COMPONENT_SEED}
	for tx in setup_transactions {
		resident_report, resident_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
		if !resident_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize component backends: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&ctx.connection)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&ctx.durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish component log checkpoint")
	}

	model := pbt.State_Model(^Component_Context, Component_Event, Component_Observation) {
		target = &ctx,
		initial = component_initial,
		command = component_command,
		run = component_run,
		next_state = component_next_state,
		postcondition = component_postcondition,
		invariant = component_invariant,
		command_name = component_event_name,
		state_detail = component_state_detail,
		value_detail = component_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 2,
		max_len = COMPONENT_COMMAND_COUNT,
		max_success_events = COMPONENT_COMMAND_COUNT,
		compact_success_events = true,
		skip_success_events = true,
	})
	if result.status != .Pass {
		return result
	}
	if result := component_log_invariant(t, &ctx, &ctx.connection, resident_checkpoint, "resident component"); result.status != .Pass {
		return result
	}
	if result := component_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable component"); result.status != .Pass {
		return result
	}
	if result := component_reopen_invariant(t, &ctx); result.status != .Pass {
		return result
	}
	return component_log_invariant(t, &ctx, &ctx.durable, durable_checkpoint, "durable reopened component")
}

component_statechart_init :: proc(ctx: ^Component_Context) -> bool {
	definition := sc.Chart_Def(Component_State, Component_Event) {
		initial = .Ready,
		states = COMPONENT_STATES[:],
		transitions = COMPONENT_TRANSITIONS[:],
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

component_statechart_destroy :: proc(ctx: ^Component_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

component_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Component_Context {
	return cast(^Component_Context)target
}

component_command :: proc(t: ^pbt.T, state: ^Component_Context) -> Component_Event {
	event := pbt_statechart.draw_enabled_trigger_or_discard(t, &state.model, Component_Event.Attach)
	pbt.cover(t, event == .Attach, 95, "component-attach")
	pbt.cover(t, event == .Rename_Parent, 20, "component-rename-parent")
	pbt.cover(t, event == .Rename_Child, 20, "component-rename-child")
	pbt.cover(t, event == .Retract_Component, 20, "component-retract-attribute")
	pbt.cover(t, event == .Retract_Parent, 20, "component-retract-entity")
	pbt.cover(t, event == .Restore_Component, 15, "component-restore-child")
	pbt.cover(t, event == .Restore_Tree, 15, "component-restore-tree")
	return event
}

component_run :: proc(
	t: ^pbt.T,
	target: rawptr,
	state: ^Component_Context,
	event: Component_Event,
) -> Component_Observation {
	ctx := cast(^Component_Context)target
	before_state := component_model_state(ctx)
	before_parent := ctx.parent_revision
	before_child := ctx.child_revision
	tx := component_event_tx(event, before_parent, before_child)
	resident_before, resident_before_ok := tempid_order_basis(&ctx.connection)
	durable_before, durable_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)

	dispatch := pbt_statechart.dispatch_record(t, &ctx.model, event, component_event_name)
	defer sc.destroy_dispatch_result(&dispatch)
	if dispatch.status == .Transitioned {
		component_apply_model_event(ctx, event)
	}
	resident_report, resident_call_ok := vev.transact(&ctx.connection, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&ctx.durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	resident_after, resident_after_ok := tempid_order_basis(&ctx.connection)
	durable_after, durable_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	pbt.note(t, fmt.tprintf(
		"component state=%v event=%s tx=%s resident=%s durable=%s",
		before_state,
		component_event_name(event),
		tx,
		resident_report,
		durable_report,
	))
	if dispatch.status == .Transitioned && resident_committed && durable_committed {
		component_record_transaction(ctx, event, before_parent, before_child, resident_after)
	}
	return Component_Observation {
		resident_report = resident_report,
		durable_report = durable_report,
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
		model_state = component_model_state(ctx),
	}
}

component_next_state :: proc(
	state: ^Component_Context,
	event: Component_Event,
	observation: Component_Observation,
) -> ^Component_Context {
	return state
}

component_postcondition :: proc(
	state: ^Component_Context,
	event: Component_Event,
	observation: Component_Observation,
) -> pbt.Result {
	if !observation.resident_committed || !observation.durable_committed {
		return pbt.fail(fmt.tprintf(
			"component %s did not commit: resident=%s durable=%s",
			component_event_name(event),
			observation.resident_report,
			observation.durable_report,
		))
	}
	if !observation.coordinates_ok {
		return pbt.error(fmt.tprintf("component %s coordinates unavailable", component_event_name(event)))
	}
	if observation.resident_basis_after != observation.resident_basis_before + 1 ||
	   observation.durable_basis_after != observation.durable_basis_before + 1 ||
	   observation.durable_count_after != observation.durable_count_before + 1 ||
	   observation.resident_basis_after != observation.durable_basis_after {
		return pbt.fail(fmt.tprintf(
			"component %s coordinate mismatch: resident=%d->%d durable=%d->%d count=%d->%d",
			component_event_name(event),
			observation.resident_basis_before,
			observation.resident_basis_after,
			observation.durable_basis_before,
			observation.durable_basis_after,
			observation.durable_count_before,
			observation.durable_count_after,
		))
	}
	return pbt.pass()
}

component_invariant :: proc(t: ^pbt.T, state: ^Component_Context) -> pbt.Result {
	resident, resident_ok := vev.db(&state.connection)
	if !resident_ok {
		return pbt.error("could not retain resident component database")
	}
	defer vev.close(&resident)
	if result := component_database_invariant(t, state, &resident, "resident"); result.status != .Pass {
		return result
	}
	durable, durable_ok := vev.db(&state.durable)
	if !durable_ok {
		return pbt.error("could not retain durable component database")
	}
	defer vev.close(&durable)
	return component_database_invariant(t, state, &durable, "durable")
}

component_database_invariant :: proc(
	t: ^pbt.T,
	state: ^Component_Context,
	database: ^vev.DB,
	backend: string,
) -> pbt.Result {
	model_state := component_model_state(state)
	parent_exists := model_state != .Deleted
	child_exists := model_state == .Ready || model_state == .Attached
	link_exists := model_state == .Attached
	if result := component_expect_name(t, database, 1, parent_exists, component_parent_name(state.parent_revision), backend); result.status != .Pass {
		return result
	}
	if result := component_expect_name(t, database, 2, child_exists, component_child_name(state.child_revision), backend); result.status != .Pass {
		return result
	}
	if result := component_expect_name(t, database, 99, true, "sentinel", backend); result.status != .Pass {
		return result
	}
	child, child_found, child_ok := component_query_ref(database)
	if !child_ok || child_found != link_exists || (child_found && child != 2) {
		return pbt.fail(fmt.tprintf(
			"%s component link: expected-present=%v actual-present=%v child=%d",
			backend,
			link_exists,
			child_found,
			child,
		))
	}
	relation, relation_ok := vev.query(database, `[:find ?e ?name :where [?e :tree/name ?name]]`)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s component relation query failed", backend))
	}
	defer vev.close(&relation)
	relation_value, value_ok := vev.value(&relation)
	expected_count := 1
	if parent_exists {
		expected_count += 1
	}
	if child_exists {
		expected_count += 1
	}
	if !value_ok || vev.item_count(relation_value) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s component name count: expected=%d actual=%d",
			backend,
			expected_count,
			vev.item_count(relation_value),
		))
	}
	return pbt.pass()
}

component_expect_name :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	entity: u64,
	expected_present: bool,
	expected: string,
	backend: string,
) -> pbt.Result {
	actual := query_name_attr(t, database, entity, ":tree/name")
	if !actual.ok {
		return pbt.error(fmt.tprintf("%s component name query failed for %d", backend, entity))
	}
	if actual.found != expected_present || (actual.found && actual.name != expected) {
		return pbt.fail(fmt.tprintf(
			"%s entity %d name: expected-present=%v expected=%s actual-present=%v actual=%s",
			backend,
			entity,
			expected_present,
			expected,
			actual.found,
			actual.name,
		))
	}
	return pbt.pass()
}

component_query_ref :: proc(database: ^vev.DB) -> (child: u64, found, ok: bool) {
	result, query_ok := vev.query(database, `[:find ?child . :where [1 :tree/component ?child]]`)
	if !query_ok {
		return 0, false, false
	}
	defer vev.close(&result)
	value, value_ok := vev.value(&result)
	if !value_ok {
		return 0, false, false
	}
	if vev.kind(value) == .Nil {
		return 0, false, true
	}
	entity, entity_ok := vev.as_int(value)
	if !entity_ok || entity < 0 {
		return 0, false, false
	}
	return u64(entity), true, true
}

component_event_tx :: proc(event: Component_Event, parent_revision, child_revision: int) -> string {
	switch event {
	case .Attach:
		return `[[:db/add 1 :tree/component 2]]`
	case .Rename_Parent:
		return fmt.tprintf(`[[:db/add 1 :tree/name "%s"]]`, component_parent_name(parent_revision + 1))
	case .Rename_Child:
		return fmt.tprintf(`[[:db/add 2 :tree/name "%s"]]`, component_child_name(child_revision + 1))
	case .Retract_Component:
		return `[[:db.fn/retractAttribute 1 :tree/component]]`
	case .Retract_Parent:
		return `[[:db.fn/retractEntity 1]]`
	case .Restore_Component:
		return fmt.tprintf(
			`[[:db/add 2 :tree/name "%s"] [:db/add 1 :tree/component 2]]`,
			component_child_name(child_revision + 1),
		)
	case .Restore_Tree:
		return fmt.tprintf(
			`[[:db/add 1 :tree/name "%s"] [:db/add 2 :tree/name "%s"] [:db/add 1 :tree/component 2]]`,
			component_parent_name(parent_revision + 1),
			component_child_name(child_revision + 1),
		)
	}
	return "[]"
}

component_apply_model_event :: proc(ctx: ^Component_Context, event: Component_Event) {
	switch event {
	case .Rename_Parent:
		ctx.parent_revision += 1
	case .Rename_Child:
		ctx.child_revision += 1
	case .Restore_Component:
		ctx.child_revision += 1
	case .Restore_Tree:
		ctx.parent_revision += 1
		ctx.child_revision += 1
	case .Attach, .Retract_Component, .Retract_Parent:
	}
}

component_record_transaction :: proc(
	ctx: ^Component_Context,
	event: Component_Event,
	parent_revision, child_revision: int,
	basis: u64,
) {
	ctx.transaction_basis[ctx.transaction_count] = basis
	ctx.transaction_count += 1
	switch event {
	case .Attach:
		component_record_ref(ctx, basis, true)
	case .Rename_Parent:
		component_record_name(ctx, 1, parent_revision, basis, false)
		component_record_name(ctx, 1, parent_revision + 1, basis, true)
	case .Rename_Child:
		component_record_name(ctx, 2, child_revision, basis, false)
		component_record_name(ctx, 2, child_revision + 1, basis, true)
	case .Retract_Component:
		component_record_ref(ctx, basis, false)
		component_record_name(ctx, 2, child_revision, basis, false)
	case .Retract_Parent:
		component_record_name(ctx, 1, parent_revision, basis, false)
		component_record_ref(ctx, basis, false)
		component_record_name(ctx, 2, child_revision, basis, false)
	case .Restore_Component:
		component_record_name(ctx, 2, child_revision + 1, basis, true)
		component_record_ref(ctx, basis, true)
	case .Restore_Tree:
		component_record_name(ctx, 1, parent_revision + 1, basis, true)
		component_record_name(ctx, 2, child_revision + 1, basis, true)
		component_record_ref(ctx, basis, true)
	}
}

component_record_name :: proc(ctx: ^Component_Context, entity: u64, revision: int, basis: u64, added: bool) {
	ctx.log_datoms[ctx.log_datom_count] = Component_Log_Datom {
		entity = entity,
		attribute = .Name,
		revision = revision,
		basis = basis,
		added = added,
	}
	ctx.log_datom_count += 1
}

component_record_ref :: proc(ctx: ^Component_Context, basis: u64, added: bool) {
	ctx.log_datoms[ctx.log_datom_count] = Component_Log_Datom {
		entity = 1,
		attribute = .Component,
		ref = 2,
		basis = basis,
		added = added,
	}
	ctx.log_datom_count += 1
}

component_log_invariant :: proc(
	t: ^pbt.T,
	ctx: ^Component_Context,
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
	if !value_ok || vev.kind(transactions_value) != .Vector ||
	   vev.item_count(transactions_value) != ctx.transaction_count {
		return pbt.fail(fmt.tprintf(
			"%s transaction count: expected=%d actual=%d",
			backend,
			ctx.transaction_count,
			vev.item_count(transactions_value),
		))
	}
	matched: [COMPONENT_LOG_DATOM_COUNT]bool
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
			actual, application, parse_ok := component_log_datom(t, value, expected_basis)
			if !datom_ok || !parse_ok {
				return pbt.error(fmt.tprintf("%s transaction %d has malformed datom", backend, transaction_index))
			}
			if !application {
				continue
			}
			actual_count += 1
			found := false
			for expected_index in 0 ..< ctx.log_datom_count {
				if !matched[expected_index] && component_log_equal(actual, ctx.log_datoms[expected_index]) {
					matched[expected_index] = true
					found = true
					break
				}
			}
			if !found {
				return pbt.fail(fmt.tprintf("%s transaction %d has unexpected component datom", backend, transaction_index))
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
			return pbt.fail(fmt.tprintf("%s omitted component datom %d", backend, expected_index))
		}
	}
	return pbt.pass()
}

component_log_datom :: proc(
	t: ^pbt.T,
	value: vev.Value,
	expected_basis: u64,
) -> (datom: Component_Log_Datom, application, ok: bool) {
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
	if attribute != ":tree/name" && attribute != ":tree/component" {
		return {}, false, true
	}
	entity, entity_value_ok := vev.as_entity(entity_value)
	tx, tx_entity_ok := vev.as_entity(tx_value)
	added, added_bool_ok := vev.as_bool(added_value)
	if !entity_value_ok || !tx_entity_ok || !added_bool_ok || tx != vev.t_to_tx(expected_basis) {
		return {}, true, false
	}
	if attribute == ":tree/component" {
		ref, ref_ok := vev.as_entity(fact_value)
		if !ref_ok {
			return {}, true, false
		}
		return Component_Log_Datom {
			entity = entity,
			attribute = .Component,
			ref = ref,
			basis = expected_basis,
			added = added,
		}, true, true
	}
	name, name_ok := vev.as_string(fact_value, t.value_allocator)
	if !name_ok {
		return {}, true, false
	}
	revision, revision_ok := component_name_revision(entity, name)
	if !revision_ok {
		return {}, true, false
	}
	return Component_Log_Datom {
		entity = entity,
		attribute = .Name,
		revision = revision,
		basis = expected_basis,
		added = added,
	}, true, true
}

component_log_equal :: proc(left, right: Component_Log_Datom) -> bool {
	return left.entity == right.entity && left.attribute == right.attribute &&
	       left.revision == right.revision && left.ref == right.ref &&
	       left.basis == right.basis && left.added == right.added
}

component_name_revision :: proc(entity: u64, name: string) -> (revision: int, ok: bool) {
	for candidate in 0 ..= COMPONENT_COMMAND_COUNT {
		expected := ""
		if entity == 1 {
			expected = component_parent_name(candidate)
		} else if entity == 2 {
			expected = component_child_name(candidate)
		} else {
			return 0, false
		}
		if name == expected {
			return candidate, true
		}
	}
	return 0, false
}

component_reopen_invariant :: proc(t: ^pbt.T, ctx: ^Component_Context) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(&ctx.durable)
	count_before, count_before_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read component coordinates before reopen")
	}
	vev.close(&ctx.durable)
	reopened_ok: bool
	ctx.durable, reopened_ok = vev.connect(&library, ctx.durable_path)
	if !reopened_ok {
		return pbt.error("could not reopen component durable connection")
	}
	basis_after, basis_after_ok := tempid_order_basis(&ctx.durable)
	count_after, count_after_ok := vev.connection_tx_count(&ctx.durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"component coordinates changed across reopen: basis=%d->%d count=%d->%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}
	database, database_ok := vev.db(&ctx.durable)
	if !database_ok {
		return pbt.error("could not retain reopened component database")
	}
	defer vev.close(&database)
	if result := component_database_invariant(t, ctx, &database, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "component-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d state=%v",
		basis_after,
		count_after,
		component_model_state(ctx),
	))
	return pbt.pass()
}

component_model_state :: proc(ctx: ^Component_Context) -> Component_State {
	if sc.is_active(&ctx.model, Component_State.Attached) {
		return .Attached
	}
	if sc.is_active(&ctx.model, Component_State.Cascaded) {
		return .Cascaded
	}
	if sc.is_active(&ctx.model, Component_State.Deleted) {
		return .Deleted
	}
	return .Ready
}

component_parent_name :: proc(revision: int) -> string {
	return fmt.tprintf("parent-%d", revision)
}

component_child_name :: proc(revision: int) -> string {
	return fmt.tprintf("child-%d", revision)
}

component_event_name :: proc(event: Component_Event) -> string {
	switch event {
	case .Attach:
		return "attach"
	case .Rename_Parent:
		return "rename-parent"
	case .Rename_Child:
		return "rename-child"
	case .Retract_Component:
		return "retract-component"
	case .Retract_Parent:
		return "retract-parent"
	case .Restore_Component:
		return "restore-component"
	case .Restore_Tree:
		return "restore-tree"
	}
	return "unknown"
}

component_state_detail :: proc(state: ^Component_Context) -> string {
	return fmt.tprintf(
		"state=%v parent-revision=%d child-revision=%d",
		component_model_state(state),
		state.parent_revision,
		state.child_revision,
	)
}

component_value_detail :: proc(observation: Component_Observation) -> string {
	return fmt.tprintf(
		"state=%v resident=%v durable=%v basis=%d/%d",
		observation.model_state,
		observation.resident_committed,
		observation.durable_committed,
		observation.resident_basis_after,
		observation.durable_basis_after,
	)
}
