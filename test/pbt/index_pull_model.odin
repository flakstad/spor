// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

INDEX_PULL_TAGS := [?]string{"core", "index", "index-pull", "avet", "aevt", "pull", "pagination", "model", "durable", "differential", "mutation", "reopen"}

Index_Pull_Case :: struct {
	entity_count:      int,
	scores:            [INDEX_READ_MAX_ENTITIES]int,
	links:             [INDEX_READ_MAX_ENTITIES]u8,
	mutation_kind:     int,
	mutation_entity:   int,
	mutation_value:    int,
	avet_start:        int,
	aevt_start_entity: int,
	avet_bounded:      bool,
	aevt_bounded:      bool,
	avet_reverse:      bool,
	aevt_reverse:      bool,
	avet_offset:       int,
	aevt_offset:       int,
	avet_limit:        int,
	aevt_limit:        int,
	reverse_seed:      bool,
}

index_pull_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Index_Pull_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, INDEX_READ_MAX_ENTITIES)),
		mutation_kind = pbt.draw(t, pbt.int_range(0, 2)),
		avet_start = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1)),
		avet_bounded = pbt.draw(t, pbt.boolean()),
		aevt_bounded = pbt.draw(t, pbt.boolean()),
		avet_reverse = pbt.draw(t, pbt.boolean()),
		aevt_reverse = pbt.draw(t, pbt.boolean()),
		avet_offset = pbt.draw(t, pbt.int_range(0, 3)),
		aevt_offset = pbt.draw(t, pbt.int_range(0, 3)),
		avet_limit = index_pull_draw_limit(t),
		aevt_limit = index_pull_draw_limit(t),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_value = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
	scenario.aevt_start_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	force_empty_links := pbt.draw(t, pbt.int_range(0, 9)) == 0
	mask_limit := int((u16(1) << u8(scenario.entity_count)) - 1)
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
		if !force_empty_links {
			scenario.links[entity] = u8(pbt.draw(t, pbt.int_range(0, mask_limit)))
		}
	}
	final_scores := index_pull_final_scores(scenario)
	final_links := index_pull_final_links(scenario)
	avet_walk := index_pull_expected_avet(t, scenario, final_scores)
	aevt_walk := index_pull_expected_aevt(t, scenario, final_links)
	avet_count := index_pull_page_count(len(avet_walk), scenario.avet_offset, scenario.avet_limit)
	aevt_count := index_pull_page_count(len(aevt_walk), scenario.aevt_offset, scenario.aevt_limit)
	pbt.note(t, fmt.tprintf("index-pull scenario=%v", scenario))
	pbt.cover(t, scenario.mutation_kind == 0, 20, "index-pull-no-mutation")
	pbt.cover(t, scenario.mutation_kind == 1, 20, "index-pull-score-mutation")
	pbt.cover(t, scenario.mutation_kind == 2, 20, "index-pull-link-mutation")
	pbt.cover(t, scenario.avet_reverse, 35, "index-pull-avet-reverse")
	pbt.cover(t, scenario.aevt_reverse, 35, "index-pull-aevt-reverse")
	pbt.cover(t, !scenario.avet_bounded, 35, "index-pull-avet-attr-start")
	pbt.cover(t, !scenario.aevt_bounded, 35, "index-pull-aevt-attr-start")
	pbt.cover(t, scenario.avet_bounded && scenario.aevt_bounded, 20, "index-pull-bounded-starts")
	pbt.cover(t, scenario.avet_offset > 0 || scenario.aevt_offset > 0, 70, "index-pull-offset")
	pbt.cover(t, scenario.avet_limit < 0 || scenario.aevt_limit < 0, 30, "index-pull-unbounded-limit")
	pbt.cover(t, scenario.avet_limit == 0 || scenario.aevt_limit == 0, 30, "index-pull-zero-limit")
	pbt.cover(t, avet_count == 0 || aevt_count == 0, 35, "index-pull-empty-page")
	pbt.cover(t, avet_count > 1 || aevt_count > 1, 25, "index-pull-multi-page")
	pbt.cover(t, index_pull_has_duplicate(aevt_walk[:]), 10, "index-pull-duplicate-target")
	pbt.cover(t, index_read_mask_empty(scenario.entity_count, final_links), 2, "index-pull-empty-links")
	pbt.cover(t, scenario.reverse_seed, 35, "index-pull-reverse-seed")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create index-pull resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate index-pull durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create index-pull durable connection")
	}
	defer vev.close(&durable)

	seed := index_pull_seed_edn(t, scenario)
	setup := [?]string{INDEX_READ_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize index-pull model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutation_kind != 0 {
		mutation := index_pull_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate index-pull model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read index-pull durable coordinates")
	}
	if result := index_pull_connection_check(t, &resident, scenario, final_scores, avet_walk[:], aevt_walk[:], "resident"); result.status != .Pass {
		return result
	}
	if result := index_pull_connection_check(t, &durable, scenario, final_scores, avet_walk[:], aevt_walk[:], "durable"); result.status != .Pass {
		return result
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"index-pull changed coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen index-pull durable connection")
	}
	if result := index_pull_connection_check(t, &durable, scenario, final_scores, avet_walk[:], aevt_walk[:], "durable reopened"); result.status != .Pass {
		return result
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"index-pull coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	return pbt.pass()
}

index_pull_draw_limit :: proc(t: ^pbt.T) -> int {
	choice := pbt.draw(t, pbt.int_range(0, 4))
	if choice == 0 {
		return -1
	}
	return choice - 1
}

index_pull_seed_edn :: proc(t: ^pbt.T, scenario: Index_Pull_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf("[:db/add %d :index/score %d]", entity, scenario.scores[entity - 1]))
		for target in 1 ..= scenario.entity_count {
			if index_read_mask_has(scenario.links[entity - 1], target - 1) {
				append(&parts, fmt.tprintf("[:db/add %d :index/link %d]", entity, target))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

index_pull_mutation_edn :: proc(scenario: Index_Pull_Case) -> string {
	if scenario.mutation_kind == 1 {
		return fmt.tprintf(
			"[[:db/add %d :index/score %d]]",
			scenario.mutation_entity,
			scenario.mutation_value,
		)
	}
	target := scenario.mutation_value % scenario.entity_count + 1
	op := ":db/add"
	if index_read_mask_has(scenario.links[scenario.mutation_entity - 1], target - 1) {
		op = ":db/retract"
	}
	return fmt.tprintf("[[%s %d :index/link %d]]", op, scenario.mutation_entity, target)
}

index_pull_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Index_Pull_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	avet_walk, aevt_walk: []int,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s index-pull database", backend))
	}
	defer vev.close(&database)

	avet_start := "[:index/score]"
	if scenario.avet_bounded {
		avet_start = fmt.tprintf("[:index/score %d]", scenario.avet_start)
	}
	avet, avet_ok := vev.index_pull(
		&database,
		":avet",
		"[:db/id :index/score]",
		avet_start,
		scenario.avet_reverse,
		i64(scenario.avet_offset),
		i64(scenario.avet_limit),
	)
	if !avet_ok {
		return pbt.fail(fmt.tprintf("%s AVET index-pull failed", backend))
	}
	defer vev.close(&avet)
	if result := index_pull_data_check(t, &avet, avet_walk, scenario.avet_offset, scenario.avet_limit, scores, fmt.tprintf("%s AVET", backend)); result.status != .Pass {
		return result
	}

	aevt_start := "[:index/link]"
	if scenario.aevt_bounded {
		aevt_start = fmt.tprintf("[:index/link %d]", scenario.aevt_start_entity)
	}
	aevt, aevt_ok := vev.index_pull(
		&database,
		":aevt",
		"[:db/id :index/score]",
		aevt_start,
		scenario.aevt_reverse,
		i64(scenario.aevt_offset),
		i64(scenario.aevt_limit),
	)
	if !aevt_ok {
		return pbt.fail(fmt.tprintf("%s AEVT index-pull failed", backend))
	}
	defer vev.close(&aevt)
	return index_pull_data_check(t, &aevt, aevt_walk, scenario.aevt_offset, scenario.aevt_limit, scores, fmt.tprintf("%s AEVT", backend))
}

index_pull_data_check :: proc(
	t: ^pbt.T,
	data: ^vev.Data,
	walk: []int,
	offset, limit: int,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	label: string,
) -> pbt.Result {
	value, value_ok := vev.value(data)
	start := min(offset, len(walk))
	end := len(walk)
	if limit >= 0 {
		end = min(end, start + limit)
	}
	expected_count := end - start
	if !value_ok || vev.kind(value) != .Vector || vev.item_count(value) != expected_count {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf(
			"%s index-pull count: expected=%d actual=%d data=%s",
			label,
			expected_count,
			vev.item_count(value),
			actual,
		))
	}
	for index in 0 ..< expected_count {
		pulled, pulled_ok := vev.item(value, index)
		id_value, id_ok := vev.get(pulled, ":db/id")
		score_value, score_ok := vev.get(pulled, ":index/score")
		entity, entity_ok := vev.as_entity(id_value)
		if !entity_ok {
			entity_int, entity_int_ok := vev.as_int(id_value)
			if entity_int_ok && entity_int >= 0 {
				entity = u64(entity_int)
				entity_ok = true
			}
		}
		score, score_value_ok := vev.as_int(score_value)
		expected_entity := walk[start + index]
		if !pulled_ok || vev.kind(pulled) != .Map || !id_ok || !score_ok ||
		   !entity_ok || !score_value_ok || entity != u64(expected_entity) ||
		   score != i64(scores[expected_entity - 1]) {
			actual, _ := vev.edn(pulled, t.value_allocator)
			return pbt.fail(fmt.tprintf(
				"%s index-pull row %d: expected entity=%d score=%d actual=%s",
				label,
				index,
				expected_entity,
				scores[expected_entity - 1],
				actual,
			))
		}
	}
	return pbt.pass()
}

index_pull_expected_avet :: proc(
	t: ^pbt.T,
	scenario: Index_Pull_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
) -> [dynamic]int {
	out := make([dynamic]int, t.value_allocator)
	if scenario.avet_reverse {
		for reverse_value in 0 ..< INDEX_READ_VALUE_COUNT {
			value := INDEX_READ_VALUE_COUNT - reverse_value - 1
			if scenario.avet_bounded && value > scenario.avet_start {
				continue
			}
			for reverse_entity in 0 ..< scenario.entity_count {
				entity := scenario.entity_count - reverse_entity
				if scores[entity - 1] == value {
					append(&out, entity)
				}
			}
		}
		return out
	}
	start := 0
	if scenario.avet_bounded {
		start = scenario.avet_start
	}
	for value in start ..< INDEX_READ_VALUE_COUNT {
		for entity in 1 ..= scenario.entity_count {
			if scores[entity - 1] == value {
				append(&out, entity)
			}
		}
	}
	return out
}

index_pull_expected_aevt :: proc(
	t: ^pbt.T,
	scenario: Index_Pull_Case,
	links: [INDEX_READ_MAX_ENTITIES]u8,
) -> [dynamic]int {
	out := make([dynamic]int, t.value_allocator)
	if scenario.aevt_reverse {
		end_entity := scenario.entity_count
		if scenario.aevt_bounded {
			end_entity = scenario.aevt_start_entity
		}
		for reverse_entity in 0 ..< end_entity {
			entity := end_entity - reverse_entity
			for reverse_target in 0 ..< scenario.entity_count {
				target := scenario.entity_count - reverse_target
				if index_read_mask_has(links[entity - 1], target - 1) {
					append(&out, target)
				}
			}
		}
		return out
	}
	start_entity := 1
	if scenario.aevt_bounded {
		start_entity = scenario.aevt_start_entity
	}
	for entity in start_entity ..= scenario.entity_count {
		for target in 1 ..= scenario.entity_count {
			if index_read_mask_has(links[entity - 1], target - 1) {
				append(&out, target)
			}
		}
	}
	return out
}

index_pull_final_scores :: proc(scenario: Index_Pull_Case) -> [INDEX_READ_MAX_ENTITIES]int {
	out := scenario.scores
	if scenario.mutation_kind == 1 {
		out[scenario.mutation_entity - 1] = scenario.mutation_value
	}
	return out
}

index_pull_final_links :: proc(scenario: Index_Pull_Case) -> [INDEX_READ_MAX_ENTITIES]u8 {
	out := scenario.links
	if scenario.mutation_kind == 2 {
		target := scenario.mutation_value % scenario.entity_count
		out[scenario.mutation_entity - 1] = out[scenario.mutation_entity - 1] ~ (u8(1) << u8(target))
	}
	return out
}

index_pull_page_count :: proc(count, offset, limit: int) -> int {
	start := min(offset, count)
	if limit < 0 {
		return count - start
	}
	return min(count - start, limit)
}

index_pull_has_duplicate :: proc(values: []int) -> bool {
	for value, index in values {
		for earlier in 0 ..< index {
			if values[earlier] == value {
				return true
			}
		}
	}
	return false
}
