package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

PULL_MODEL_TAGS := [?]string{"core", "pull", "query", "datalog", "model", "durable", "differential", "cardinality-many", "nested", "reference", "mutation", "reopen"}
PULL_MODEL_MAX_ENTITIES :: 8
PULL_MODEL_TAG_COUNT :: 4

PULL_MODEL_SCHEMA :: `[
	{:db/id 100 :db/ident :pull/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :pull/tag :db/valueType :db.type/string :db/cardinality :db.cardinality/many}
	{:db/id 102 :db/ident :pull/friend :db/valueType :db.type/ref :db/cardinality :db.cardinality/one}
]`

PULL_MODEL_PATTERN :: `[:pull/name :pull/tag {:pull/friend [:pull/name]}]`
PULL_MODEL_QUERY :: `[:find ?e (pull ?e [:pull/name :pull/tag {:pull/friend [:pull/name]}])
	:where [?e :pull/name ?name]]`

Pull_Model_Case :: struct {
	entity_count:       int,
	tags:               [PULL_MODEL_MAX_ENTITIES]u8,
	friends:            [PULL_MODEL_MAX_ENTITIES]int,
	mutation_kind:      int,
	mutation_entity:    int,
	mutation_tag:       int,
	mutation_friend:    int,
	reverse_seed:       bool,
	reverse_pull_many:  bool,
}

pull_model_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Pull_Model_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, PULL_MODEL_MAX_ENTITIES)),
		mutation_kind = pbt.draw(t, pbt.int_range(0, 2)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
		reverse_pull_many = pbt.draw(t, pbt.boolean()),
	}
	scenario.mutation_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.mutation_tag = pbt.draw(t, pbt.int_range(0, PULL_MODEL_TAG_COUNT - 1))
	scenario.mutation_friend = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	for entity in 0 ..< scenario.entity_count {
		scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << PULL_MODEL_TAG_COUNT) - 1)))
		friend_choice := pbt.draw(t, pbt.int_range(0, scenario.entity_count))
		scenario.friends[entity] = friend_choice
	}
	final_tags := pull_model_final_tags(scenario)
	final_friends := pull_model_final_friends(scenario)
	has_empty_tags, has_multiple_tags := pull_model_tag_shapes(scenario.entity_count, final_tags)
	has_missing_friend, has_self_friend := pull_model_friend_shapes(scenario.entity_count, final_friends)
	pbt.cover(t, scenario.mutation_kind == 0, 20, "pull-no-mutation")
	pbt.cover(t, scenario.mutation_kind == 1, 20, "pull-tag-mutation")
	pbt.cover(t, scenario.mutation_kind == 2, 20, "pull-friend-mutation")
	pbt.cover(t, scenario.reverse_seed, 35, "pull-reverse-seed")
	pbt.cover(t, scenario.reverse_pull_many, 35, "pull-reverse-many")
	pbt.cover(t, has_empty_tags, 20, "pull-empty-many")
	pbt.cover(t, has_multiple_tags, 35, "pull-multiple-many")
	pbt.cover(t, has_missing_friend, 20, "pull-missing-reference")
	pbt.cover(t, has_self_friend, 5, "pull-self-reference")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create pull-model resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate pull-model durable path")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create pull-model durable connection")
	}
	defer vev.close(&durable)

	seed := pull_model_seed_edn(t, scenario)
	setup := [?]string{PULL_MODEL_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not initialize pull model: resident=%s durable=%s",
				resident_report,
				durable_report,
			))
		}
	}
	if scenario.mutation_kind != 0 {
		mutation := pull_model_mutation_edn(scenario)
		resident_report, resident_call_ok := vev.transact(&resident, mutation, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, mutation, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf(
				"could not mutate pull model: tx=%s resident=%s durable=%s",
				mutation,
				resident_report,
				durable_report,
			))
		}
	}

	basis_before, basis_ok := tempid_order_basis(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {
		return pbt.error("could not read pull-model durable coordinates")
	}
	if result := pull_model_connection_check(t, &resident, scenario, final_tags, final_friends, "resident"); result.status != .Pass {
		return result
	}
	if result := pull_model_connection_check(t, &durable, scenario, final_tags, final_friends, "durable"); result.status != .Pass {
		return result
	}
	basis_after, basis_after_ok := tempid_order_basis(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf(
			"pull reads changed coordinates: basis=%d/%d count=%d/%d",
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
		return pbt.error("could not reopen pull-model durable connection")
	}
	if result := pull_model_connection_check(t, &durable, scenario, final_tags, final_friends, "durable reopened"); result.status != .Pass {
		return result
	}
	reopened_basis, reopened_basis_ok := tempid_order_basis(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf(
			"pull coordinates changed across reopen: basis=%d/%d count=%d/%d",
			basis_before,
			reopened_basis,
			count_before,
			reopened_count,
		))
	}
	pbt.record_event(t, "durable", "pull-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d entities=%d",
		reopened_basis,
		reopened_count,
		scenario.entity_count,
	))
	return pbt.pass()
}

pull_model_seed_edn :: proc(t: ^pbt.T, scenario: Pull_Model_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {
			entity = scenario.entity_count - offset
		}
		append(&parts, fmt.tprintf(`[:db/add %d :pull/name "node-%d"]`, entity, entity))
		for tag in 0 ..< PULL_MODEL_TAG_COUNT {
			if pull_model_has_tag(scenario.tags[entity - 1], tag) {
				append(&parts, fmt.tprintf(`[:db/add %d :pull/tag "tag-%d"]`, entity, tag))
			}
		}
		if scenario.friends[entity - 1] != 0 {
			append(&parts, fmt.tprintf("[:db/add %d :pull/friend %d]", entity, scenario.friends[entity - 1]))
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

pull_model_mutation_edn :: proc(scenario: Pull_Model_Case) -> string {
	entity := scenario.mutation_entity
	switch scenario.mutation_kind {
	case 1:
		op := ":db/add"
		if pull_model_has_tag(scenario.tags[entity - 1], scenario.mutation_tag) {
			op = ":db/retract"
		}
		return fmt.tprintf(`[[%s %d :pull/tag "tag-%d"]]`, op, entity, scenario.mutation_tag)
	case 2:
		friend := scenario.friends[entity - 1]
		if friend == scenario.mutation_friend {
			return fmt.tprintf("[[:db/retract %d :pull/friend %d]]", entity, friend)
		}
		return fmt.tprintf("[[:db/add %d :pull/friend %d]]", entity, scenario.mutation_friend)
	}
	return "[]"
}

pull_model_connection_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Pull_Model_Case,
	tags: [PULL_MODEL_MAX_ENTITIES]u8,
	friends: [PULL_MODEL_MAX_ENTITIES]int,
	backend: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s pull database", backend))
	}
	defer vev.close(&database)

	for entity in 1 ..= scenario.entity_count {
		pulled, pull_ok := vev.pull(&database, PULL_MODEL_PATTERN, u64(entity))
		if !pull_ok {
			return pbt.fail(fmt.tprintf("%s direct pull failed for entity %d", backend, entity))
		}
		value, value_ok := vev.value(&pulled)
		if !value_ok {
			vev.close(&pulled)
			return pbt.error(fmt.tprintf("%s direct pull value unavailable for entity %d", backend, entity))
		}
		result := pull_model_value_check(t, value, entity, tags, friends, backend)
		vev.close(&pulled)
		if result.status != .Pass {
			return result
		}
	}

	entities: [PULL_MODEL_MAX_ENTITIES]u64
	for index in 0 ..< scenario.entity_count {
		entity := index + 1
		if scenario.reverse_pull_many {
			entity = scenario.entity_count - index
		}
		entities[index] = u64(entity)
	}
	many, many_ok := vev.pull_many(&database, PULL_MODEL_PATTERN, entities[:scenario.entity_count])
	if !many_ok {
		return pbt.fail(fmt.tprintf("%s pull-many failed", backend))
	}
	defer vev.close(&many)
	many_value, many_value_ok := vev.value(&many)
	if !many_value_ok || vev.kind(many_value) != .Vector || vev.item_count(many_value) != scenario.entity_count {
		return pbt.fail(fmt.tprintf("%s pull-many returned unexpected shape", backend))
	}
	for index in 0 ..< scenario.entity_count {
		item, item_ok := vev.item(many_value, index)
		if !item_ok {
			return pbt.error(fmt.tprintf("%s pull-many item %d unavailable", backend, index))
		}
		if result := pull_model_value_check(t, item, int(entities[index]), tags, friends, backend); result.status != .Pass {
			return result
		}
	}

	query_result, query_ok := vev.query(&database, PULL_MODEL_QUERY)
	if !query_ok {
		return pbt.fail(fmt.tprintf("%s Datalog pull failed", backend))
	}
	defer vev.close(&query_result)
	relation, relation_ok := vev.value(&query_result)
	if !relation_ok || vev.item_count(relation) != scenario.entity_count {
		return pbt.fail(fmt.tprintf(
			"%s Datalog pull row count: expected=%d actual=%d",
			backend,
			scenario.entity_count,
			vev.item_count(relation),
		))
	}
	seen: [PULL_MODEL_MAX_ENTITIES]bool
	for row_index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, row_index)
		entity_value, entity_value_ok := vev.item(row, 0)
		pulled_value, pulled_value_ok := vev.item(row, 1)
		entity, entity_ok := vev.as_int(entity_value)
		if !row_ok || !entity_value_ok || !pulled_value_ok || !entity_ok ||
		   entity < 1 || entity > i64(scenario.entity_count) || seen[entity - 1] {
			return pbt.fail(fmt.tprintf("%s Datalog pull returned invalid entity %d", backend, entity))
		}
		seen[entity - 1] = true
		if result := pull_model_value_check(t, pulled_value, int(entity), tags, friends, backend); result.status != .Pass {
			return result
		}
	}
	return pbt.pass()
}

pull_model_value_check :: proc(
	t: ^pbt.T,
	value: vev.Value,
	entity: int,
	tags: [PULL_MODEL_MAX_ENTITIES]u8,
	friends: [PULL_MODEL_MAX_ENTITIES]int,
	backend: string,
) -> pbt.Result {
	if vev.kind(value) != .Map {
		return pbt.fail(fmt.tprintf("%s pull for entity %d was not a map", backend, entity))
	}
	name_value, name_ok := vev.get(value, ":pull/name")
	name, name_text_ok := vev.as_string(name_value, t.value_allocator)
	expected_name := fmt.tprintf("node-%d", entity)
	if !name_ok || !name_text_ok || name != expected_name {
		return pbt.fail(fmt.tprintf(
			"%s pull name for entity %d: expected=%s actual=%s",
			backend,
			entity,
			expected_name,
			name,
		))
	}

	expected_tags := tags[entity - 1]
	tag_value, tag_present := vev.get(value, ":pull/tag")
	if expected_tags == 0 {
		if tag_present {
			return pbt.fail(fmt.tprintf("%s pull unexpectedly included tags for entity %d", backend, entity))
		}
	} else {
		if !tag_present || vev.kind(tag_value) != .Vector || vev.item_count(tag_value) != pull_model_tag_count(expected_tags) {
			return pbt.fail(fmt.tprintf("%s pull returned wrong tag shape for entity %d", backend, entity))
		}
		seen_tags: u8
		for index in 0 ..< vev.item_count(tag_value) {
			item, item_ok := vev.item(tag_value, index)
			text, text_ok := vev.as_string(item, t.value_allocator)
			matched := false
			if item_ok && text_ok {
				for tag in 0 ..< PULL_MODEL_TAG_COUNT {
					if text == fmt.tprintf("tag-%d", tag) {
						bit := u8(1) << u8(tag)
						if (seen_tags & bit) != 0 {
							return pbt.fail(fmt.tprintf("%s pull duplicated tag %s for entity %d", backend, text, entity))
						}
						seen_tags |= bit
						matched = true
						break
					}
				}
			}
			if !matched {
				return pbt.fail(fmt.tprintf("%s pull returned invalid tag for entity %d", backend, entity))
			}
		}
		if seen_tags != expected_tags {
			return pbt.fail(fmt.tprintf(
				"%s pull tags for entity %d: expected=%02x actual=%02x",
				backend,
				entity,
				expected_tags,
				seen_tags,
			))
		}
	}

	expected_friend := friends[entity - 1]
	friend_value, friend_present := vev.get(value, ":pull/friend")
	if expected_friend == 0 {
		if friend_present {
			return pbt.fail(fmt.tprintf("%s pull unexpectedly included friend for entity %d", backend, entity))
		}
	} else {
		if !friend_present || vev.kind(friend_value) != .Map {
			return pbt.fail(fmt.tprintf("%s pull omitted nested friend for entity %d", backend, entity))
		}
		if expected_friend == entity {
			friend_id_value, friend_id_ok := vev.get(friend_value, ":db/id")
			friend_id: u64
			friend_id_value_ok := false
			if friend_id_ok {
				friend_id, friend_id_value_ok = vev.as_entity(friend_id_value)
				if !friend_id_value_ok {
					friend_id_int, friend_id_int_ok := vev.as_int(friend_id_value)
					if friend_id_int_ok && friend_id_int >= 0 {
						friend_id = u64(friend_id_int)
						friend_id_value_ok = true
					}
				}
			}
			if !friend_id_ok || !friend_id_value_ok || friend_id != u64(entity) {
				actual_friend, _ := vev.edn(friend_value, t.value_allocator)
				return pbt.fail(fmt.tprintf(
					"%s self-referential pull for entity %d did not stop at :db/id: %s",
					backend,
					entity,
					actual_friend,
				))
			}
			return pbt.pass()
		}
		friend_name_value, friend_name_ok := vev.get(friend_value, ":pull/name")
		friend_name, friend_name_text_ok := vev.as_string(friend_name_value, t.value_allocator)
		expected_friend_name := fmt.tprintf("node-%d", expected_friend)
		if !friend_name_ok || !friend_name_text_ok || friend_name != expected_friend_name {
			actual_friend, _ := vev.edn(friend_value, t.value_allocator)
			return pbt.fail(fmt.tprintf(
				"%s nested pull for entity %d: expected=%s actual=%s value=%s",
				backend,
				entity,
				expected_friend_name,
				friend_name,
				actual_friend,
			))
		}
	}
	return pbt.pass()
}

pull_model_final_tags :: proc(scenario: Pull_Model_Case) -> [PULL_MODEL_MAX_ENTITIES]u8 {
	out := scenario.tags
	if scenario.mutation_kind == 1 {
		index := scenario.mutation_entity - 1
		out[index] = out[index] ~ (u8(1) << u8(scenario.mutation_tag))
	}
	return out
}

pull_model_final_friends :: proc(scenario: Pull_Model_Case) -> [PULL_MODEL_MAX_ENTITIES]int {
	out := scenario.friends
	if scenario.mutation_kind == 2 {
		index := scenario.mutation_entity - 1
		if out[index] == scenario.mutation_friend {
			out[index] = 0
		} else {
			out[index] = scenario.mutation_friend
		}
	}
	return out
}

pull_model_tag_shapes :: proc(
	entity_count: int,
	tags: [PULL_MODEL_MAX_ENTITIES]u8,
) -> (has_empty, has_multiple: bool) {
	for entity in 0 ..< entity_count {
		count := pull_model_tag_count(tags[entity])
		has_empty = has_empty || count == 0
		has_multiple = has_multiple || count > 1
	}
	return
}

pull_model_friend_shapes :: proc(
	entity_count: int,
	friends: [PULL_MODEL_MAX_ENTITIES]int,
) -> (has_missing, has_self: bool) {
	for entity in 0 ..< entity_count {
		has_missing = has_missing || friends[entity] == 0
		has_self = has_self || friends[entity] == entity + 1
	}
	return
}

pull_model_tag_count :: proc(mask: u8) -> int {
	count := 0
	for tag in 0 ..< PULL_MODEL_TAG_COUNT {
		if pull_model_has_tag(mask, tag) {
			count += 1
		}
	}
	return count
}

pull_model_has_tag :: proc(mask: u8, tag: int) -> bool {
	return (mask & (u8(1) << u8(tag))) != 0
}
