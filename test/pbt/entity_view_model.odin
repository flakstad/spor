// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

ENTITY_VIEW_TAGS := [?]string{"core", "entity", "entity-view", "touch", "attribute", "reverse-ref", "model", "durable", "differential", "mutation", "reopen"}

ENTITY_VIEW_SCHEMA :: `[
	{:db/id 100 :db/ident :view/score :db/valueType :db.type/long :db/cardinality :db.cardinality/one :db/index true}
	{:db/id 101 :db/ident :view/tag :db/valueType :db.type/long :db/cardinality :db.cardinality/many :db/index true}
	{:db/id 102 :db/ident :view/link :db/valueType :db.type/ref :db/cardinality :db.cardinality/many}
]`

Entity_View_Case :: struct {
	entity_count:    int,
	scores:          [INDEX_READ_MAX_ENTITIES]int,
	tags:            [INDEX_READ_MAX_ENTITIES]u8,
	links:           [INDEX_READ_MAX_ENTITIES]u8,
	mutation_kind:   int,
	mutation_entity: int,
	mutation_value:  int,
	selected_entity: int,
	selected_attr:   int,
	reverse_seed:    bool,
}

entity_view_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Entity_View_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, INDEX_READ_MAX_ENTITIES)),
		mutation_kind = pbt.draw(t, pbt.int_range(0, 3)),
		selected_attr = pbt.draw(t, pbt.int_range(0, 2)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_value = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
	scenario.selected_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	mask_limit := int((u16(1) << u8(scenario.entity_count)) - 1)
	force_empty_tags := pbt.draw(t, pbt.int_range(0, 9)) == 0
	force_empty_links := pbt.draw(t, pbt.int_range(0, 9)) == 0
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, INDEX_READ_VALUE_COUNT - 1))
		if !force_empty_tags {
			scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << INDEX_READ_VALUE_COUNT) - 1)))
		}
		if !force_empty_links {
			scenario.links[entity] = u8(pbt.draw(t, pbt.int_range(0, mask_limit)))
		}
	}
	final_scores := entity_view_final_scores(scenario)
	final_tags := entity_view_final_tags(scenario)
	final_links := entity_view_final_links(scenario)
	selected_tags := final_tags[scenario.selected_entity - 1]
	selected_links := final_links[scenario.selected_entity - 1]
	incoming := entity_view_incoming_mask(scenario.selected_entity, scenario.entity_count, final_links)

	pbt.note(t, fmt.tprintf("entity-view scenario=%v", scenario))
	pbt.cover(t, scenario.mutation_kind == 0, 15, "entity-view-no-mutation")
	pbt.cover(t, scenario.mutation_kind == 1, 15, "entity-view-score-mutation")
	pbt.cover(t, scenario.mutation_kind == 2, 15, "entity-view-tag-mutation")
	pbt.cover(t, scenario.mutation_kind == 3, 15, "entity-view-link-mutation")
	pbt.cover(t, selected_tags == 0, 5, "entity-view-no-selected-tags")
	pbt.cover(t, selected_links == 0, 5, "entity-view-no-selected-links")
	pbt.cover(t, incoming == 0, 5, "entity-view-no-incoming-links")
	pbt.cover(t, selected_tags != 0 && selected_links != 0 && incoming != 0, 15, "entity-view-rich-entity")
	pbt.cover(t, scenario.selected_attr == 0, 20, "entity-view-score-metadata")
	pbt.cover(t, scenario.selected_attr == 1, 20, "entity-view-tag-metadata")
	pbt.cover(t, scenario.selected_attr == 2, 20, "entity-view-link-metadata")
	pbt.cover(t, scenario.reverse_seed, 35, "entity-view-reverse-seed")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create entity-view resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate entity-view durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create entity-view durable connection")
	}
	defer vev.close(&durable)

	seed := entity_view_seed_edn(t, scenario)
	setup := [?]string{ENTITY_VIEW_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize entity-view model: resident=%s durable=%s", resident_report, durable_report))
		}
	}
	if scenario.mutation_kind != 0 {
		mutation := entity_view_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not mutate entity-view model: tx=%s resident=%s durable=%s", mutation, resident_report, durable_report))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read entity-view durable coordinates")
	}
	if result := entity_view_connection_check(t, &resident, scenario, final_scores, final_tags, final_links, "resident"); result.status != .Pass {
		return result
	}
	if result := entity_view_connection_check(t, &durable, scenario, final_scores, final_tags, final_links, "durable"); result.status != .Pass {
		return result
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf("entity views changed coordinates: basis=%d/%d count=%d/%d", basis_before, basis_after, count_before, count_after))
	}

	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {
		return pbt.error("could not reopen entity-view durable connection")
	}
	if result := entity_view_connection_check(t, &durable, scenario, final_scores, final_tags, final_links, "durable reopened"); result.status != .Pass {
		return result
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf("entity-view coordinates changed across reopen: basis=%d/%d count=%d/%d", basis_before, reopened_basis, count_before, reopened_count))
	}
	return pbt.pass()
}

entity_view_seed_edn :: proc(t: ^pbt.T, scenario: Entity_View_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf("[:db/add %d :view/score %d]", entity, scenario.scores[entity - 1]))
		for tag in 0 ..< INDEX_READ_VALUE_COUNT {
			if index_read_mask_has(scenario.tags[entity - 1], tag) {
				append(&parts, fmt.tprintf("[:db/add %d :view/tag %d]", entity, tag))
			}
		}
		for target in 1 ..= scenario.entity_count {
			if index_read_mask_has(scenario.links[entity - 1], target - 1) {
				append(&parts, fmt.tprintf("[:db/add %d :view/link %d]", entity, target))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

entity_view_mutation_edn :: proc(scenario: Entity_View_Case) -> string {
	if scenario.mutation_kind == 1 {
		return fmt.tprintf("[[:db/add %d :view/score %d]]", scenario.mutation_entity, scenario.mutation_value)
	}
	if scenario.mutation_kind == 2 {
		op := ":db/add"
		if index_read_mask_has(scenario.tags[scenario.mutation_entity - 1], scenario.mutation_value) {
			op = ":db/retract"
		}
		return fmt.tprintf("[[%s %d :view/tag %d]]", op, scenario.mutation_entity, scenario.mutation_value)
	}
	target := scenario.mutation_value % scenario.entity_count + 1
	op := ":db/add"
	if index_read_mask_has(scenario.links[scenario.mutation_entity - 1], target - 1) {
		op = ":db/retract"
	}
	return fmt.tprintf("[[%s %d :view/link %d]]", op, scenario.mutation_entity, target)
}

entity_view_final_tags :: proc(scenario: Entity_View_Case) -> [INDEX_READ_MAX_ENTITIES]u8 {
	out := scenario.tags
	if scenario.mutation_kind == 2 {
		out[scenario.mutation_entity - 1] = out[scenario.mutation_entity - 1] ~ (u8(1) << u8(scenario.mutation_value))
	}
	return out
}

entity_view_final_scores :: proc(scenario: Entity_View_Case) -> [INDEX_READ_MAX_ENTITIES]int {
	out := scenario.scores
	if scenario.mutation_kind == 1 {
		out[scenario.mutation_entity - 1] = scenario.mutation_value
	}
	return out
}

entity_view_final_links :: proc(scenario: Entity_View_Case) -> [INDEX_READ_MAX_ENTITIES]u8 {
	out := scenario.links
	if scenario.mutation_kind == 3 {
		target := scenario.mutation_value % scenario.entity_count
		out[scenario.mutation_entity - 1] = out[scenario.mutation_entity - 1] ~ (u8(1) << u8(target))
	}
	return out
}

entity_view_incoming_mask :: proc(target, entity_count: int, links: [INDEX_READ_MAX_ENTITIES]u8) -> u8 {
	mask: u8
	for source in 1 ..= entity_count {
		if index_read_mask_has(links[source - 1], target - 1) {
			mask |= u8(1) << u8(source - 1)
		}
	}
	return mask
}

entity_view_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Entity_View_Case,
	scores: [INDEX_READ_MAX_ENTITIES]int,
	tags, links: [INDEX_READ_MAX_ENTITIES]u8,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s entity-view database", backend))
	}
	defer vev.close(&database)

	if _, missing_ok := vev.entity(&database, u64(scenario.entity_count + 1)); missing_ok {
		return pbt.fail(fmt.tprintf("%s resolved a missing entity", backend))
	}
	selected := scenario.selected_entity
	entity_value, entity_ok := vev.entity(&database, u64(selected))
	if !entity_ok {
		return pbt.fail(fmt.tprintf("%s did not resolve entity %d", backend, selected))
	}
	defer vev.close(&entity_value)
	id, id_ok := vev.entity_id(&entity_value)
	if !id_ok || id != u64(selected) {
		return pbt.fail(fmt.tprintf("%s entity id: expected=%d actual=%d", backend, selected, id))
	}
	has_id := vev.entity_contains(&entity_value, ":db/id")
	has_score := vev.entity_contains(&entity_value, ":view/score")
	has_tag := vev.entity_contains(&entity_value, ":view/tag")
	has_link := vev.entity_contains(&entity_value, ":view/link")
	has_incoming := vev.entity_contains(&entity_value, ":_view/link")
	has_missing := vev.entity_contains(&entity_value, ":view/missing")
	if !has_id || !has_score || has_tag != (tags[selected - 1] != 0) ||
	   has_link != (links[selected - 1] != 0) ||
	   has_incoming != (entity_view_incoming_mask(selected, scenario.entity_count, links) != 0) || has_missing {
		return pbt.fail(fmt.tprintf("%s entity contains disagreed for entity %d: id=%v score=%v tag=%v/%v link=%v/%v incoming=%v/%v missing=%v", backend, selected, has_id, has_score, has_tag, tags[selected - 1] != 0, has_link, links[selected - 1] != 0, has_incoming, entity_view_incoming_mask(selected, scenario.entity_count, links) != 0, has_missing))
	}

	if result := entity_view_get_int_check(t, &entity_value, ":view/score", scores[selected - 1], true, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_get_int_check(t, &entity_value, ":view/tag", entity_view_first_set(tags[selected - 1]), tags[selected - 1] != 0, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_get_entity_check(t, &entity_value, ":view/link", entity_view_first_set(links[selected - 1]) + 1, links[selected - 1] != 0, backend); result.status != .Pass {
		return result
	}
	incoming := entity_view_incoming_mask(selected, scenario.entity_count, links)
	if result := entity_view_get_entity_check(t, &entity_value, ":_view/link", entity_view_first_set(incoming) + 1, incoming != 0, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_get_int_check(t, &entity_value, ":view/missing", 0, false, backend); result.status != .Pass {
		return result
	}

	if result := entity_view_values_check(t, &entity_value, ":db/id", u8(1) << u8(selected - 1), true, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_values_check(t, &entity_value, ":view/tag", tags[selected - 1], false, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_values_check(t, &entity_value, ":view/link", links[selected - 1], true, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_values_check(t, &entity_value, ":_view/link", incoming, true, backend); result.status != .Pass {
		return result
	}
	if result := entity_view_values_check(t, &entity_value, ":view/missing", 0, false, backend); result.status != .Pass {
		return result
	}

	touched, touch_ok := vev.entity_touch(&entity_value)
	if !touch_ok {
		return pbt.fail(fmt.tprintf("%s could not touch entity %d", backend, selected))
	}
	defer vev.close(&touched)
	if result := entity_view_touch_check(t, &touched, selected, scores[selected - 1], tags[selected - 1], links[selected - 1], backend); result.status != .Pass {
		return result
	}
	return entity_view_schema_check(t, &database, scenario.selected_attr, backend)
}

entity_view_get_int_check :: proc(t: ^pbt.T, entity_value: ^vev.Entity, attr: string, expected: int, present: bool, backend: string) -> pbt.Result {
	data, data_ok := vev.entity_get(entity_value, attr)
	if !data_ok {
		return pbt.fail(fmt.tprintf("%s entity get failed for %s", backend, attr))
	}
	defer vev.close(&data)
	value, value_ok := vev.value(&data)
	actual, actual_ok := vev.as_int(value)
	if !value_ok || (!present && vev.kind(value) != .Nil) || (present && (!actual_ok || actual != i64(expected))) {
		actual_edn, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s entity get %s: expected=%d present=%v actual=%s", backend, attr, expected, present, actual_edn))
	}
	return pbt.pass()
}

entity_view_get_entity_check :: proc(t: ^pbt.T, entity_value: ^vev.Entity, attr: string, expected: int, present: bool, backend: string) -> pbt.Result {
	data, data_ok := vev.entity_get(entity_value, attr)
	if !data_ok {
		return pbt.fail(fmt.tprintf("%s entity get failed for %s", backend, attr))
	}
	defer vev.close(&data)
	value, value_ok := vev.value(&data)
	actual, actual_ok := vev.as_entity(value)
	if !value_ok || (!present && vev.kind(value) != .Nil) || (present && (!actual_ok || actual != u64(expected))) {
		actual_edn, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s entity get %s: expected=%d present=%v actual=%s", backend, attr, expected, present, actual_edn))
	}
	return pbt.pass()
}

entity_view_values_check :: proc(t: ^pbt.T, entity_value: ^vev.Entity, attr: string, expected: u8, entities: bool, backend: string) -> pbt.Result {
	data, data_ok := vev.entity_values(entity_value, attr)
	if !data_ok {
		return pbt.fail(fmt.tprintf("%s entity values failed for %s", backend, attr))
	}
	defer vev.close(&data)
	value, value_ok := vev.value(&data)
	if !value_ok || vev.kind(value) != .Vector || vev.item_count(value) != entity_view_mask_count(expected) {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s entity values %s had wrong shape: expected-mask=%02x actual=%s", backend, attr, expected, actual))
	}
	seen: u8
	for index in 0 ..< vev.item_count(value) {
		item, item_ok := vev.item(value, index)
		actual: i64
		actual_ok: bool
		if entities {
			entity, ok := vev.as_entity(item)
			actual, actual_ok = i64(entity), ok
			actual -= 1
		} else {
			actual, actual_ok = vev.as_int(item)
		}
		if !item_ok || !actual_ok || actual < 0 || actual >= 8 || (seen & (u8(1) << u8(actual))) != 0 {
			actual_edn, _ := vev.edn(item, t.value_allocator)
			return pbt.fail(fmt.tprintf("%s entity values %s contained invalid item %s", backend, attr, actual_edn))
		}
		seen |= u8(1) << u8(actual)
	}
	if seen != expected {
		return pbt.fail(fmt.tprintf("%s entity values %s: expected=%02x actual=%02x", backend, attr, expected, seen))
	}
	return pbt.pass()
}

entity_view_touch_check :: proc(t: ^pbt.T, data: ^vev.Data, entity, score: int, tags, links: u8, backend: string) -> pbt.Result {
	value, value_ok := vev.value(data)
	expected_count := 2
	if tags != 0 {expected_count += 1}
	if links != 0 {expected_count += 1}
	if !value_ok || vev.kind(value) != .Map || vev.map_count(value) != expected_count {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s touch entity %d had wrong shape: expected-count=%d actual=%s", backend, entity, expected_count, actual))
	}
	id_value, id_ok := vev.get(value, ":db/id")
	id, id_value_ok := vev.as_entity(id_value)
	score_value, score_ok := vev.get(value, ":view/score")
	actual_score, score_value_ok := vev.as_int(score_value)
	if !id_ok || !id_value_ok || id != u64(entity) || !score_ok || !score_value_ok || actual_score != i64(score) {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s touch entity %d scalar mismatch: %s", backend, entity, actual))
	}
	if result := entity_view_touch_many_check(t, value, ":view/tag", tags, false, backend); result.status != .Pass {return result}
	if result := entity_view_touch_many_check(t, value, ":view/link", links, true, backend); result.status != .Pass {return result}
	if _, reverse_present := vev.get(value, ":_view/link"); reverse_present {
		return pbt.fail(fmt.tprintf("%s touch unexpectedly included reverse refs", backend))
	}
	return pbt.pass()
}

entity_view_touch_many_check :: proc(t: ^pbt.T, value: vev.Value, attr: string, mask: u8, entities: bool, backend: string) -> pbt.Result {
	item, present := vev.get(value, attr)
	if mask == 0 {
		if present {return pbt.fail(fmt.tprintf("%s touch unexpectedly included %s", backend, attr))}
		return pbt.pass()
	}
	if !present || vev.kind(item) != .Vector {
		return pbt.fail(fmt.tprintf("%s touch omitted many-valued %s", backend, attr))
	}
	return entity_view_value_vector_check(t, item, mask, entities, fmt.tprintf("%s touch %s", backend, attr))
}

entity_view_value_vector_check :: proc(t: ^pbt.T, value: vev.Value, expected: u8, entities: bool, label: string) -> pbt.Result {
	if vev.item_count(value) != entity_view_mask_count(expected) {
		return pbt.fail(fmt.tprintf("%s count mismatch", label))
	}
	seen: u8
	for index in 0 ..< vev.item_count(value) {
		item, item_ok := vev.item(value, index)
		actual: i64
		actual_ok: bool
		if entities {
			entity, ok := vev.as_entity(item)
			if !ok && vev.kind(item) == .Map {
				id_value, id_ok := vev.get(item, ":db/id")
				entity, ok = vev.as_entity(id_value)
				ok = id_ok && ok
			}
			actual, actual_ok = i64(entity) - 1, ok
		} else {
			actual, actual_ok = vev.as_int(item)
		}
		if !item_ok || !actual_ok || actual < 0 || actual >= 8 {
			return pbt.fail(fmt.tprintf("%s contained invalid value", label))
		}
		seen |= u8(1) << u8(actual)
	}
	if seen != expected {
		return pbt.fail(fmt.tprintf("%s: expected=%02x actual=%02x", label, expected, seen))
	}
	return pbt.pass()
}

entity_view_schema_check :: proc(t: ^pbt.T, database: ^vev.DB, selected_attr: int, backend: string) -> pbt.Result {
	attrs := [?]string{":view/score", ":view/tag", ":view/link"}
	ids := [?]u64{100, 101, 102}
	value_types := [?]string{":db.type/long", ":db.type/long", ":db.type/ref"}
	attr := attrs[selected_attr]
	schema_entity, entity_ok := vev.entity_ident(database, attr)
	if !entity_ok {
		return pbt.fail(fmt.tprintf("%s did not resolve schema entity %s", backend, attr))
	}
	defer vev.close(&schema_entity)
	id, id_ok := vev.entity_id(&schema_entity)
	if !id_ok || id != ids[selected_attr] {
		return pbt.fail(fmt.tprintf("%s schema entity %s: expected=%d actual=%d", backend, attr, ids[selected_attr], id))
	}
	metadata, metadata_ok := vev.attribute(database, attr)
	if !metadata_ok {
		return pbt.fail(fmt.tprintf("%s did not return attribute metadata for %s", backend, attr))
	}
	defer vev.close(&metadata)
	value, value_ok := vev.value(&metadata)
	if !value_ok || vev.kind(value) != .Map || vev.map_count(value) != 10 {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s attribute %s had wrong shape: %s", backend, attr, actual))
	}
	if result := entity_view_map_entity_check(t, value, ":id", ids[selected_attr], backend); result.status != .Pass {return result}
	if result := entity_view_map_text_check(t, value, ":ident", attr, backend); result.status != .Pass {return result}
	if result := entity_view_map_text_check(t, value, ":value-type", value_types[selected_attr], backend); result.status != .Pass {return result}
	cardinality := ":db.cardinality/one"
	if selected_attr != 0 {cardinality = ":db.cardinality/many"}
	if result := entity_view_map_text_check(t, value, ":cardinality", cardinality, backend); result.status != .Pass {return result}
	indexed := selected_attr != 2
	if result := entity_view_map_bool_check(value, ":indexed", indexed, attr, backend); result.status != .Pass {return result}
	if result := entity_view_map_bool_check(value, ":has-avet", indexed, attr, backend); result.status != .Pass {return result}
	if result := entity_view_map_bool_check(value, ":is-component", false, attr, backend); result.status != .Pass {return result}
	if result := entity_view_map_bool_check(value, ":no-history", false, attr, backend); result.status != .Pass {return result}
	if result := entity_view_map_bool_check(value, ":fulltext", false, attr, backend); result.status != .Pass {return result}
	unique, unique_ok := vev.get(value, ":unique")
	if !unique_ok || vev.kind(unique) != .Nil {
		return pbt.fail(fmt.tprintf("%s attribute %s unexpectedly had uniqueness", backend, attr))
	}
	if _, missing_ok := vev.attribute(database, ":view/missing"); missing_ok {
		return pbt.fail(fmt.tprintf("%s returned metadata for missing attribute", backend))
	}
	return pbt.pass()
}

entity_view_map_bool_check :: proc(value: vev.Value, key: string, expected: bool, attr, backend: string) -> pbt.Result {
	item, present := vev.get(value, key)
	actual, actual_ok := vev.as_bool(item)
	if !present || !actual_ok || actual != expected {
		return pbt.fail(fmt.tprintf("%s attribute %s %s: expected=%v actual=%v", backend, attr, key, expected, actual))
	}
	return pbt.pass()
}

entity_view_map_entity_check :: proc(t: ^pbt.T, value: vev.Value, key: string, expected: u64, backend: string) -> pbt.Result {
	item, present := vev.get(value, key)
	actual, actual_ok := vev.as_entity(item)
	if !present || !actual_ok || actual != expected {
		return pbt.fail(fmt.tprintf("%s metadata %s: expected=%d actual=%d", backend, key, expected, actual))
	}
	return pbt.pass()
}

entity_view_map_text_check :: proc(t: ^pbt.T, value: vev.Value, key, expected, backend: string) -> pbt.Result {
	item, present := vev.get(value, key)
	actual, actual_ok := vev.as_string(item, t.value_allocator)
	if !present || !actual_ok || actual != expected {
		return pbt.fail(fmt.tprintf("%s metadata %s: expected=%s actual=%s", backend, key, expected, actual))
	}
	return pbt.pass()
}

entity_view_first_set :: proc(mask: u8) -> int {
	for bit in 0 ..< 8 {
		if index_read_mask_has(mask, bit) {return bit}
	}
	return 0
}

entity_view_mask_count :: proc(mask: u8) -> int {
	count := 0
	for bit in 0 ..< 8 {
		if index_read_mask_has(mask, bit) {count += 1}
	}
	return count
}
