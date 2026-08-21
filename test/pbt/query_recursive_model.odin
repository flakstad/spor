// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

QUERY_RECURSIVE_TAGS := [?]string{"core", "query", "datalog", "rules", "recursive", "fixpoint", "graph", "model", "durable", "differential", "cycle", "retract", "reopen"}
QUERY_RECURSIVE_MAX_ENTITIES :: 8

QUERY_RECURSIVE_SCHEMA :: `[
	{:db/id 100 :db/ident :graph/name :db/valueType :db.type/string}
	{:db/id 101 :db/ident :graph/edge :db/valueType :db.type/ref :db/cardinality :db.cardinality/many}
]`

QUERY_RECURSIVE_BASE_FIRST :: `{:find [?from ?to]
	:where [(reachable ?from ?to)]
	:rules [[(reachable ?x ?y) [?x :graph/edge ?y]]
	        [(reachable ?x ?y) [?x :graph/edge ?mid] (reachable ?mid ?y)]]}`

Query_Recursive_Case :: struct {
	entity_count:    int,
	edges:           [QUERY_RECURSIVE_MAX_ENTITIES]u64,
	mutate:          bool,
	mutation_source: int,
	mutation_target: int,
	reverse_seed:    bool,
}

query_recursive_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Query_Recursive_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, QUERY_RECURSIVE_MAX_ENTITIES)),
		mutate = pbt.draw(t, pbt.boolean()),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_source = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_target = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	mask_limit := (u64(1) << u64(scenario.entity_count)) - 1
	for source in 0 ..< scenario.entity_count {
		scenario.edges[source] = pbt.draw(t, pbt.u64_range(0, mask_limit))
	}
	final_edges := query_recursive_final_edges(scenario)
	closure := query_recursive_closure(scenario.entity_count, final_edges)
	pair_count := query_recursive_pair_count(scenario.entity_count, closure)
	has_cycle := query_recursive_has_cycle(scenario.entity_count, closure)
	has_isolated := query_recursive_has_isolated(scenario.entity_count, closure)
	pbt.cover(t, scenario.mutate, 35, "recursive-mutation")
	pbt.cover(t, !scenario.mutate, 35, "recursive-no-mutation")
	pbt.cover(t, scenario.reverse_seed, 35, "recursive-reverse-seed")
	pbt.cover(t, pair_count == 0, 2, "recursive-empty-closure")
	pbt.cover(t, pair_count > 0, 75, "recursive-nonempty-closure")
	pbt.cover(t, has_cycle, 35, "recursive-cycle")
	pbt.cover(t, has_isolated, 5, "recursive-isolated-entity")
	pbt.cover(t, pair_count == scenario.entity_count * scenario.entity_count, 5, "recursive-full-closure")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create recursive-model resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate recursive-model durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create recursive-model durable connection")
	}
	defer vev.close(&durable)

	seed := query_recursive_seed_edn(t, scenario)
	setup := [?]string{QUERY_RECURSIVE_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize recursive model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutate {
		mutation := query_recursive_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate recursive model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read recursive-model durable coordinates")
	}
	queries := [?]string{QUERY_RECURSIVE_BASE_FIRST}
	for query in queries {
		if result := query_recursive_connection_check(t, &resident, scenario, closure, query, "resident"); result.status != .Pass {
			return result
		}
		if result := query_recursive_connection_check(t, &durable, scenario, closure, query, "durable"); result.status != .Pass {
			return result
		}
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"recursive queries changed coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen recursive-model durable connection")
	}
	for query in queries {
		if result := query_recursive_connection_check(t, &durable, scenario, closure, query, "durable reopened"); result.status != .Pass {
			return result
		}
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"recursive coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "recursive-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d pairs=%d",
		reopened_basis,
		reopened_count,
		pair_count,
	))
	return pbt.pass()
}

query_recursive_seed_edn :: proc(t: ^pbt.T, scenario: Query_Recursive_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		source := offset + 1
		if scenario.reverse_seed {
			source = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf(`[:db/add %d :graph/name "node-%d"]`, source, source))
		for target in 1 ..= scenario.entity_count {
			if query_recursive_edge_has(scenario.edges, source, target) {
				append(&parts, fmt.tprintf("[:db/add %d :graph/edge %d]", source, target))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

query_recursive_mutation_edn :: proc(scenario: Query_Recursive_Case) -> string {
	op := ":db/add"
	if query_recursive_edge_has(scenario.edges, scenario.mutation_source, scenario.mutation_target) {
		op = ":db/retract"
	}
	return fmt.tprintf(
		"[[%s %d :graph/edge %d]]",
		op,
		scenario.mutation_source,
		scenario.mutation_target,
	)
}

query_recursive_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Query_Recursive_Case,
	expected: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
	query: string,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s recursive database", backend))
	}
	defer vev.close(&database)
	result, query_ok := vev.query(&database, query)
	if !query_ok {
		return pbt.fail(fmt.tprintf("%s recursive query failed: %s", backend, query))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s recursive relation unavailable", backend))
	}
	actual: [QUERY_RECURSIVE_MAX_ENTITIES]u64
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		from_value, from_value_ok := vev.item(row, 0)
		to_value, to_value_ok := vev.item(row, 1)
		from, from_ok := vev.as_int(from_value)
		to, to_ok := vev.as_int(to_value)
		if !row_ok || !from_value_ok || !to_value_ok || !from_ok || !to_ok ||
		   from < 1 || from > i64(scenario.entity_count) || to < 1 || to > i64(scenario.entity_count) {
			return pbt.fail(fmt.tprintf("%s recursive query returned invalid pair %d -> %d", backend, from, to))
		}
		bit := u64(1) << u64(to - 1)
		if (actual[from - 1] & bit) != 0 {
			return pbt.fail(fmt.tprintf("%s recursive query duplicated pair %d -> %d", backend, from, to))
		}
		actual[from - 1] |= bit
	}
	for source in 0 ..< scenario.entity_count {
		if actual[source] != expected[source] {
			return pbt.fail(fmt.tprintf(
				"%s recursive closure row %d: expected=%02x actual=%02x query=%s",
				backend,
				source + 1,
				expected[source],
				actual[source],
				query,
			))
		}
	}
	return pbt.pass()
}

query_recursive_final_edges :: proc(scenario: Query_Recursive_Case) -> [QUERY_RECURSIVE_MAX_ENTITIES]u64 {
	out := scenario.edges
	if scenario.mutate {
		bit := u64(1) << u64(scenario.mutation_target - 1)
		source := scenario.mutation_source - 1
		out[source] = out[source] ~ bit
	}
	return out
}

query_recursive_closure :: proc(
	entity_count: int,
	edges: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
) -> [QUERY_RECURSIVE_MAX_ENTITIES]u64 {
	out := edges
	for middle in 0 ..< entity_count {
		middle_bit := u64(1) << u64(middle)
		for source in 0 ..< entity_count {
			if (out[source] & middle_bit) != 0 {
				out[source] |= out[middle]
			}
		}
	}
	return out
}

query_recursive_pair_count :: proc(
	entity_count: int,
	closure: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
) -> int {
	count := 0
	for source in 0 ..< entity_count {
		for target in 0 ..< entity_count {
			if (closure[source] & (u64(1) << u64(target))) != 0 {
				count += 1
			}
		}
	}
	return count
}

query_recursive_has_cycle :: proc(
	entity_count: int,
	closure: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
) -> bool {
	for entity in 0 ..< entity_count {
		if (closure[entity] & (u64(1) << u64(entity))) != 0 {
			return true
		}
	}
	return false
}

query_recursive_has_isolated :: proc(
	entity_count: int,
	closure: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
) -> bool {
	for entity in 0 ..< entity_count {
		if closure[entity] != 0 {
			continue
		}
		incoming := false
		for source in 0 ..< entity_count {
			if (closure[source] & (u64(1) << u64(entity))) != 0 {
				incoming = true
				break
			}
		}
		if !incoming {
			return true
		}
	}
	return false
}

query_recursive_edge_has :: proc(
	edges: [QUERY_RECURSIVE_MAX_ENTITIES]u64,
	source, target: int,
) -> bool {
	return (edges[source - 1] & (u64(1) << u64(target - 1))) != 0
}
