package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

QUERY_AGGREGATE_TAGS := [?]string{"core", "query", "datalog", "aggregate", "model", "durable", "differential", "group", "duplicate", "retract", "permutation", "reopen"}
QUERY_AGGREGATE_MAX_ENTITIES :: 16
QUERY_AGGREGATE_MAX_GROUPS :: 4

QUERY_AGGREGATE_SCHEMA :: `[
	{:db/id 100 :db/ident :aggregate/group :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :aggregate/amount :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
]`

Query_Aggregate_Case :: struct {
	entity_count:      int,
	group_count:       int,
	amount_offset:     int,
	amount_step:       int,
	amount_modulus:    int,
	threshold:         int,
	mutation_kind:     int,
	mutation_entity:   int,
	mutation_value:    int,
	permutation_index: int,
	reverse_seed:      bool,
}

Query_Aggregate_Expected :: struct {
	present:        bool,
	count:          int,
	distinct_count: int,
	sum:            int,
	min:            int,
	max:            int,
	amounts_seen:   [32]bool,
}

query_aggregate_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Query_Aggregate_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, QUERY_AGGREGATE_MAX_ENTITIES)),
		group_count = pbt.draw(t, pbt.int_range(1, QUERY_AGGREGATE_MAX_GROUPS)),
		amount_offset = pbt.draw(t, pbt.int_range(-10, 10)),
		amount_step = pbt.draw(t, pbt.int_range(1, 9)),
		amount_modulus = pbt.draw(t, pbt.int_range(1, 8)),
		threshold = pbt.draw(t, pbt.int_range(-10, 15)),
		mutation_kind = pbt.draw(t, pbt.int_range(0, 3)),
		permutation_index = pbt.draw(t, pbt.int_range(0, 1)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_value = pbt.draw(t, pbt.int_range(-10, 15))
	expected := query_aggregate_expected(scenario)
	expected_groups := query_aggregate_expected_group_count(expected)
	has_duplicate := query_aggregate_has_duplicate(expected)
	has_fractional_avg := query_aggregate_has_fractional_avg(expected)
	pbt.cover(t, expected_groups == 0, 5, "aggregate-empty")
	pbt.cover(t, expected_groups > 0, 50, "aggregate-nonempty")
	pbt.cover(t, expected_groups > 1, 20, "aggregate-multiple-groups")
	pbt.cover(t, has_duplicate, 20, "aggregate-duplicate-values")
	pbt.cover(t, has_fractional_avg, 15, "aggregate-fractional-average")
	pbt.cover(t, scenario.mutation_kind == 0, 15, "aggregate-no-mutation")
	pbt.cover(t, scenario.mutation_kind == 1, 15, "aggregate-replace-amount")
	pbt.cover(t, scenario.mutation_kind == 2, 15, "aggregate-retract-group")
	pbt.cover(t, scenario.mutation_kind == 3, 15, "aggregate-replace-group")
	pbt.cover(t, scenario.permutation_index == 0, 35, "aggregate-canonical-order")
	pbt.cover(t, scenario.permutation_index != 0, 35, "aggregate-permuted-order")
	pbt.cover(t, scenario.reverse_seed, 35, "aggregate-reverse-seed")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create aggregate-model resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate aggregate-model durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create aggregate-model durable connection")
	}
	defer vev.close(&durable)

	seed := query_aggregate_seed_edn(t, scenario)
	setup_transactions := [?]string{QUERY_AGGREGATE_SCHEMA, seed}
	for tx in setup_transactions {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize aggregate model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutation_kind != 0 {
		mutation := query_aggregate_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate aggregate model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read aggregate-model durable coordinates")
	}
	canonical := query_aggregate_edn(t, scenario, 0)
	permuted := query_aggregate_edn(t, scenario, scenario.permutation_index)
	pbt.note(t, fmt.tprintf(
		"aggregate entities=%d groups=%d expected-groups=%d canonical=%s permuted=%s",
		scenario.entity_count,
		scenario.group_count,
		expected_groups,
		canonical,
		permuted,
	))
	queries := [?]string{canonical, permuted}
	for query in queries {
		if result := query_aggregate_connection_check(t, &resident, scenario, expected, query, "resident"); result.status != .Pass {
			return result
		}
		if result := query_aggregate_connection_check(t, &durable, scenario, expected, query, "durable"); result.status != .Pass {
			return result
		}
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"aggregate queries changed durable coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen aggregate-model durable connection")
	}
	for query in queries {
		if result := query_aggregate_connection_check(t, &durable, scenario, expected, query, "durable reopened"); result.status != .Pass {
			return result
		}
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"aggregate coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "aggregate-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d groups=%d",
		reopened_basis,
		reopened_count,
		expected_groups,
	))
	return pbt.pass()
}

query_aggregate_seed_edn :: proc(t: ^pbt.T, scenario: Query_Aggregate_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf(
			`[:db/add %d :aggregate/group "group-%d"][:db/add %d :aggregate/amount %d]`,
			entity,
			query_aggregate_group(scenario, entity),
			entity,
			query_aggregate_base_amount(scenario, entity),
		))
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

query_aggregate_mutation_edn :: proc(scenario: Query_Aggregate_Case) -> string {
	switch scenario.mutation_kind {
	case 1:
		return fmt.tprintf(
			"[[:db/add %d :aggregate/amount %d]]",
			scenario.mutation_entity,
			scenario.mutation_value,
		)
	case 2:
		return fmt.tprintf(
			`[[:db/retract %d :aggregate/group "group-%d"]]`,
			scenario.mutation_entity,
			query_aggregate_group(scenario, scenario.mutation_entity),
		)
	case 3:
		return fmt.tprintf(
			`[[:db/add %d :aggregate/group "group-%d"]]`,
			scenario.mutation_entity,
			(query_aggregate_group(scenario, scenario.mutation_entity) + 1) % scenario.group_count,
		)
	}
	return "[]"
}

query_aggregate_edn :: proc(t: ^pbt.T, scenario: Query_Aggregate_Case, permutation_index: int) -> string {
	clauses := [2]string{
		"[?e :aggregate/group ?group]",
		"[?e :aggregate/amount ?amount]",
	}
	order := query_aggregate_permutation(permutation_index)
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[:find ?group (count ?amount) (count-distinct ?amount) (sum ?amount) (min ?amount) (max ?amount) (avg ?amount) :with ?e :where ")
	for index in order {
		append(&parts, clauses[index])
	}
	append(&parts, fmt.tprintf("[(>= ?amount %d)]]", scenario.threshold))
	return strings.concatenate(parts[:])
}

query_aggregate_permutation :: proc(index: int) -> [2]int {
	available := [2]int{0, 1}
	count := 2
	out: [2]int
	remainder := index
	for position in 0 ..< 2 {
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

query_aggregate_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Query_Aggregate_Case,
	expected: [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected,
	query: string,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s aggregate database", backend))
	}
	defer vev.close(&database)
	result, query_ok := vev.query(&database, query)
	if !query_ok {
		return pbt.fail(fmt.tprintf("%s aggregate query failed: %s", backend, query))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok {
		return pbt.error(fmt.tprintf("%s aggregate relation unavailable", backend))
	}
	expected_groups := query_aggregate_expected_group_count(expected)
	if vev.item_count(relation) != expected_groups {
		return pbt.fail(fmt.tprintf(
			"%s aggregate group count: expected=%d actual=%d query=%s",
			backend,
			expected_groups,
			vev.item_count(relation),
			query,
		))
	}
	seen: [QUERY_AGGREGATE_MAX_GROUPS]bool
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		if !row_ok || vev.item_count(row) != 7 {
			return pbt.fail(fmt.tprintf("%s aggregate row had wrong width", backend))
		}
		group_value, group_ok := vev.item(row, 0)
		group_text, group_text_ok := vev.as_string(group_value, t.value_allocator)
		group := query_aggregate_parse_group(group_text)
		if !group_ok || !group_text_ok || group < 0 || group >= scenario.group_count || seen[group] || !expected[group].present {
			return pbt.fail(fmt.tprintf("%s unexpected aggregate group %s", backend, group_text))
		}
		if result := query_aggregate_row_check(t, row, expected[group], backend, group); result.status != .Pass {
			return result
		}
		seen[group] = true
	}
	for group in 0 ..< scenario.group_count {
		if seen[group] != expected[group].present {
			return pbt.fail(fmt.tprintf("%s omitted aggregate group %d", backend, group))
		}
	}
	return pbt.pass()
}

query_aggregate_row_check :: proc(
	t: ^pbt.T,
	row: vev.Value,
	expected: Query_Aggregate_Expected,
	backend: string,
	group: int,
) -> pbt.Result {
	actual: [5]int
	for index in 0 ..< 5 {
		value, value_ok := vev.item(row, index + 1)
		parsed, parsed_ok := vev.as_int(value)
		if !value_ok || !parsed_ok {
			return pbt.fail(fmt.tprintf("%s group %d aggregate %d was not an integer", backend, group, index))
		}
		actual[index] = int(parsed)
	}
	wanted := [5]int{expected.count, expected.distinct_count, expected.sum, expected.min, expected.max}
	if actual != wanted {
		return pbt.fail(fmt.tprintf(
			"%s group %d aggregates: expected=%v actual=%v",
			backend,
			group,
			wanted,
			actual,
		))
	}
	avg_value, avg_value_ok := vev.item(row, 6)
	if expected.sum % expected.count == 0 {
		avg, avg_ok := vev.as_int(avg_value)
		if !avg_value_ok || !avg_ok || avg != i64(expected.sum / expected.count) {
			return pbt.fail(fmt.tprintf("%s group %d integer average mismatch", backend, group))
		}
	} else {
		avg, avg_ok := vev.as_float(avg_value)
		expected_avg := f64(expected.sum) / f64(expected.count)
		if !avg_value_ok || !avg_ok || avg != expected_avg {
			return pbt.fail(fmt.tprintf(
				"%s group %d average: expected=%f actual=%f",
				backend,
				group,
				expected_avg,
				avg,
			))
		}
	}
	return pbt.pass()
}

query_aggregate_expected :: proc(scenario: Query_Aggregate_Case) -> [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected {
	out: [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected
	for entity in 1 ..= scenario.entity_count {
		group, active := query_aggregate_final_group(scenario, entity)
		amount := query_aggregate_final_amount(scenario, entity)
		if !active || amount < scenario.threshold {
			continue
		}
		entry := &out[group]
		if !entry.present {
			entry.present = true
			entry.min = amount
			entry.max = amount
		}
		entry.count += 1
		entry.sum += amount
		entry.min = min(entry.min, amount)
		entry.max = max(entry.max, amount)
		amount_index := amount + 10
		if !entry.amounts_seen[amount_index] {
			entry.amounts_seen[amount_index] = true
			entry.distinct_count += 1
		}
	}
	return out
}

query_aggregate_expected_group_count :: proc(expected: [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected) -> int {
	count := 0
	for entry in expected {
		if entry.present {
			count += 1
		}
	}
	return count
}

query_aggregate_has_duplicate :: proc(expected: [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected) -> bool {
	for entry in expected {
		if entry.count > entry.distinct_count {
			return true
		}
	}
	return false
}

query_aggregate_has_fractional_avg :: proc(expected: [QUERY_AGGREGATE_MAX_GROUPS]Query_Aggregate_Expected) -> bool {
	for entry in expected {
		if entry.present && entry.sum % entry.count != 0 {
			return true
		}
	}
	return false
}

query_aggregate_final_group :: proc(scenario: Query_Aggregate_Case, entity: int) -> (group: int, active: bool) {
	group = query_aggregate_group(scenario, entity)
	if entity != scenario.mutation_entity {
		return group, true
	}
	switch scenario.mutation_kind {
	case 2:
		return group, false
	case 3:
		return (group + 1) % scenario.group_count, true
	}
	return group, true
}

query_aggregate_final_amount :: proc(scenario: Query_Aggregate_Case, entity: int) -> int {
	if scenario.mutation_kind == 1 && entity == scenario.mutation_entity {
		return scenario.mutation_value
	}
	return query_aggregate_base_amount(scenario, entity)
}

query_aggregate_group :: proc(scenario: Query_Aggregate_Case, entity: int) -> int {
	return (entity - 1) % scenario.group_count
}

query_aggregate_base_amount :: proc(scenario: Query_Aggregate_Case, entity: int) -> int {
	return scenario.amount_offset + (entity * scenario.amount_step) % scenario.amount_modulus
}

query_aggregate_parse_group :: proc(text: string) -> int {
	for group in 0 ..< QUERY_AGGREGATE_MAX_GROUPS {
		if text == fmt.tprintf("group-%d", group) {
			return group
		}
	}
	return -1
}
