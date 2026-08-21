// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

INDEX_MAINTENANCE_TAGS := [?]string{"core", "durable", "index", "maintenance", "compaction", "history", "log", "snapshot", "reopen", "model"}
INDEX_MAINTENANCE_NAMES := [?]string{":eavt", ":aevt", ":avet", ":vaet"}

index_maintenance_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Index_Read_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, INDEX_READ_MAX_ENTITIES)),
		mutation_kind = pbt.draw(t, pbt.int_range(1, 3)),
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
	mask_limit := int((u16(1) << u8(scenario.entity_count)) - 1)
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
		scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << INDEX_READ_VALUE_COUNT) - 1)))
		scenario.links[entity] = u8(pbt.draw(t, pbt.int_range(0, mask_limit)))
	}
	maintenance_steps := pbt.draw(t, pbt.int_range(0, 4))
	maintenance_first := pbt.draw(t, pbt.boolean())
	repeat_compaction := pbt.draw(t, pbt.boolean())
	pbt.cover(t, scenario.mutation_kind == 1, 20, "maintenance-score-history")
	pbt.cover(t, scenario.mutation_kind == 2, 20, "maintenance-tag-history")
	pbt.cover(t, scenario.mutation_kind == 3, 20, "maintenance-link-history")
	pbt.cover(t, maintenance_steps == 0, 10, "maintenance-zero-budget")
	pbt.cover(t, maintenance_steps > 0, 60, "maintenance-positive-budget")
	pbt.cover(t, maintenance_first, 35, "maintenance-before-compaction")
	pbt.cover(t, repeat_compaction, 35, "maintenance-repeat-compaction")

	final_scores := index_read_final_scores(scenario)
	final_tags := index_read_final_tags(scenario)
	final_links := index_read_final_links(scenario)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate index-maintenance path")}
	defer transaction_model_remove_store(path)
	connection, connection_ok := vev.connect(&library, path)
	if !connection_ok {return pbt.error("could not create index-maintenance connection")}
	defer vev.close(&connection)

	seed := index_read_seed_edn(t, scenario)
	mutation := index_read_mutation_edn(scenario)
	setup := [?]string{INDEX_READ_SCHEMA, seed, mutation}
	for tx in setup {
		report, ok := vev.transact(&connection, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize index maintenance: tx=%s report=%s", tx, report))
		}
	}
	if result := index_read_connection_check(t, &connection, scenario, final_scores, final_tags, final_links, "maintenance before"); result.status != .Pass {return result}
	basis_before, basis_before_ok := vev.connection_basis_t(&connection)
	count_before, count_before_ok := vev.connection_tx_count(&connection)
	ids_before, ids_before_ok := vev.connection_tx_ids(&connection, t.value_allocator)
	history_before, history_before_ok := index_maintenance_history_edn(t, &connection)
	log_before, log_before_ok := index_maintenance_log_edn(t, &connection)
	if !basis_before_ok || !count_before_ok || !ids_before_ok || !history_before_ok || !log_before_ok {
		return pbt.error("could not capture index-maintenance checkpoint")
	}

	if maintenance_first {
		if !vev.maintain_indexes(&connection, maintenance_steps) {return pbt.fail("bounded index maintenance failed")}
		if !vev.compact_indexes(&connection) {return pbt.fail("index compaction failed after maintenance")}
	} else {
		if !vev.compact_indexes(&connection) {return pbt.fail("index compaction failed before maintenance")}
		if !vev.maintain_indexes(&connection, maintenance_steps) {return pbt.fail("bounded index maintenance failed after compaction")}
	}
	if !vev.ensure_resident(&connection) {return pbt.fail("ensure-resident failed after index maintenance")}
	if repeat_compaction && !vev.compact_indexes(&connection) {return pbt.fail("repeated index compaction failed")}
	for index_name in INDEX_MAINTENANCE_NAMES {
		_, count_ok := vev.latest_index_merge_run_count(&connection, index_name)
		if !count_ok {return pbt.fail(fmt.tprintf("index maintenance omitted merge-run metadata for %s", index_name))}
	}

	if result := index_maintenance_unchanged_check(
		t,
		&connection,
		scenario,
		final_scores,
		final_tags,
		final_links,
		basis_before,
		count_before,
		ids_before[:],
		history_before,
		log_before,
		"maintenance after",
	); result.status != .Pass {return result}

	vev.close(&connection)
	reopened_ok: bool
	connection, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen maintained index store")}
	return index_maintenance_unchanged_check(
		t,
		&connection,
		scenario,
		final_scores,
		final_tags,
		final_links,
		basis_before,
		count_before,
		ids_before[:],
		history_before,
		log_before,
		"maintenance reopened",
	)
}

index_maintenance_unchanged_check :: proc(
	t: ^pbt.T,
	connection: ^vev.Durable_Connection,
	scenario: Index_Read_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	tags, links: [INDEX_READ_MAX_ENTITIES]u8,
	expected_basis, expected_count: u64,
	expected_ids: []u64,
	expected_history, expected_log: string,
	backend: string,
) -> pbt.Result {
	basis, basis_ok := vev.connection_basis_t(connection)
	count, count_ok := vev.connection_tx_count(connection)
	ids, ids_ok := vev.connection_tx_ids(connection, t.value_allocator)
	history, history_ok := index_maintenance_history_edn(t, connection)
	log_text, log_ok := index_maintenance_log_edn(t, connection)
	if !basis_ok || !count_ok || !ids_ok || !history_ok || !log_ok {
		return pbt.error(fmt.tprintf("could not inspect %s index-maintenance state", backend))
	}
	if basis != expected_basis || count != expected_count ||
	   !backup_tx_ids_equal(expected_ids, ids[:]) || history != expected_history || log_text != expected_log {
		return pbt.fail(fmt.tprintf(
			"%s index maintenance changed durable history: basis=%d/%d count=%d/%d ids=%v/%v history-equal=%v log-equal=%v",
			backend,
			basis,
			expected_basis,
			count,
			expected_count,
			ids,
			expected_ids,
			history == expected_history,
			log_text == expected_log,
		))
	}
	return index_read_connection_check(t, connection, scenario, scores, tags, links, backend)
}

index_maintenance_history_edn :: proc(
	t: ^pbt.T,
	connection: ^vev.Durable_Connection,
) -> (text: string, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {return "", false}
	defer vev.close(&database)
	history, history_ok := vev.history(&database)
	if !history_ok {return "", false}
	defer vev.close(&history)
	datoms, datoms_ok := vev.datoms(&history, 0, ":eavt", "[]")
	if !datoms_ok {return "", false}
	defer vev.close(&datoms)
	return vev.edn(&datoms, t.value_allocator)
}

index_maintenance_log_edn :: proc(
	t: ^pbt.T,
	connection: ^vev.Durable_Connection,
) -> (text: string, ok: bool) {
	log_value, log_ok := vev.log(connection)
	if !log_ok {return "", false}
	defer vev.close(&log_value)
	transactions, transactions_ok := vev.tx_range_all(&log_value)
	if !transactions_ok {return "", false}
	defer vev.close(&transactions)
	return vev.edn(&transactions, t.value_allocator)
}
