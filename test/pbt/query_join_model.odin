package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

QUERY_JOIN_TAGS := [?]string{"core", "query", "datalog", "prepared", "model", "durable", "differential", "join", "predicate", "permutation", "reopen"}
QUERY_JOIN_MAX_ENTITIES :: 12

QUERY_JOIN_SCHEMA :: `[
	{:db/id 100 :db/ident :query/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :query/age :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :query/tag :db/valueType :db.type/string :db/cardinality :db.cardinality/many}
	{:db/id 103 :db/ident :query/friend :db/valueType :db.type/ref :db/cardinality :db.cardinality/one}
]`

QUERY_JOIN_CLAUSES := [?]string {
	"[?e :query/name ?name]",
	"[?e :query/age ?age]",
	"[?e :query/tag ?selected-tag]",
	"[?e :query/friend ?friend]",
	"[?friend :query/name ?friend-name]",
}

Query_Join_Case :: struct {
	stem:              string,
	entity_count:      int,
	age_offset:        int,
	age_step:          int,
	threshold:         int,
	friend_jump:       int,
	selected_tag:      int,
	tag_masks:         [2]u64,
	permutation_index: int,
	reverse_seed:      bool,
}

query_join_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Query_Join_Case {
		stem = pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8)),
		entity_count = pbt.draw(t, pbt.int_range(2, QUERY_JOIN_MAX_ENTITIES)),
		age_offset = pbt.draw(t, pbt.int_range(0, 59)),
		age_step = pbt.draw(t, pbt.int_range(1, 17)),
		threshold = pbt.draw(t, pbt.int_range(0, 59)),
		selected_tag = pbt.draw(t, pbt.int_range(0, 1)),
		permutation_index = pbt.draw(t, pbt.int_range(0, 119)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.friend_jump = pbt.draw(t, pbt.int_range(0, scenario.entity_count - 1))
	mask_limit := (u64(1) << u64(scenario.entity_count)) - 1
	scenario.tag_masks[0] = pbt.draw(t, pbt.u64_range(0, mask_limit))
	scenario.tag_masks[1] = pbt.draw(t, pbt.u64_range(0, mask_limit))
	expected_count := query_join_expected_count(scenario)
	pbt.cover(t, expected_count == 0, 15, "query-empty-relation")
	pbt.cover(t, expected_count > 0, 55, "query-nonempty-relation")
	pbt.cover(t, expected_count == scenario.entity_count, 2, "query-full-relation")
	pbt.cover(t, scenario.friend_jump == 0, 5, "query-self-join")
	pbt.cover(t, scenario.friend_jump != 0, 70, "query-friend-join")
	pbt.cover(t, scenario.permutation_index == 0, 0, "query-canonical-order")
	pbt.cover(t, scenario.permutation_index != 0, 90, "query-permuted-order")
	pbt.cover(t, scenario.reverse_seed, 35, "query-reverse-seed-order")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create query-model resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate query-model durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create query-model durable connection")
	}
	defer vev.close(&durable)

	seed := query_join_seed_edn(t, scenario)
	setup_transactions := [?]string{QUERY_JOIN_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_committed := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") || !durable_committed {
			return pbt.error(fmt.tprintf(
				"could not initialize query model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	basis_before, basis_before_ok := tempid_order_basis(&durable)
	count_before, count_before_ok := vev.connection_tx_count(&durable)
	if !basis_before_ok || !count_before_ok {
		return pbt.error("could not read query-model durable coordinates")
	}
	canonical := query_join_edn(t, scenario, 0)
	permuted := query_join_edn(t, scenario, scenario.permutation_index)
	canonical_prepared, canonical_prepared_ok := vev.prepare(&library, canonical)
	if !canonical_prepared_ok {
		return pbt.error(fmt.tprintf("could not prepare canonical query: %s", canonical))
	}
	defer vev.close(&canonical_prepared)
	permuted_prepared, permuted_prepared_ok := vev.prepare(&library, permuted)
	if !permuted_prepared_ok {
		return pbt.error(fmt.tprintf("could not prepare permuted query: %s", permuted))
	}
	defer vev.close(&permuted_prepared)
	pbt.note(t, fmt.tprintf(
		"query-model entities=%d expected=%d canonical=%s permuted=%s",
		scenario.entity_count,
		expected_count,
		canonical,
		permuted,
	))
	if result := query_join_connection_check(t, &resident, &canonical_prepared, scenario, canonical, "resident canonical"); result.status != .Pass {
		return result
	}
	if result := query_join_connection_check(t, &resident, &permuted_prepared, scenario, permuted, "resident permuted"); result.status != .Pass {
		return result
	}
	if result := query_join_connection_check(t, &durable, &canonical_prepared, scenario, canonical, "durable canonical"); result.status != .Pass {
		return result
	}
	if result := query_join_connection_check(t, &durable, &permuted_prepared, scenario, permuted, "durable permuted"); result.status != .Pass {
		return result
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"queries changed durable coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen query-model durable connection")
	}
	if result := query_join_connection_check(t, &durable, &canonical_prepared, scenario, canonical, "durable reopened canonical"); result.status != .Pass {
		return result
	}
	if result := query_join_connection_check(t, &durable, &permuted_prepared, scenario, permuted, "durable reopened permuted"); result.status != .Pass {
		return result
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"query-model coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "query-model-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d rows=%d",
		reopened_basis,
		reopened_count,
		expected_count,
	))
	return pbt.pass()
}

query_join_seed_edn :: proc(t: ^pbt.T, scenario: Query_Join_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf(
			`[:db/add %d :query/name "%s"][:db/add %d :query/age %d][:db/add %d :query/friend %d]`,
			entity,
			query_join_name(scenario, entity),
			entity,
			query_join_age(scenario, entity),
			entity,
			query_join_friend(scenario, entity),
		))
		for tag in 0 ..< 2 {
			if query_join_has_tag(scenario, entity, tag) {
				append(&parts, fmt.tprintf(
					`[:db/add %d :query/tag "tag-%d"]`,
					entity,
					tag,
				))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

query_join_edn :: proc(t: ^pbt.T, scenario: Query_Join_Case, permutation_index: int) -> string {
	order := query_join_permutation(permutation_index)
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, `[:find ?e ?name ?friend ?friend-name :in $ ?selected-tag :where `)
	for index in order {
		append(&parts, QUERY_JOIN_CLAUSES[index])
	}
	append(&parts, fmt.tprintf(`[(>= ?age %d)]]`, scenario.threshold))
	return strings.concatenate(parts[:])
}

query_join_permutation :: proc(index: int) -> [5]int {
	available := [5]int{0, 1, 2, 3, 4}
	count := 5
	out: [5]int
	remainder := index
	for position in 0 ..< 5 {
		choice := remainder % count
		remainder /= count
		out[position] = available[choice]
		for move in choice ..< count - 1 {
			available[move] = available[move + 1]
		}
		count -= 1
	}
	return out
}

query_join_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	prepared: ^vev.Prepared_Query,
	scenario: Query_Join_Case,
	query: string,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s query database", backend))
	}
	defer vev.close(&database)
	return query_join_database_check(t, &database, prepared, scenario, query, backend)
}

query_join_database_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	prepared: ^vev.Prepared_Query,
	scenario: Query_Join_Case,
	query: string,
	backend: string,
) -> pbt.Result {
	inputs := fmt.tprintf(`["tag-%d"]`, scenario.selected_tag)
	text_result, query_ok := vev.query(database, query, inputs)
	if !query_ok {
		return pbt.fail(fmt.tprintf("%s query failed: %s", backend, query))
	}
	defer vev.close(&text_result)
	if result := query_join_result_check(t, &text_result, scenario, query, fmt.tprintf("%s text", backend)); result.status != .Pass {
		return result
	}

	prepared_result, prepared_query_ok := vev.query_db_prepared(database, prepared, inputs)
	if !prepared_query_ok {
		return pbt.fail(fmt.tprintf("%s prepared query failed: %s", backend, query))
	}
	defer vev.close(&prepared_result)
	return query_join_result_check(t, &prepared_result, scenario, query, fmt.tprintf("%s prepared", backend))
}

query_join_result_check :: proc(
	t: ^pbt.T,
	result: ^vev.Data,
	scenario: Query_Join_Case,
	query, backend: string,
) -> pbt.Result {
	relation, relation_ok := vev.value(result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s query relation unavailable", backend))
	}
	expected_count := query_join_expected_count(scenario)
	if vev.item_count(relation) != expected_count {
		return pbt.fail(fmt.tprintf(
			"%s query row count: expected=%d actual=%d query=%s",
			backend,
			expected_count,
			vev.item_count(relation),
			query,
		))
	}
	seen: [QUERY_JOIN_MAX_ENTITIES + 1]bool
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		entity_value, entity_ok := vev.item(row, 0)
		name_value, name_ok := vev.item(row, 1)
		friend_value, friend_ok := vev.item(row, 2)
		friend_name_value, friend_name_ok := vev.item(row, 3)
		entity, entity_value_ok := vev.as_int(entity_value)
		name, name_value_ok := vev.as_string(name_value, t.value_allocator)
		friend, friend_value_ok := vev.as_int(friend_value)
		friend_name, friend_name_value_ok := vev.as_string(friend_name_value, t.value_allocator)
		if !row_ok || !entity_ok || !name_ok || !friend_ok || !friend_name_ok ||
		   !entity_value_ok || !name_value_ok || !friend_value_ok || !friend_name_value_ok ||
		   entity < 1 || entity > i64(scenario.entity_count) || seen[entity] ||
		   !query_join_expected(scenario, int(entity)) ||
		   name != query_join_name(scenario, int(entity)) ||
		   friend != i64(query_join_friend(scenario, int(entity))) ||
		   friend_name != query_join_name(scenario, int(friend)) {
			return pbt.fail(fmt.tprintf(
				"%s unexpected query row: entity=%d name=%s friend=%d friend-name=%s",
				backend,
				entity,
				name,
				friend,
				friend_name,
			))
		}
		seen[entity] = true
	}
	for entity in 1 ..= scenario.entity_count {
		if seen[entity] != query_join_expected(scenario, entity) {
			return pbt.fail(fmt.tprintf("%s omitted expected query entity %d", backend, entity))
		}
	}
	return pbt.pass()
}

query_join_expected :: proc(scenario: Query_Join_Case, entity: int) -> bool {
	return query_join_has_tag(scenario, entity, scenario.selected_tag) &&
	       query_join_age(scenario, entity) >= scenario.threshold
}

query_join_expected_count :: proc(scenario: Query_Join_Case) -> int {
	count := 0
	for entity in 1 ..= scenario.entity_count {
		if query_join_expected(scenario, entity) {
			count += 1
		}
	}
	return count
}

query_join_has_tag :: proc(scenario: Query_Join_Case, entity, tag: int) -> bool {
	return (scenario.tag_masks[tag] & (u64(1) << u64(entity - 1))) != 0
}

query_join_age :: proc(scenario: Query_Join_Case, entity: int) -> int {
	return (scenario.age_offset + entity * scenario.age_step) % 60
}

query_join_friend :: proc(scenario: Query_Join_Case, entity: int) -> int {
	return ((entity - 1 + scenario.friend_jump) % scenario.entity_count) + 1
}

query_join_name :: proc(scenario: Query_Join_Case, entity: int) -> string {
	return fmt.tprintf("%s-person-%d", scenario.stem, entity)
}
