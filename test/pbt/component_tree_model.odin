package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

COMPONENT_TREE_TAGS := [?]string{"core", "transaction", "model", "durable", "differential", "component", "cascade", "recursive", "cardinality-many", "retract", "log", "reopen"}
COMPONENT_TREE_MAX_NODES :: 15

COMPONENT_TREE_SCHEMA :: `[
	{:db/id 100 :db/ident :forest/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :forest/children :db/valueType :db.type/ref :db/cardinality :db.cardinality/many :db/isComponent true}
]`

Component_Tree_Case :: struct {
	stem:           string,
	node_count:     int,
	target:         int,
	retract_entity: bool,
	reverse_seed:   bool,
}

Component_Tree_Log_Datom :: struct {
	entity:    int,
	child:     int,
	name_fact: bool,
}

component_tree_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Component_Tree_Case {
		stem = pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8)),
		node_count = pbt.draw(t, pbt.int_range(2, COMPONENT_TREE_MAX_NODES)),
		retract_entity = pbt.draw(t, pbt.boolean()),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.target = pbt.draw(t, pbt.int_range(1, scenario.node_count))
	deleted_count := component_tree_deleted_count(scenario)
	max_depth := component_tree_subtree_depth(scenario)
	pbt.cover(t, scenario.retract_entity, 35, "tree-retract-entity")
	pbt.cover(t, !scenario.retract_entity, 35, "tree-retract-attribute")
	pbt.cover(t, scenario.target == 1, 5, "tree-root-target")
	pbt.cover(t, scenario.target * 2 > scenario.node_count, 30, "tree-leaf-target")
	pbt.cover(t, scenario.target * 2 <= scenario.node_count, 30, "tree-interior-target")
	pbt.cover(t, max_depth >= 2, 10, "tree-multilevel-cascade")
	pbt.cover(t, deleted_count == 0, 10, "tree-noop-leaf-attribute")
	pbt.cover(t, scenario.reverse_seed, 35, "tree-reverse-seed-order")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create component-tree resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate component-tree durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create component-tree durable connection")
	}
	defer vev.close(&durable)

	seed := component_tree_seed_edn(t, scenario)
	setup_transactions := [?]string{COMPONENT_TREE_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize component tree: tx=%s resident=%s durable=%s",
				tx,
				resident_report,
				durable_report,
			))
		}
	}
	resident_checkpoint, resident_checkpoint_ok := tempid_order_basis(&resident)
	durable_checkpoint, durable_checkpoint_ok := tempid_order_basis(&durable)
	durable_count_before, count_before_ok := vev.connection_tx_count(&durable)
	if !resident_checkpoint_ok || !durable_checkpoint_ok || !count_before_ok ||
	   resident_checkpoint != durable_checkpoint {
		return pbt.error("could not establish component-tree checkpoint")
	}

	tx := component_tree_retract_edn(scenario)
	resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&durable, tx, t.value_allocator)
	pbt.note(t, fmt.tprintf(
		"component-tree nodes=%d target=%d deleted=%d depth=%d tx=%s resident=%s durable=%s",
		scenario.node_count,
		scenario.target,
		deleted_count,
		max_depth,
		tx,
		resident_report,
		durable_report,
	))
	if !resident_call_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
		return pbt.fail(fmt.tprintf(
			"component-tree retract did not commit: resident=%s durable=%s",
			resident_report,
			durable_report,
		))
	}
	resident_basis, resident_basis_ok := tempid_order_basis(&resident)
	durable_basis, durable_basis_ok := tempid_order_basis(&durable)
	durable_count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !resident_basis_ok || !durable_basis_ok || !count_after_ok ||
	   resident_basis != resident_checkpoint + 1 || durable_basis != durable_checkpoint + 1 ||
	   resident_basis != durable_basis || durable_count_after != durable_count_before + 1 {
		return pbt.fail(fmt.tprintf(
			"component-tree coordinates: resident=%d->%d durable=%d->%d count=%d->%d",
			resident_checkpoint,
			resident_basis,
			durable_checkpoint,
			durable_basis,
			durable_count_before,
			durable_count_after,
		))
	}
	if result := component_tree_connection_invariant(t, &resident, scenario, "resident"); result.status != .Pass {
		return result
	}
	if result := component_tree_connection_invariant(t, &durable, scenario, "durable"); result.status != .Pass {
		return result
	}
	if result := component_tree_log_invariant(t, &resident, scenario, resident_checkpoint, resident_basis, "resident"); result.status != .Pass {
		return result
	}
	if result := component_tree_log_invariant(t, &durable, scenario, durable_checkpoint, durable_basis, "durable"); result.status != .Pass {
		return result
	}

	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {
		return pbt.error("could not reopen component-tree durable connection")
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != durable_basis ||
	   reopened_count != durable_count_after {
		return pbt.fail(fmt.tprintf(
			"component-tree coordinates changed across reopen: basis=%d/%d count=%d/%d",
			durable_basis,
			reopened_basis,
			durable_count_after,
			reopened_count,
		))
	}
	if result := component_tree_connection_invariant(t, &durable, scenario, "durable reopened"); result.status != .Pass {
		return result
	}
	if result := component_tree_log_invariant(t, &durable, scenario, durable_checkpoint, durable_basis, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "component-tree-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d deleted=%d",
		reopened_basis,
		reopened_count,
		deleted_count,
	))
	return pbt.pass()
}

component_tree_seed_edn :: proc(t: ^pbt.T, scenario: Component_Tree_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	if scenario.reverse_seed {
		for offset in 0 ..< scenario.node_count {
			node := scenario.node_count - offset
			append(&parts, component_tree_name_add(scenario, node))
		}
		for offset in 0 ..< scenario.node_count - 1 {
			child := scenario.node_count - offset
			append(&parts, component_tree_edge_add(child))
		}
	} else {
		for node in 1 ..= scenario.node_count {
			append(&parts, component_tree_name_add(scenario, node))
		}
		for child in 2 ..= scenario.node_count {
			append(&parts, component_tree_edge_add(child))
		}
	}
	append(&parts, `[:db/add 99 :forest/name "sentinel"]]`)
	return strings.concatenate(parts[:])
}

component_tree_name_add :: proc(scenario: Component_Tree_Case, node: int) -> string {
	return fmt.tprintf(`[:db/add %d :forest/name "%s"]`, node, component_tree_name(scenario, node))
}

component_tree_edge_add :: proc(child: int) -> string {
	return fmt.tprintf(`[:db/add %d :forest/children %d]`, child / 2, child)
}

component_tree_retract_edn :: proc(scenario: Component_Tree_Case) -> string {
	if scenario.retract_entity {
		return fmt.tprintf("[[:db.fn/retractEntity %d]]", scenario.target)
	}
	return fmt.tprintf("[[:db.fn/retractAttribute %d :forest/children]]", scenario.target)
}

component_tree_connection_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Component_Tree_Case,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s component-tree database", backend))
	}
	defer vev.close(&database)
	return component_tree_database_invariant(t, &database, scenario, backend)
}

component_tree_database_invariant :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: Component_Tree_Case,
	backend: string,
) -> pbt.Result {
	names, names_ok := vev.query(database, `[:find ?e ?name :where [?e :forest/name ?name]]`)
	if !names_ok {
		return pbt.error(fmt.tprintf("%s component-tree name query failed", backend))
	}
	defer vev.close(&names)
	names_value, names_value_ok := vev.value(&names)
	if !names_value_ok {
		return pbt.error(fmt.tprintf("%s component-tree names unavailable", backend))
	}
	seen_names: [COMPONENT_TREE_MAX_NODES + 1]bool
	sentinel_seen := false
	for row_index in 0 ..< vev.item_count(names_value) {
		row, row_ok := vev.item(names_value, row_index)
		entity_value, entity_ok := vev.item(row, 0)
		name_value, name_ok := vev.item(row, 1)
		entity, entity_value_ok := vev.as_int(entity_value)
		name, name_value_ok := vev.as_string(name_value, t.value_allocator)
		if !row_ok || !entity_ok || !name_ok || !entity_value_ok || !name_value_ok {
			return pbt.error(fmt.tprintf("%s component-tree name row is malformed", backend))
		}
		if entity == 99 {
			if sentinel_seen || name != "sentinel" {
				return pbt.fail(fmt.tprintf("%s component-tree sentinel mismatch", backend))
			}
			sentinel_seen = true
			continue
		}
		if entity < 1 || entity > i64(scenario.node_count) ||
		   component_tree_deleted(scenario, int(entity)) || seen_names[entity] ||
		   name != component_tree_name(scenario, int(entity)) {
			return pbt.fail(fmt.tprintf(
				"%s unexpected component-tree name: entity=%d name=%s",
				backend,
				entity,
				name,
			))
		}
		seen_names[entity] = true
	}
	if !sentinel_seen {
		return pbt.fail(fmt.tprintf("%s component-tree sentinel was deleted", backend))
	}
	for node in 1 ..= scenario.node_count {
		if seen_names[node] == component_tree_deleted(scenario, node) {
			return pbt.fail(fmt.tprintf("%s component-tree entity %d has wrong presence", backend, node))
		}
	}

	edges, edges_ok := vev.query(database, `[:find ?parent ?child :where [?parent :forest/children ?child]]`)
	if !edges_ok {
		return pbt.error(fmt.tprintf("%s component-tree edge query failed", backend))
	}
	defer vev.close(&edges)
	edges_value, edges_value_ok := vev.value(&edges)
	if !edges_value_ok {
		return pbt.error(fmt.tprintf("%s component-tree edges unavailable", backend))
	}
	seen_edges: [COMPONENT_TREE_MAX_NODES + 1]bool
	for row_index in 0 ..< vev.item_count(edges_value) {
		row, row_ok := vev.item(edges_value, row_index)
		parent_value, parent_ok := vev.item(row, 0)
		child_value, child_ok := vev.item(row, 1)
		parent, parent_value_ok := vev.as_int(parent_value)
		child, child_value_ok := vev.as_int(child_value)
		if !row_ok || !parent_ok || !child_ok || !parent_value_ok || !child_value_ok ||
		   child < 2 || child > i64(scenario.node_count) || parent != child / 2 ||
		   component_tree_deleted(scenario, int(child)) || seen_edges[child] {
			return pbt.fail(fmt.tprintf(
				"%s unexpected component-tree edge: parent=%d child=%d",
				backend,
				parent,
				child,
			))
		}
		seen_edges[child] = true
	}
	for child in 2 ..= scenario.node_count {
		if seen_edges[child] == component_tree_deleted(scenario, child) {
			return pbt.fail(fmt.tprintf("%s component-tree edge for %d has wrong presence", backend, child))
		}
	}
	return pbt.pass()
}

component_tree_log_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Component_Tree_Case,
	checkpoint, basis: u64,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s component-tree log", backend))
	}
	defer vev.close(&log_value)
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s component-tree log range failed", backend))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != 1 {
		return pbt.fail(fmt.tprintf("%s component-tree log range count is not one", backend))
	}
	transaction, transaction_ok := vev.item(transactions_value, 0)
	t_value, t_ok := vev.get(transaction, ":t")
	data, data_ok := vev.get(transaction, ":data")
	t_value_int, t_value_ok := vev.as_int(t_value)
	if !transaction_ok || !t_ok || !data_ok || !t_value_ok || t_value_int < 0 ||
	   u64(t_value_int) != basis || vev.kind(data) != .Vector {
		return pbt.error(fmt.tprintf("%s component-tree transaction is malformed", backend))
	}
	expected_count := component_tree_expected_log_count(scenario)
	seen_names: [COMPONENT_TREE_MAX_NODES + 1]bool
	seen_edges: [COMPONENT_TREE_MAX_NODES + 1]bool
	actual_count := 0
	for datom_index in 0 ..< vev.item_count(data) {
		value, datom_ok := vev.item(data, datom_index)
		datom, application, parse_ok := component_tree_log_datom(t, value, scenario, basis)
		if !datom_ok || !parse_ok {
			return pbt.error(fmt.tprintf("%s component-tree datom is malformed", backend))
		}
		if !application {
			continue
		}
		actual_count += 1
		if datom.name_fact {
			if !component_tree_deleted(scenario, datom.entity) || seen_names[datom.entity] {
				return pbt.fail(fmt.tprintf("%s unexpected component-tree name retraction for %d", backend, datom.entity))
			}
			seen_names[datom.entity] = true
		} else {
			if datom.child < 2 || !component_tree_deleted(scenario, datom.child) ||
			   datom.entity != datom.child / 2 || seen_edges[datom.child] {
				return pbt.fail(fmt.tprintf(
					"%s unexpected component-tree edge retraction %d->%d",
					backend,
					datom.entity,
					datom.child,
				))
			}
			seen_edges[datom.child] = true
		}
	}
	if actual_count != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s component-tree application datoms: expected=%d actual=%d",
			backend,
			expected_count,
			actual_count,
		))
	}
	for node in 1 ..= scenario.node_count {
		if seen_names[node] != component_tree_deleted(scenario, node) {
			return pbt.fail(fmt.tprintf("%s omitted component-tree name retraction for %d", backend, node))
		}
		if node > 1 && seen_edges[node] != component_tree_deleted(scenario, node) {
			return pbt.fail(fmt.tprintf("%s omitted component-tree edge retraction for %d", backend, node))
		}
	}
	return pbt.pass()
}

component_tree_log_datom :: proc(
	t: ^pbt.T,
	value: vev.Value,
	scenario: Component_Tree_Case,
	basis: u64,
) -> (datom: Component_Tree_Log_Datom, application, ok: bool) {
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
	if attribute != ":forest/name" && attribute != ":forest/children" {
		return {}, false, true
	}
	entity, entity_value_ok := vev.as_entity(entity_value)
	tx, tx_value_ok := vev.as_entity(tx_value)
	added, added_value_ok := vev.as_bool(added_value)
	if !entity_value_ok || !tx_value_ok || !added_value_ok || entity > COMPONENT_TREE_MAX_NODES ||
	   tx != vev.t_to_tx(basis) || added {
		return {}, true, false
	}
	if attribute == ":forest/name" {
		name, name_ok := vev.as_string(fact_value, t.value_allocator)
		if !name_ok || name != component_tree_name(scenario, int(entity)) {
			return {}, true, false
		}
		return Component_Tree_Log_Datom{entity = int(entity), name_fact = true}, true, true
	}
	child, child_ok := vev.as_entity(fact_value)
	if !child_ok || child > COMPONENT_TREE_MAX_NODES {
		return {}, true, false
	}
	return Component_Tree_Log_Datom{entity = int(entity), child = int(child)}, true, true
}

component_tree_deleted :: proc(scenario: Component_Tree_Case, node: int) -> bool {
	if !scenario.retract_entity && node == scenario.target {
		return false
	}
	cursor := node
	for cursor >= scenario.target {
		if cursor == scenario.target {
			return true
		}
		cursor /= 2
	}
	return false
}

component_tree_deleted_count :: proc(scenario: Component_Tree_Case) -> int {
	count := 0
	for node in 1 ..= scenario.node_count {
		if component_tree_deleted(scenario, node) {
			count += 1
		}
	}
	return count
}

component_tree_expected_log_count :: proc(scenario: Component_Tree_Case) -> int {
	deleted := component_tree_deleted_count(scenario)
	edges := deleted
	if component_tree_deleted(scenario, 1) {
		edges -= 1
	}
	return deleted + edges
}

component_tree_subtree_depth :: proc(scenario: Component_Tree_Case) -> int {
	depth := 0
	frontier := scenario.target
	for frontier * 2 <= scenario.node_count {
		depth += 1
		frontier *= 2
	}
	return depth
}

component_tree_name :: proc(scenario: Component_Tree_Case, node: int) -> string {
	return fmt.tprintf("%s-node-%d", scenario.stem, node)
}
