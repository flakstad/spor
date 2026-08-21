// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

TUPLE_UPDATE_TAGS := [?]string{"core", "transaction", "model", "durable", "differential", "tuple", "identity", "map", "vector", "atomic", "rollback", "log"}

TUPLE_UPDATE_SCHEMA :: `[
	{:db/id 100 :db/ident :tuple/left :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :tuple/right :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :tuple/identity :db/valueType :db.type/tuple :db/tupleAttrs [:tuple/left :tuple/right] :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
]`

Tuple_Update_Expected :: struct {
	old_left:       string,
	old_right:      string,
	new_left:       string,
	new_right:      string,
	left_first:     bool,
	map_left_first: bool,
}

tuple_update_property :: proc(t: ^pbt.T) -> pbt.Result {
	stem := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 8))
	expected := Tuple_Update_Expected{
		old_left = fmt.tprintf("%s-left-old", stem),
		old_right = fmt.tprintf("%s-right-old", stem),
		new_left = fmt.tprintf("%s-left-new", stem),
		new_right = fmt.tprintf("%s-right-new", stem),
		left_first = pbt.draw(t, pbt.boolean()),
		map_left_first = pbt.draw(t, pbt.boolean()),
	}
	pbt.cover(t, expected.left_first, 35, "tuple-vector-left-first")
	pbt.cover(t, !expected.left_first, 35, "tuple-vector-right-first")
	pbt.cover(t, expected.map_left_first == expected.left_first, 35, "tuple-map-same-order")
	pbt.cover(t, expected.map_left_first != expected.left_first, 35, "tuple-map-reversed-order")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {
		return pbt.error("could not create tuple-update resident connection")
	}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return pbt.error("could not allocate tuple-update store")
	}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {
		return pbt.error("could not create tuple-update durable connection")
	}
	defer vev.close(&durable)

	if result := tuple_update_setup(t, &resident, expected); result.status != .Pass {
		return result
	}
	if result := tuple_update_setup(t, &durable, expected); result.status != .Pass {
		return result
	}
	vector_tx := tuple_update_vector_edn(expected)
	map_tx := tuple_update_map_edn(expected)
	pbt.note(t, fmt.tprintf("tuple-update vector=%s map=%s", vector_tx, map_tx))
	if result := tuple_update_backend_check(t, &resident, expected, vector_tx, map_tx, "resident", false); result.status != .Pass {
		return result
	}
	if result := tuple_update_backend_check(t, &durable, expected, vector_tx, map_tx, "durable", true); result.status != .Pass {
		return result
	}
	count_before_reopen, count_ok := vev.connection_tx_count(&durable)
	basis_before_reopen, basis_ok := tempid_order_basis(&durable)
	if !count_ok || !basis_ok {
		return pbt.error("could not read tuple-update durable coordinates")
	}
	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {
		return pbt.error("could not reopen tuple-update durable connection")
	}
	count_after_reopen, reopened_count_ok := vev.connection_tx_count(&durable)
	basis_after_reopen, reopened_basis_ok := tempid_order_basis(&durable)
	if !reopened_count_ok || !reopened_basis_ok ||
	   count_after_reopen != count_before_reopen || basis_after_reopen != basis_before_reopen {
		return pbt.fail(fmt.tprintf(
			"tuple-update coordinates changed across reopen: count=%d/%d basis=%d/%d",
			count_before_reopen,
			count_after_reopen,
			basis_before_reopen,
			basis_after_reopen,
		))
	}
	if result := tuple_update_state_invariant(t, &durable, expected, "durable reopened"); result.status != .Pass {
		return result
	}
	pbt.record_event(t, "durable", "tuple-update-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d",
		basis_after_reopen,
		count_after_reopen,
	))
	return pbt.pass()
}

tuple_update_setup :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tuple_Update_Expected,
) -> pbt.Result {
	seed_one := fmt.tprintf(
		`[[:db/add 1 :tuple/left "%s"] [:db/add 1 :tuple/right "%s"]]`,
		expected.old_left,
		expected.old_right,
	)
	seed_two := fmt.tprintf(
		`[[:db/add 2 :tuple/left "%s"] [:db/add 2 :tuple/right "%s"]]`,
		expected.new_left,
		expected.old_right,
	)
	seed_three := fmt.tprintf(
		`[[:db/add 3 :tuple/left "%s"] [:db/add 3 :tuple/right "%s"]]`,
		expected.old_left,
		expected.new_right,
	)
	transactions := [?]string{TUPLE_UPDATE_SCHEMA, seed_one, seed_two, seed_three}
	for tx in transactions {
		report, ok := vev.transact(connection, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize tuple-update backend with %s: %s", tx, report))
		}
	}
	return tuple_update_seed_invariant(t, connection, expected, "setup")
}

tuple_update_vector_edn :: proc(expected: Tuple_Update_Expected) -> string {
	left := fmt.tprintf(`[:db/add 1 :tuple/left "%s"]`, expected.new_left)
	right := fmt.tprintf(`[:db/add 1 :tuple/right "%s"]`, expected.new_right)
	if expected.left_first {
		return fmt.tprintf("[%s %s]", left, right)
	}
	return fmt.tprintf("[%s %s]", right, left)
}

tuple_update_map_edn :: proc(expected: Tuple_Update_Expected) -> string {
	body: string
	if expected.map_left_first {
		body = fmt.tprintf(
			`:db/id 1 :tuple/left "%s" :tuple/right "%s"`,
			expected.new_left,
			expected.new_right,
		)
	} else {
		body = fmt.tprintf(
			`:db/id 1 :tuple/right "%s" :tuple/left "%s"`,
			expected.new_right,
			expected.new_left,
		)
	}
	return strings.concatenate([]string{"[{", body, "}]"})
}

tuple_update_backend_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tuple_Update_Expected,
	vector_tx, map_tx: string,
	label: string,
	durable: bool,
) -> pbt.Result {
	basis_before, basis_before_ok := tempid_order_basis(connection)
	if !basis_before_ok {
		return pbt.error(fmt.tprintf("could not read %s tuple-update basis", label))
	}
	vector_report, vector_call_ok := vev.transact(connection, vector_tx, t.value_allocator)
	pbt.note(t, fmt.tprintf("%s tuple vector report=%s", label, vector_report))
	basis_after_failure, failure_basis_ok := tempid_order_basis(connection)
	if vector_call_ok == durable || strings.contains(vector_report, ":ok true") ||
	   !strings.contains(vector_report, "schema unique conflict") {
		return pbt.fail(fmt.tprintf("%s tuple vector did not conflict: %s", label, vector_report))
	}
	if !failure_basis_ok || basis_after_failure != basis_before {
		return pbt.fail(fmt.tprintf(
			"%s tuple vector changed basis: before=%d after=%d",
			label,
			basis_before,
			basis_after_failure,
		))
	}
	if result := tuple_update_seed_invariant(t, connection, expected, fmt.tprintf("%s after rollback", label)); result.status != .Pass {
		return result
	}
	map_report, map_ok := vev.transact(connection, map_tx, t.value_allocator)
	pbt.note(t, fmt.tprintf("%s tuple map report=%s", label, map_report))
	if !map_ok || !strings.contains(map_report, ":ok true") {
		return pbt.fail(fmt.tprintf("%s tuple map did not commit: %s", label, map_report))
	}
	basis_after, basis_after_ok := tempid_order_basis(connection)
	if !basis_after_ok || basis_after != basis_before + 1 {
		return pbt.fail(fmt.tprintf(
			"%s tuple map basis: before=%d after=%d",
			label,
			basis_before,
			basis_after,
		))
	}
	if result := tuple_update_state_invariant(t, connection, expected, label); result.status != .Pass {
		return result
	}
	return tuple_update_log_invariant(t, connection, expected, basis_before, basis_after, label)
}

tuple_update_seed_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tuple_Update_Expected,
	label: string,
) -> pbt.Result {
	tuples := [3][2]string{
		{expected.old_left, expected.old_right},
		{expected.new_left, expected.old_right},
		{expected.old_left, expected.new_right},
	}
	for tuple, index in tuples {
		if result := tuple_update_expect_lookup(t, connection, tuple[0], tuple[1], u64(index + 1), label); result.status != .Pass {
			return result
		}
	}
	return pbt.pass()
}

tuple_update_state_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tuple_Update_Expected,
	label: string,
) -> pbt.Result {
	if result := tuple_update_expect_missing_lookup(t, connection, expected.old_left, expected.old_right, label); result.status != .Pass {
		return result
	}
	expected_tuples := [3][3]string{
		{expected.new_left, expected.new_right, "1"},
		{expected.new_left, expected.old_right, "2"},
		{expected.old_left, expected.new_right, "3"},
	}
	for tuple in expected_tuples {
		entity := u64(1)
		if tuple[2] == "2" {
			entity = 2
		} else if tuple[2] == "3" {
			entity = 3
		}
		if result := tuple_update_expect_lookup(t, connection, tuple[0], tuple[1], entity, label); result.status != .Pass {
			return result
		}
	}
	return pbt.pass()
}

tuple_update_expect_lookup :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	left, right: string,
	expected_entity: u64,
	label: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s tuple database", label))
	}
	defer vev.close(&database)
	lookup, lookup_ok := vev.entity_lookup_ref(
		&database,
		":tuple/identity",
		fmt.tprintf(`["%s" "%s"]`, left, right),
	)
	if !lookup_ok {
		return pbt.fail(fmt.tprintf("%s did not resolve tuple [%s %s]", label, left, right))
	}
	defer vev.close(&lookup)
	entity, entity_ok := vev.entity_id(&lookup)
	if !entity_ok || entity != expected_entity {
		return pbt.fail(fmt.tprintf(
			"%s tuple [%s %s] resolved to %d instead of %d",
			label,
			left,
			right,
			entity,
			expected_entity,
		))
	}
	return pbt.pass()
}

tuple_update_expect_missing_lookup :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	left, right: string,
	label: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s tuple database", label))
	}
	defer vev.close(&database)
	lookup, lookup_ok := vev.entity_lookup_ref(
		&database,
		":tuple/identity",
		fmt.tprintf(`["%s" "%s"]`, left, right),
	)
	if lookup_ok {
		vev.close(&lookup)
		return pbt.fail(fmt.tprintf("%s retained obsolete tuple [%s %s]", label, left, right))
	}
	return pbt.pass()
}

tuple_update_log_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tuple_Update_Expected,
	checkpoint, basis: u64,
	label: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s tuple-update log", label))
	}
	defer vev.close(&log_value)
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s tuple-update range failed", label))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != 1 {
		return pbt.fail(fmt.tprintf("%s tuple-update range count is not one", label))
	}
	transaction, transaction_ok := vev.item(transactions_value, 0)
	data, data_ok := vev.get(transaction, ":data")
	if !transaction_ok || !data_ok || vev.kind(data) != .Vector {
		return pbt.error(fmt.tprintf("%s tuple-update transaction is malformed", label))
	}
	seen: [6]bool
	for datom_index in 0 ..< vev.item_count(data) {
		datom, datom_ok := vev.item(data, datom_index)
		if !datom_ok || vev.kind(datom) != .Vector || vev.item_count(datom) != 5 {
			return pbt.error(fmt.tprintf("%s tuple-update datom is malformed", label))
		}
		entity_value, entity_ok := vev.item(datom, 0)
		attribute_value, attribute_ok := vev.item(datom, 1)
		fact_value, fact_ok := vev.item(datom, 2)
		added_value, added_ok := vev.item(datom, 4)
		attribute, attribute_value_ok := vev.as_string(attribute_value, t.value_allocator)
		if !entity_ok || !attribute_ok || !fact_ok || !added_ok || !attribute_value_ok {
			return pbt.error(fmt.tprintf("%s tuple-update datom has unexpected types", label))
		}
		if attribute == ":db/txInstant" {
			continue
		}
		entity, entity_value_ok := vev.as_entity(entity_value)
		added, added_value_ok := vev.as_bool(added_value)
		if !entity_value_ok || !added_value_ok || entity != 1 {
			return pbt.fail(fmt.tprintf("%s tuple-update datom has wrong envelope", label))
		}
		seen_index := -1
		switch attribute {
		case ":tuple/left":
			actual, actual_ok := vev.as_string(fact_value, t.value_allocator)
			if !actual_ok {
				return pbt.fail(fmt.tprintf("%s tuple-update left value is malformed", label))
			}
			if !added && actual == expected.old_left {
				seen_index = 0
			} else if added && actual == expected.new_left {
				seen_index = 1
			}
		case ":tuple/right":
			actual, actual_ok := vev.as_string(fact_value, t.value_allocator)
			if !actual_ok {
				return pbt.fail(fmt.tprintf("%s tuple-update right value is malformed", label))
			}
			if !added && actual == expected.old_right {
				seen_index = 2
			} else if added && actual == expected.new_right {
				seen_index = 3
			}
		case ":tuple/identity":
			if vev.kind(fact_value) != .Vector || vev.item_count(fact_value) != 2 {
				return pbt.fail(fmt.tprintf("%s tuple-update identity value is malformed", label))
			}
			left_value, left_ok := vev.item(fact_value, 0)
			right_value, right_ok := vev.item(fact_value, 1)
			left, left_value_ok := vev.as_string(left_value, t.value_allocator)
			right, right_value_ok := vev.as_string(right_value, t.value_allocator)
			if !left_ok || !right_ok || !left_value_ok || !right_value_ok {
				return pbt.fail(fmt.tprintf("%s tuple-update identity components are malformed", label))
			}
			if !added && left == expected.old_left && right == expected.old_right {
				seen_index = 4
			} else if added && left == expected.new_left && right == expected.new_right {
				seen_index = 5
			}
		case:
			return pbt.fail(fmt.tprintf("%s tuple-update has unexpected attribute %s", label, attribute))
		}
		if seen_index < 0 || seen[seen_index] {
			return pbt.fail(fmt.tprintf("%s tuple-update has unexpected or repeated datom", label))
		}
		seen[seen_index] = true
	}
	for item in seen {
		if !item {
			return pbt.fail(fmt.tprintf("%s tuple-update log omitted an expected datom", label))
		}
	}
	return pbt.pass()
}
