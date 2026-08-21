// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

INDEX_READ_TAGS := [?]string{"core", "index", "datoms", "eavt", "aevt", "avet", "vaet", "index-range", "model", "durable", "differential", "mutation", "reopen"}
INDEX_READ_MAX_ENTITIES :: 8
INDEX_READ_VALUE_COUNT :: 8

INDEX_READ_SCHEMA :: `[
	{:db/id 100 :db/ident :index/score :db/valueType :db.type/long :db/cardinality :db.cardinality/one :db/index true}
	{:db/id 101 :db/ident :index/tag :db/valueType :db.type/long :db/cardinality :db.cardinality/many :db/index true}
	{:db/id 102 :db/ident :index/link :db/valueType :db.type/ref :db/cardinality :db.cardinality/many}
]`

Index_Read_Case :: struct {
	entity_count:     int,
	scores:           [INDEX_READ_MAX_ENTITIES]int,
	tags:             [INDEX_READ_MAX_ENTITIES]u8,
	links:            [INDEX_READ_MAX_ENTITIES]u8,
	mutation_kind:    int,
	mutation_entity:  int,
	mutation_value:   int,
	selected_entity:  int,
	selected_target:  int,
	range_start:      int,
	range_end:        int,
	has_range_start:  bool,
	has_range_end:    bool,
	reverse_seed:     bool,
}

Index_Read_Datom :: struct {
	entity: int,
	attr:   string,
	value:  int,
	is_ref: bool,
}

index_read_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Index_Read_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, INDEX_READ_MAX_ENTITIES)),
		mutation_kind = pbt.draw(t, pbt.int_range(0, 3)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
		has_range_start = pbt.draw(t, pbt.boolean()),
		has_range_end = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_value = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
	scenario.selected_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.selected_target = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	first_bound := pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
	second_bound := pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
	scenario.range_start = min(first_bound, second_bound)
	scenario.range_end = max(first_bound, second_bound)
	force_empty_tags := pbt.draw(t, pbt.int_range(0, 9)) == 0
	force_empty_links := pbt.draw(t, pbt.int_range(0, 9)) == 0
	mask_limit := int((u16(1) << u8(scenario.entity_count)) - 1)
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
		if !force_empty_tags {
			scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << INDEX_READ_VALUE_COUNT) - 1)))
		}
		if !force_empty_links {
			scenario.links[entity] = u8(pbt.draw(t, pbt.int_range(0, mask_limit)))
		}
	}
	final_scores := index_read_final_scores(scenario)
	final_tags := index_read_final_tags(scenario)
	final_links := index_read_final_links(scenario)
	range_count := index_read_range_count(scenario, final_scores)
	pbt.note(t, fmt.tprintf("index-read scenario=%v", scenario))
	pbt.cover(t, scenario.mutation_kind == 0, 15, "index-read-no-mutation")
	pbt.cover(t, scenario.mutation_kind == 1, 15, "index-read-score-mutation")
	pbt.cover(t, scenario.mutation_kind == 2, 15, "index-read-tag-mutation")
	pbt.cover(t, scenario.mutation_kind == 3, 15, "index-read-link-mutation")
	pbt.cover(t, scenario.reverse_seed, 35, "index-read-reverse-seed")
	pbt.cover(t, !scenario.has_range_start, 20, "index-read-unbounded-start")
	pbt.cover(t, !scenario.has_range_end, 20, "index-read-unbounded-end")
	pbt.cover(t, range_count == 0, 5, "index-read-empty-range")
	pbt.cover(t, range_count > 1, 35, "index-read-multi-range")
	pbt.cover(t, index_read_mask_empty(scenario.entity_count, final_tags), 2, "index-read-empty-tag-index")
	pbt.cover(t, index_read_mask_empty(scenario.entity_count, final_links), 2, "index-read-empty-link-index")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create index-read resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate index-read durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create index-read durable connection")
	}
	defer vev.close(&durable)

	seed := index_read_seed_edn(t, scenario)
	setup := [?]string{INDEX_READ_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize index-read model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutation_kind != 0 {
		mutation := index_read_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate index-read model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read index-read durable coordinates")
	}
	if result := index_read_connection_check(t, &resident, scenario, final_scores, final_tags, final_links, "resident"); result.status != .Pass {
		return result
	}
	if result := index_read_connection_check(t, &durable, scenario, final_scores, final_tags, final_links, "durable"); result.status != .Pass {
		return result
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"index reads changed coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen index-read durable connection")
	}
	if result := index_read_connection_check(t, &durable, scenario, final_scores, final_tags, final_links, "durable reopened"); result.status != .Pass {
		return result
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"index-read coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "index-read-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d entities=%d",
		reopened_basis,
		reopened_count,
		scenario.entity_count,
	))
	return pbt.pass()
}

index_read_seed_edn :: proc(t: ^pbt.T, scenario: Index_Read_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf("[:db/add %d :index/score %d]", entity, scenario.scores[entity - 1]))
		for value in 0 ..< INDEX_READ_VALUE_COUNT {
			if index_read_mask_has(scenario.tags[entity - 1], value) {
				append(&parts, fmt.tprintf("[:db/add %d :index/tag %d]", entity, value))
			}
		}
		for target in 1 ..= scenario.entity_count {
			if index_read_mask_has(scenario.links[entity - 1], target - 1) {
				append(&parts, fmt.tprintf("[:db/add %d :index/link %d]", entity, target))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

index_read_mutation_edn :: proc(scenario: Index_Read_Case) -> string {
	entity := scenario.mutation_entity
	switch scenario.mutation_kind {
	case 1:
		return fmt.tprintf("[[:db/add %d :index/score %d]]", entity, scenario.mutation_value)
	case 2:
		op := ":db/add"
		if index_read_mask_has(scenario.tags[entity - 1], scenario.mutation_value) {
			op = ":db/retract"
		}
		return fmt.tprintf("[[%s %d :index/tag %d]]", op, entity, scenario.mutation_value)
	case 3:
		target := scenario.mutation_value % scenario.entity_count + 1
		op := ":db/add"
		if index_read_mask_has(scenario.links[entity - 1], target - 1) {
			op = ":db/retract"
		}
		return fmt.tprintf("[[%s %d :index/link %d]]", op, entity, target)
	}
	return "[]"
}

index_read_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Index_Read_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	tags, links: [INDEX_READ_MAX_ENTITIES]u8,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s index-read database", backend))
	}
	defer vev.close(&database)

	eavt_expected := index_read_expected_eavt(t, scenario, scores, tags, links)
	if result := index_read_datoms_check(t, &database, 0, ":eavt", fmt.tprintf("[%d]", scenario.selected_entity), eavt_expected[:], backend); result.status != .Pass {
		return result
	}
	aevt_expected := index_read_expected_aevt_tags(t, scenario.entity_count, tags)
	if result := index_read_datoms_check(t, &database, 0, ":aevt", "[:index/tag]", aevt_expected[:], backend); result.status != .Pass {
		return result
	}
	avet_expected := index_read_expected_avet_scores(t, scenario.entity_count, scores)
	if result := index_read_datoms_check(t, &database, 0, ":avet", "[:index/score]", avet_expected[:], backend); result.status != .Pass {
		return result
	}
	vaet_expected := index_read_expected_vaet(t, scenario.entity_count, scenario.selected_target, links)
	if result := index_read_datoms_check(t, &database, 0, ":vaet", fmt.tprintf("[%d]", scenario.selected_target), vaet_expected[:], backend); result.status != .Pass {
		return result
	}
	range_expected := index_read_expected_range(t, scenario, scores)
	start := "nil"
	if scenario.has_range_start {
		start = fmt.tprintf("%d", scenario.range_start)
	}
	end := "nil"
	if scenario.has_range_end {
		end = fmt.tprintf("%d", scenario.range_end)
	}
	range_data, range_ok := vev.index_range(&database, ":index/score", start, end)
	if !range_ok {
		return pbt.fail(fmt.tprintf("%s index-range failed for %s..%s", backend, start, end))
	}
	defer vev.close(&range_data)
	if result := index_read_data_check(t, &range_data, range_expected[:], fmt.tprintf("%s index-range", backend)); result.status != .Pass {
		return result
	}
	return pbt.pass()
}

index_read_datoms_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	mode: int,
	index, components: string,
	expected: []Index_Read_Datom,
	backend: string,
) -> pbt.Result {
	data, ok := vev.datoms(database, mode, index, components)
	if !ok {
		return pbt.fail(fmt.tprintf("%s %s datoms failed for %s", backend, index, components))
	}
	defer vev.close(&data)
	return index_read_data_check(t, &data, expected, fmt.tprintf("%s %s %s", backend, index, components))
}

index_read_data_check :: proc(
	t: ^pbt.T,
	data: ^vev.Data,
	expected: []Index_Read_Datom,
	label: string,
) -> pbt.Result {
	value, value_ok := vev.value(data)
	if !value_ok || vev.kind(value) != .Vector || vev.item_count(value) != len(expected) {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf(
			"%s row count: expected=%d actual=%d data=%s",
			label,
			len(expected),
			vev.item_count(value),
			actual,
		))
	}
	for index in 0 ..< len(expected) {
		row, row_ok := vev.item(value, index)
		entity_value, entity_ok := vev.get(row, ":e")
		attr_value, attr_ok := vev.get(row, ":a")
		stored_value, stored_ok := vev.get(row, ":v")
		tx_value, tx_ok := vev.get(row, ":tx")
		added_value, added_ok := vev.get(row, ":added")
		entity, entity_value_ok := vev.as_entity(entity_value)
		attr, attr_value_ok := vev.as_string(attr_value, t.value_allocator)
		_, tx_value_ok := vev.as_entity(tx_value)
		added, added_value_ok := vev.as_bool(added_value)
		actual_value: i64
		actual_value_ok := false
		if expected[index].is_ref {
			ref, ref_ok := vev.as_entity(stored_value)
			actual_value = i64(ref)
			actual_value_ok = ref_ok
		} else {
			actual_value, actual_value_ok = vev.as_int(stored_value)
		}
		if !row_ok || vev.kind(row) != .Map ||
		   !entity_ok || !attr_ok || !stored_ok || !tx_ok || !added_ok ||
		   !entity_value_ok || !attr_value_ok || !actual_value_ok || !tx_value_ok || !added_value_ok || !added ||
		   entity != u64(expected[index].entity) || attr != expected[index].attr || actual_value != i64(expected[index].value) {
			actual, _ := vev.edn(row, t.value_allocator)
			all_actual, _ := vev.edn(value, t.value_allocator)
			return pbt.fail(fmt.tprintf(
				"%s row %d: expected=[%d %s %d ref=%v] actual=%s data=%s",
				label,
				index,
				expected[index].entity,
				expected[index].attr,
				expected[index].value,
				expected[index].is_ref,
				actual,
				all_actual,
			))
		}
	}
	return pbt.pass()
}

index_read_expected_eavt :: proc(
	t: ^pbt.T,
	scenario: Index_Read_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	tags, links: [INDEX_READ_MAX_ENTITIES]u8,
) -> [dynamic]Index_Read_Datom {
	out := make([dynamic]Index_Read_Datom, t.value_allocator)
	entity := scenario.selected_entity
	for target in 1 ..= scenario.entity_count {
		if index_read_mask_has(links[entity - 1], target - 1) {
			append(&out, Index_Read_Datom{entity = entity, attr = ":index/link", value = target, is_ref = true})
		}
	}
	append(&out, Index_Read_Datom{entity = entity, attr = ":index/score", value = scores[entity - 1]})
	for value in 0 ..< INDEX_READ_VALUE_COUNT {
		if index_read_mask_has(tags[entity - 1], value) {
			append(&out, Index_Read_Datom{entity = entity, attr = ":index/tag", value = value})
		}
	}
	return out
}

index_read_expected_aevt_tags :: proc(
	t: ^pbt.T,
	entity_count: int,
	tags: [INDEX_READ_MAX_ENTITIES]u8,
) -> [dynamic]Index_Read_Datom {
	out := make([dynamic]Index_Read_Datom, t.value_allocator)
	for entity in 1 ..= entity_count {
		for value in 0 ..< INDEX_READ_VALUE_COUNT {
			if index_read_mask_has(tags[entity - 1], value) {
				append(&out, Index_Read_Datom{entity = entity, attr = ":index/tag", value = value})
			}
		}
	}
	return out
}

index_read_expected_avet_scores :: proc(
	t: ^pbt.T,
	entity_count: int,
	scores: [INDEX_READ_MAX_ENTITIES]int,
) -> [dynamic]Index_Read_Datom {
	out := make([dynamic]Index_Read_Datom, t.value_allocator)
	for value in 0 ..< INDEX_READ_VALUE_COUNT {
		for entity in 1 ..= entity_count {
			if scores[entity - 1] == value {
				append(&out, Index_Read_Datom{entity = entity, attr = ":index/score", value = value})
			}
		}
	}
	return out
}

index_read_expected_vaet :: proc(
	t: ^pbt.T,
	entity_count, target: int,
	links: [INDEX_READ_MAX_ENTITIES]u8,
) -> [dynamic]Index_Read_Datom {
	out := make([dynamic]Index_Read_Datom, t.value_allocator)
	for entity in 1 ..= entity_count {
		if index_read_mask_has(links[entity - 1], target - 1) {
			append(&out, Index_Read_Datom{entity = entity, attr = ":index/link", value = target, is_ref = true})
		}
	}
	return out
}

index_read_expected_range :: proc(
	t: ^pbt.T,
	scenario: Index_Read_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
) -> [dynamic]Index_Read_Datom {
	out := make([dynamic]Index_Read_Datom, t.value_allocator)
	for value in 0 ..< INDEX_READ_VALUE_COUNT {
		if scenario.has_range_start && value < scenario.range_start {
			continue
		}
		if scenario.has_range_end && value > scenario.range_end {
			continue
		}
		for entity in 1 ..= scenario.entity_count {
			if scores[entity - 1] == value {
				append(&out, Index_Read_Datom{entity = entity, attr = ":index/score", value = value})
			}
		}
	}
	return out
}

index_read_final_scores :: proc(scenario: Index_Read_Case) -> [INDEX_READ_MAX_ENTITIES]int {
	out := scenario.scores
	if scenario.mutation_kind == 1 {
		out[scenario.mutation_entity - 1] = scenario.mutation_value
	}
	return out
}

index_read_final_tags :: proc(scenario: Index_Read_Case) -> [INDEX_READ_MAX_ENTITIES]u8 {
	out := scenario.tags
	if scenario.mutation_kind == 2 {
		index := scenario.mutation_entity - 1
		out[index] = out[index] ~ (u8(1) << u8(scenario.mutation_value))
	}
	return out
}

index_read_final_links :: proc(scenario: Index_Read_Case) -> [INDEX_READ_MAX_ENTITIES]u8 {
	out := scenario.links
	if scenario.mutation_kind == 3 {
		index := scenario.mutation_entity - 1
		target := scenario.mutation_value % scenario.entity_count
		out[index] = out[index] ~ (u8(1) << u8(target))
	}
	return out
}

index_read_range_count :: proc(
	scenario: Index_Read_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
) -> int {
	count := 0
	for entity in 0 ..< scenario.entity_count {
		value := scores[entity]
		if (!scenario.has_range_start || value >= scenario.range_start) &&
		   (!scenario.has_range_end || value <= scenario.range_end) {
			count += 1
		}
	}
	return count
}

index_read_mask_empty :: proc(
	entity_count: int,
	masks: [INDEX_READ_MAX_ENTITIES]u8,
) -> bool {
	for entity in 0 ..< entity_count {
		if masks[entity] != 0 {
			return false
		}
	}
	return true
}

index_read_mask_has :: proc(mask: u8, value: int) -> bool {
	return (mask & (u8(1) << u8(value))) != 0
}
