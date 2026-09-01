package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

QUERY_LOGIC_TAGS := [?]string{"core", "query", "datalog", "model", "durable", "differential", "or", "or-join", "not", "not-join", "retract", "reopen"}
QUERY_LOGIC_MAX_ENTITIES :: 16

QUERY_LOGIC_SCHEMA :: `[
	{:db/id 100 :db/ident :logic/name :db/valueType :db.type/string}
	{:db/id 101 :db/ident :logic/a :db/valueType :db.type/boolean}
	{:db/id 102 :db/ident :logic/b :db/valueType :db.type/boolean}
	{:db/id 103 :db/ident :logic/c :db/valueType :db.type/boolean}
	{:db/id 104 :db/ident :logic/blocked :db/valueType :db.type/boolean}
]`

QUERY_LOGIC_ATTRS := [?]string{":logic/a", ":logic/b", ":logic/c", ":logic/blocked"}

Query_Logic_Case :: struct {
	entity_count:    int,
	masks:           [4]u64,
	mutate:          bool,
	mutation_attr:   int,
	mutation_entity: int,
	reverse_seed:    bool,
}

Query_Logic_Variant :: enum {
	Or,
	Not,
	Or_Not,
	Or_Join,
	Not_Join,
}

query_logic_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Query_Logic_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, QUERY_LOGIC_MAX_ENTITIES)),
		mutate = pbt.draw(t, pbt.boolean()),
		mutation_attr = pbt.draw(t, pbt.int_range(0, 3)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	mask_limit := (u64(1) << u64(scenario.entity_count)) - 1
	for index in 0 ..< len(scenario.masks) {
		scenario.masks[index] = pbt.draw(t, pbt.u64_range(0, mask_limit))
	}
	final_masks := query_logic_final_masks(scenario)
	pbt.cover(t, scenario.mutate, 35, "logic-mutation")
	pbt.cover(t, !scenario.mutate, 35, "logic-no-mutation")
	pbt.cover(t, scenario.reverse_seed, 35, "logic-reverse-seed")
	pbt.cover(t, (final_masks[0] & final_masks[1]) != 0, 20, "logic-overlapping-or-branches")
	pbt.cover(t, query_logic_expected_mask(scenario, final_masks, .Or_Not) == 0, 5, "logic-empty-result")
	pbt.cover(t, query_logic_expected_mask(scenario, final_masks, .Or_Not) != 0, 45, "logic-nonempty-result")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create query-logic resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate query-logic durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create query-logic durable connection")
	}
	defer vev.close(&durable)

	seed := query_logic_seed_edn(t, scenario)
	setup := [?]string{QUERY_LOGIC_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize query-logic model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutate {
		mutation := query_logic_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate query-logic model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read query-logic durable coordinates")
	}
	variants := [?]Query_Logic_Variant{.Or, .Not, .Or_Not, .Or_Join, .Not_Join}
	for variant in variants {
		query := query_logic_edn(variant)
		expected := query_logic_expected_mask(scenario, final_masks, variant)
		pbt.note(t, fmt.tprintf("query-logic variant=%v expected=%016x query=%s", variant, expected, query))
		if result := query_logic_connection_check(t, &resident, scenario, query, expected, "resident"); result.status != .Pass {
			return result
		}
		if result := query_logic_connection_check(t, &durable, scenario, query, expected, "durable"); result.status != .Pass {
			return result
		}
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"query-logic queries changed coordinates: basis=%d/%d count=%d/%d",
			basis_before,
			basis_after,
			count_before,
			count_after,
		))
	}

	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {
		return pbt.error("could not reopen query-logic durable connection")
	}
	for variant in variants {
		query := query_logic_edn(variant)
		expected := query_logic_expected_mask(scenario, final_masks, variant)
		if result := query_logic_connection_check(t, &durable, scenario, query, expected, "durable reopened"); result.status != .Pass {
			return result
		}
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"query-logic coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "query-logic-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d entities=%d",
		reopened_basis,
		reopened_count,
		scenario.entity_count,
	))
	return pbt.pass()
}

query_logic_seed_edn :: proc(t: ^pbt.T, scenario: Query_Logic_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf(`[:db/add %d :logic/name "entity-%d"]`, entity, entity))
		for attr in 0 ..< len(scenario.masks) {
			if query_logic_mask_has(scenario.masks[attr], entity) {
				append(&parts, fmt.tprintf(
					"[:db/add %d %s true]",
					entity,
					QUERY_LOGIC_ATTRS[attr],
				))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

query_logic_mutation_edn :: proc(scenario: Query_Logic_Case) -> string {
	op := ":db/add"
	if query_logic_mask_has(scenario.masks[scenario.mutation_attr], scenario.mutation_entity) {
		op = ":db/retract"
	}
	return fmt.tprintf(
		"[[:%s %d %s true]]",
		op[1:],
		scenario.mutation_entity,
		QUERY_LOGIC_ATTRS[scenario.mutation_attr],
	)
}

query_logic_edn :: proc(variant: Query_Logic_Variant) -> string {
	switch variant {
	case .Or:
		return "[:find ?e :where [?e :logic/name] (or [?e :logic/a true] [?e :logic/b true])]"
	case .Not:
		return "[:find ?e :where [?e :logic/name] (not [?e :logic/blocked true])]"
	case .Or_Not:
		return "[:find ?e :where [?e :logic/name] (or [?e :logic/a true] [?e :logic/b true]) (not [?e :logic/blocked true])]"
	case .Or_Join:
		return "[:find ?e :where [?e :logic/name] (or-join [?e] (and [?e :logic/a true] [?e :logic/b true]) [?e :logic/c true])]"
	case .Not_Join:
		return "[:find ?e :where [?e :logic/name] (not-join [?e] [?e :logic/blocked true] [?e :logic/c true])]"
	}
	return "[]"
}

query_logic_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Query_Logic_Case,
	query: string,
	expected: u64,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s query-logic database", backend))
	}
	defer vev.close(&database)
	result, query_ok := vev.query(&database, query)
	if !query_ok {
		return pbt.fail(fmt.tprintf("%s query-logic query failed: %s", backend, query))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s query-logic relation unavailable", backend))
	}
	actual: u64
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		entity_value, entity_value_ok := vev.item(row, 0)
		entity, entity_ok := vev.as_int(entity_value)
		if !row_ok || !entity_value_ok || !entity_ok || entity < 1 || entity > i64(scenario.entity_count) {
			return pbt.fail(fmt.tprintf("%s query-logic returned invalid entity %d", backend, entity))
		}
		bit := u64(1) << u64(entity - 1)
		if (actual & bit) != 0 {
			return pbt.fail(fmt.tprintf("%s query-logic duplicated entity %d", backend, entity))
		}
		actual |= bit
	}
	if actual != expected {
		return pbt.fail(fmt.tprintf(
			"%s query-logic result: expected=%016x actual=%016x query=%s",
			backend,
			expected,
			actual,
			query,
		))
	}
	return pbt.pass()
}

query_logic_final_masks :: proc(scenario: Query_Logic_Case) -> [4]u64 {
	out: [4]u64 = scenario.masks
	if scenario.mutate {
		bit := u64(1) << u64(scenario.mutation_entity - 1)
		switch scenario.mutation_attr {
		case 0:
			out[0] = out[0] ~ bit
		case 1:
			out[1] = out[1] ~ bit
		case 2:
			out[2] = out[2] ~ bit
		case 3:
			out[3] = out[3] ~ bit
		}
	}
	return out
}

query_logic_expected_mask :: proc(
	scenario: Query_Logic_Case,
	masks: [4]u64,
	variant: Query_Logic_Variant,
) -> u64 {
	domain := (u64(1) << u64(scenario.entity_count)) - 1
	switch variant {
	case .Or:
		return (masks[0] | masks[1]) & domain
	case .Not:
		return (~masks[3]) & domain
	case .Or_Not:
		return (masks[0] | masks[1]) & (~masks[3]) & domain
	case .Or_Join:
		return ((masks[0] & masks[1]) | masks[2]) & domain
	case .Not_Join:
		return (~(masks[3] & masks[2])) & domain
	}
	return 0
}

query_logic_mask_has :: proc(mask: u64, entity: int) -> bool {
	return (mask & (u64(1) << u64(entity - 1))) != 0
}
