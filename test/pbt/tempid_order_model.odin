package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

TEMPID_ORDER_TAGS := [?]string{"core", "transaction", "model", "durable", "differential", "identity", "upsert", "tempid", "permutation", "order", "log"}
TEMPID_TUPLE_ORDER_TAGS := [?]string{"core", "transaction", "model", "durable", "differential", "identity", "tuple", "upsert", "tempid", "permutation", "order", "log"}
TEMPID_ORDER_FORM_COUNT :: 6

TEMPID_ORDER_SCHEMA :: `[
	{:db/id 100 :db/ident :order/key :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
	{:db/id 101 :db/ident :order/age :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :order/likes :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 103 :db/ident :order/rank :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
]`

TEMPID_TUPLE_ORDER_SCHEMA :: `[
	{:db/id 100 :db/ident :order/key :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :order/rank :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
	{:db/id 102 :db/ident :order/key+rank :db/valueType :db.type/tuple :db/tupleAttrs [:order/key :order/rank] :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
]`

Tempid_Order_Expected :: struct {
	key:           string,
	age:           int,
	likes:         string,
	rank:          int,
	seed_existing: bool,
	tuple_identity: bool,
}

tempid_order_property :: proc(t: ^pbt.T) -> pbt.Result {
	return tempid_order_property_kind(t, false)
}

tempid_tuple_order_property :: proc(t: ^pbt.T) -> pbt.Result {
	return tempid_order_property_kind(t, true)
}

tempid_order_property_kind :: proc(t: ^pbt.T, tuple_identity: bool) -> pbt.Result {
	expected := Tempid_Order_Expected{
		key = pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 10)),
		age = pbt.draw(t, pbt.int_range(1, 120)),
		likes = MODEL_TAGS[pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))],
		rank = pbt.draw(t, pbt.int_range(1, 1_000)),
		seed_existing = pbt.draw(t, pbt.boolean()),
		tuple_identity = tuple_identity,
	}
	canonical := [TEMPID_ORDER_FORM_COUNT]int{0, 1, 2, 3, 4, 5}
	permuted := canonical
	for index := TEMPID_ORDER_FORM_COUNT - 1; index > 0; index -= 1 {
		swap_index := pbt.draw(t, pbt.int_range(0, index))
		permuted[index], permuted[swap_index] = permuted[swap_index], permuted[index]
	}
	noncanonical := permuted != canonical
	if tuple_identity {
		pbt.cover(t, noncanonical, 90, "tuple-tempid-noncanonical-order")
		pbt.cover(t, permuted[0] < 3, 35, "tuple-first-component-first")
		pbt.cover(t, permuted[0] >= 3, 35, "tuple-completing-component-first")
		pbt.cover(t, expected.seed_existing, 35, "tuple-existing-identity")
		pbt.cover(t, !expected.seed_existing, 35, "tuple-new-identity")
	} else {
		pbt.cover(t, noncanonical, 90, "tempid-noncanonical-order")
		pbt.cover(t, permuted[0] < 3, 35, "tempid-payload-first")
		pbt.cover(t, permuted[0] >= 3, 35, "tempid-identity-first")
		pbt.cover(t, expected.seed_existing, 35, "tempid-existing-identity")
		pbt.cover(t, !expected.seed_existing, 35, "tempid-new-identity")
	}

	canonical_tx := tempid_order_edn(expected, canonical)
	permuted_tx := tempid_order_edn(expected, permuted)
	pbt.note(t, fmt.tprintf(
		"tempid-order key=%s existing=%v canonical=%s permuted=%s",
		expected.key,
		expected.seed_existing,
		canonical_tx,
		permuted_tx,
	))
	canonical_resident_entity, result := tempid_order_resident_check(t, canonical_tx, expected, "resident canonical")
	if result.status != .Pass {
		return result
	}
	permuted_resident_entity: u64
	permuted_resident_entity, result = tempid_order_resident_check(t, permuted_tx, expected, "resident permuted")
	if result.status != .Pass {
		return result
	}
	canonical_durable_entity: u64
	canonical_durable_entity, result = tempid_order_durable_check(t, canonical_tx, expected, "durable canonical")
	if result.status != .Pass {
		return result
	}
	permuted_durable_entity: u64
	permuted_durable_entity, result = tempid_order_durable_check(t, permuted_tx, expected, "durable permuted")
	if result.status != .Pass {
		return result
	}
	if canonical_resident_entity != permuted_resident_entity ||
	   canonical_resident_entity != canonical_durable_entity ||
	   canonical_resident_entity != permuted_durable_entity {
		return pbt.fail(fmt.tprintf(
			"tempid allocation differs by order or backend: canonical=%d/%d permuted=%d/%d",
			canonical_resident_entity,
			canonical_durable_entity,
			permuted_resident_entity,
			permuted_durable_entity,
		))
	}
	return pbt.pass()
}

tempid_order_edn :: proc(expected: Tempid_Order_Expected, order: [TEMPID_ORDER_FORM_COUNT]int) -> string {
	forms: [TEMPID_ORDER_FORM_COUNT]string
	if expected.tuple_identity {
		forms = [TEMPID_ORDER_FORM_COUNT]string{
			fmt.tprintf(`[:db/add "a" :order/key "%s"]`, expected.key),
			fmt.tprintf(`[:db/add "b" :order/key "%s"]`, expected.key),
			fmt.tprintf(`[:db/add "c" :order/key "%s"]`, expected.key),
			fmt.tprintf(`[:db/add "a" :order/rank %d]`, expected.rank),
			fmt.tprintf(`[:db/add "b" :order/rank %d]`, expected.rank),
			fmt.tprintf(`[:db/add "c" :order/rank %d]`, expected.rank),
		}
	} else {
		forms = [TEMPID_ORDER_FORM_COUNT]string{
			fmt.tprintf(`[:db/add "a" :order/age %d]`, expected.age),
			fmt.tprintf(`[:db/add "b" :order/likes "%s"]`, expected.likes),
			fmt.tprintf(`[:db/add "c" :order/rank %d]`, expected.rank),
			fmt.tprintf(`[:db/add "a" :order/key "%s"]`, expected.key),
			fmt.tprintf(`[:db/add "b" :order/key "%s"]`, expected.key),
			fmt.tprintf(`[:db/add "c" :order/key "%s"]`, expected.key),
		}
	}
	return fmt.tprintf(
		"[%s %s %s %s %s %s]",
		forms[order[0]],
		forms[order[1]],
		forms[order[2]],
		forms[order[3]],
		forms[order[4]],
		forms[order[5]],
	)
}

tempid_order_resident_check :: proc(
	t: ^pbt.T,
	tx: string,
	expected: Tempid_Order_Expected,
	label: string,
) -> (entity: u64, result: pbt.Result) {
	connection, connection_ok := vev.create_conn(&library)
	if !connection_ok {
		return 0, pbt.error(fmt.tprintf("could not create %s connection", label))
	}
	defer vev.close(&connection)
	if setup_result := tempid_order_setup(t, &connection, expected); setup_result.status != .Pass {
		return 0, setup_result
	}
	_, entity, result = tempid_order_backend_check(t, &connection, tx, expected, label)
	return entity, result
}

tempid_order_durable_check :: proc(
	t: ^pbt.T,
	tx: string,
	expected: Tempid_Order_Expected,
	label: string,
) -> (entity: u64, result: pbt.Result) {
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {
		return 0, pbt.error(fmt.tprintf("could not allocate %s store", label))
	}
	defer transaction_model_remove_store(path)
	connection, connection_ok := vev.connect(&library, path)
	if !connection_ok {
		return 0, pbt.error(fmt.tprintf("could not open %s store", label))
	}
	defer vev.close(&connection)
	if setup_result := tempid_order_setup(t, &connection, expected); setup_result.status != .Pass {
		return 0, setup_result
	}
	count_before, count_before_ok := vev.connection_tx_count(&connection)
	basis_after: u64
	basis_after, entity, result = tempid_order_backend_check(t, &connection, tx, expected, label)
	if result.status != .Pass {
		return 0, result
	}
	count_after, count_after_ok := vev.connection_tx_count(&connection)
	if !count_before_ok || !count_after_ok || count_after != count_before + 1 {
		return 0, pbt.fail(fmt.tprintf(
			"%s transaction count: before=%d after=%d",
			label,
			count_before,
			count_after,
		))
	}
	vev.close(&connection)
	reopened_ok: bool
	connection, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {
		return 0, pbt.error(fmt.tprintf("could not reopen %s store", label))
	}
	reopened_basis, reopened_basis_ok := transaction_cas_durable_basis(&connection)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&connection)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_after ||
	   reopened_count != count_after {
		return 0, pbt.fail(fmt.tprintf(
			"%s coordinates changed across reopen: basis=%d->%d count=%d->%d",
			label,
			basis_after,
			reopened_basis,
			count_after,
			reopened_count,
		))
	}
	if invariant_result := tempid_order_database_invariant(t, &connection, expected, entity, fmt.tprintf("%s reopened", label)); invariant_result.status != .Pass {
		return 0, invariant_result
	}
	checkpoint := basis_after - 1
	if log_result := tempid_order_log_invariant(t, &connection, expected, entity, checkpoint, basis_after, fmt.tprintf("%s reopened", label)); log_result.status != .Pass {
		return 0, log_result
	}
	pbt.record_event(t, "durable", "tempid-order-reopen", "ok", fmt.tprintf(
		"basis=%d transactions=%d",
		reopened_basis,
		reopened_count,
	))
	return entity, pbt.pass()
}

tempid_order_setup :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tempid_Order_Expected,
) -> pbt.Result {
	schema := TEMPID_ORDER_SCHEMA
	if expected.tuple_identity {
		schema = TEMPID_TUPLE_ORDER_SCHEMA
	}
	schema_report, schema_ok := vev.transact(connection, schema, t.value_allocator)
	if !schema_ok || !strings.contains(schema_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not install tempid-order schema: %s", schema_report))
	}
	if expected.seed_existing {
		seed := fmt.tprintf(`[[:db/add 1 :order/key "%s"]]`, expected.key)
		if expected.tuple_identity {
			seed = fmt.tprintf(
				`[[:db/add 1 :order/key "%s"] [:db/add 1 :order/rank %d]]`,
				expected.key,
				expected.rank,
			)
		}
		seed_report, seed_ok := vev.transact(connection, seed, t.value_allocator)
		if !seed_ok || !strings.contains(seed_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not seed tempid-order identity: %s", seed_report))
		}
	}
	return pbt.pass()
}

tempid_order_backend_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	tx: string,
	expected: Tempid_Order_Expected,
	label: string,
) -> (basis_after, entity: u64, result: pbt.Result) {
	basis_before, basis_before_ok := tempid_order_basis(connection)
	if !basis_before_ok {
		return 0, 0, pbt.error(fmt.tprintf("could not read %s basis before transaction", label))
	}
	report, transact_ok := vev.transact(connection, tx, t.value_allocator)
	pbt.note(t, fmt.tprintf("%s report=%s", label, report))
	if !transact_ok || !strings.contains(report, ":ok true") {
		return 0, 0, pbt.fail(fmt.tprintf("%s transaction failed: %s", label, report))
	}
	basis_after_ok: bool
	basis_after, basis_after_ok = tempid_order_basis(connection)
	if !basis_after_ok || basis_after != basis_before + 1 {
		return 0, 0, pbt.fail(fmt.tprintf(
			"%s basis: before=%d after=%d",
			label,
			basis_before,
			basis_after,
		))
	}
	entity_ok: bool
	entity, entity_ok = tempid_order_lookup_entity(connection, expected)
	if !entity_ok || (expected.seed_existing && entity != 1) {
		return 0, 0, pbt.fail(fmt.tprintf("%s could not resolve expected identity entity", label))
	}
	tempids := [?]string{"a", "b", "c"}
	for tempid in tempids {
		mapping := fmt.tprintf(`"%s" [:vev/entity %d]`, tempid, entity)
		if !strings.contains(report, mapping) {
			return 0, 0, pbt.fail(fmt.tprintf("%s omitted tempid mapping %s", label, mapping))
		}
	}
	if invariant_result := tempid_order_database_invariant(t, connection, expected, entity, label); invariant_result.status != .Pass {
		return 0, 0, invariant_result
	}
	if log_result := tempid_order_log_invariant(t, connection, expected, entity, basis_before, basis_after, label); log_result.status != .Pass {
		return 0, 0, log_result
	}
	return basis_after, entity, pbt.pass()
}

tempid_order_lookup_entity :: proc(connection: ^$Connection, expected: Tempid_Order_Expected) -> (entity: u64, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return 0, false
	}
	defer vev.close(&database)
	attribute := ":order/key"
	value := fmt.tprintf(`"%s"`, expected.key)
	if expected.tuple_identity {
		attribute = ":order/key+rank"
		value = fmt.tprintf(`["%s" %d]`, expected.key, expected.rank)
	}
	lookup, lookup_ok := vev.entity_lookup_ref(&database, attribute, value)
	if !lookup_ok {
		return 0, false
	}
	defer vev.close(&lookup)
	return vev.entity_id(&lookup)
}

tempid_order_basis :: proc(connection: ^$Connection) -> (basis: u64, ok: bool) {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return 0, false
	}
	defer vev.close(&database)
	return vev.basis_t(&database)
}

tempid_order_database_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tempid_Order_Expected,
	expected_entity: u64,
	label: string,
) -> pbt.Result {
	if expected.tuple_identity {
		return tempid_tuple_order_database_invariant(t, connection, expected, expected_entity, label)
	}
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s database", label))
	}
	defer vev.close(&database)
	result, query_ok := vev.query(
		&database,
		`[:find ?e ?key ?age ?likes ?rank :where [?e :order/key ?key] [?e :order/age ?age] [?e :order/likes ?likes] [?e :order/rank ?rank]]`,
	)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s state query failed", label))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok || vev.item_count(relation) != 1 {
		return pbt.fail(fmt.tprintf("%s entity count: expected=1 actual=%d", label, vev.item_count(relation)))
	}
	row, row_ok := vev.item(relation, 0)
	if !row_ok || vev.item_count(row) != 5 {
		return pbt.error(fmt.tprintf("%s state row is malformed", label))
	}
	entity_value, entity_ok := vev.item(row, 0)
	key_value, key_ok := vev.item(row, 1)
	age_value, age_ok := vev.item(row, 2)
	likes_value, likes_ok := vev.item(row, 3)
	rank_value, rank_ok := vev.item(row, 4)
	entity, entity_value_ok := vev.as_int(entity_value)
	key, key_value_ok := vev.as_string(key_value, t.value_allocator)
	age, age_value_ok := vev.as_int(age_value)
	likes, likes_value_ok := vev.as_string(likes_value, t.value_allocator)
	rank, rank_value_ok := vev.as_int(rank_value)
	if !entity_ok || !key_ok || !age_ok || !likes_ok || !rank_ok ||
	   !entity_value_ok || !key_value_ok || !age_value_ok || !likes_value_ok ||
	   !rank_value_ok {
		return pbt.error(fmt.tprintf("%s state row has unexpected types", label))
	}
	if entity < 0 || u64(entity) != expected_entity ||
	   key != expected.key || age != i64(expected.age) ||
	   likes != expected.likes || rank != i64(expected.rank) {
		return pbt.fail(fmt.tprintf(
			"%s state mismatch: entity=%d key=%s age=%d likes=%s rank=%d",
			label,
			entity,
			key,
			age,
			likes,
			rank,
		))
	}
	return pbt.pass()
}

tempid_tuple_order_database_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tempid_Order_Expected,
	expected_entity: u64,
	label: string,
) -> pbt.Result {
	database, database_ok := vev.db(connection)
	if !database_ok {
		return pbt.error(fmt.tprintf("could not retain %s tuple database", label))
	}
	defer vev.close(&database)
	result, query_ok := vev.query(
		&database,
		`[:find ?e ?key ?rank ?identity :where [?e :order/key ?key] [?e :order/rank ?rank] [?e :order/key+rank ?identity]]`,
	)
	if !query_ok {
		return pbt.error(fmt.tprintf("%s tuple state query failed", label))
	}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	if !relation_ok || vev.item_count(relation) != 1 {
		return pbt.fail(fmt.tprintf("%s tuple entity count: expected=1 actual=%d", label, vev.item_count(relation)))
	}
	row, row_ok := vev.item(relation, 0)
	if !row_ok || vev.item_count(row) != 4 {
		return pbt.error(fmt.tprintf("%s tuple state row is malformed", label))
	}
	entity_value, entity_ok := vev.item(row, 0)
	key_value, key_ok := vev.item(row, 1)
	rank_value, rank_ok := vev.item(row, 2)
	identity_value, identity_ok := vev.item(row, 3)
	entity, entity_value_ok := vev.as_int(entity_value)
	key, key_value_ok := vev.as_string(key_value, t.value_allocator)
	rank, rank_value_ok := vev.as_int(rank_value)
	if !entity_ok || !key_ok || !rank_ok || !identity_ok ||
	   !entity_value_ok || !key_value_ok || !rank_value_ok ||
	   entity < 0 || u64(entity) != expected_entity || key != expected.key ||
	   rank != i64(expected.rank) || vev.kind(identity_value) != .Vector ||
	   vev.item_count(identity_value) != 2 {
		return pbt.fail(fmt.tprintf("%s tuple state has unexpected entity or components", label))
	}
	identity_key_value, identity_key_ok := vev.item(identity_value, 0)
	identity_rank_value, identity_rank_ok := vev.item(identity_value, 1)
	identity_key, identity_key_value_ok := vev.as_string(identity_key_value, t.value_allocator)
	identity_rank, identity_rank_value_ok := vev.as_int(identity_rank_value)
	if !identity_key_ok || !identity_rank_ok || !identity_key_value_ok ||
	   !identity_rank_value_ok || identity_key != expected.key ||
	   identity_rank != i64(expected.rank) {
		return pbt.fail(fmt.tprintf("%s derived tuple identity is incorrect", label))
	}
	return pbt.pass()
}

tempid_order_log_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tempid_Order_Expected,
	expected_entity: u64,
	checkpoint, basis: u64,
	label: string,
) -> pbt.Result {
	if expected.tuple_identity {
		return tempid_tuple_order_log_invariant(t, connection, expected, expected_entity, checkpoint, basis, label)
	}
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s log", label))
	}
	defer vev.close(&log_value)
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s transaction range failed", label))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != 1 {
		return pbt.fail(fmt.tprintf("%s transaction range count is not one", label))
	}
	transaction, transaction_ok := vev.item(transactions_value, 0)
	t_value, t_ok := vev.get(transaction, ":t")
	data, data_ok := vev.get(transaction, ":data")
	actual_basis, actual_basis_ok := vev.as_int(t_value)
	if !transaction_ok || !t_ok || !data_ok || !actual_basis_ok || actual_basis < 0 ||
	   u64(actual_basis) != basis || vev.kind(data) != .Vector {
		return pbt.fail(fmt.tprintf("%s transaction range coordinate is malformed", label))
	}
	seen: [4]bool
	for datom_index in 0 ..< vev.item_count(data) {
		datom, datom_ok := vev.item(data, datom_index)
		if !datom_ok || vev.kind(datom) != .Vector || vev.item_count(datom) != 5 {
			return pbt.error(fmt.tprintf("%s datom %d is malformed", label, datom_index))
		}
		entity_value, entity_ok := vev.item(datom, 0)
		attribute_value, attribute_ok := vev.item(datom, 1)
		fact_value, fact_ok := vev.item(datom, 2)
		tx_value, tx_ok := vev.item(datom, 3)
		added_value, added_ok := vev.item(datom, 4)
		attribute, attribute_string_ok := vev.as_string(attribute_value, t.value_allocator)
		if !entity_ok || !attribute_ok || !fact_ok || !tx_ok || !added_ok ||
		   !attribute_string_ok {
			return pbt.error(fmt.tprintf("%s datom %d has unexpected types", label, datom_index))
		}
		if attribute == ":db/txInstant" {
			continue
		}
		entity, entity_value_ok := vev.as_entity(entity_value)
		tx, tx_entity_ok := vev.as_entity(tx_value)
		added, added_bool_ok := vev.as_bool(added_value)
		if !entity_value_ok || !tx_entity_ok || !added_bool_ok ||
		   entity != expected_entity ||
		   tx != vev.t_to_tx(basis) || !added {
			return pbt.fail(fmt.tprintf("%s datom %d has wrong envelope", label, datom_index))
		}
		attribute_index := -1
		switch attribute {
		case ":order/key":
			attribute_index = 0
			actual, actual_ok := vev.as_string(fact_value, t.value_allocator)
			if !actual_ok || actual != expected.key || expected.seed_existing {
				return pbt.fail(fmt.tprintf("%s has unexpected key datom", label))
			}
		case ":order/age":
			attribute_index = 1
			actual, actual_ok := vev.as_int(fact_value)
			if !actual_ok || actual != i64(expected.age) {
				return pbt.fail(fmt.tprintf("%s has unexpected age datom", label))
			}
		case ":order/likes":
			attribute_index = 2
			actual, actual_ok := vev.as_string(fact_value, t.value_allocator)
			if !actual_ok || actual != expected.likes {
				return pbt.fail(fmt.tprintf("%s has unexpected likes datom", label))
			}
		case ":order/rank":
			attribute_index = 3
			actual, actual_ok := vev.as_int(fact_value)
			if !actual_ok || actual != i64(expected.rank) {
				return pbt.fail(fmt.tprintf("%s has unexpected rank datom", label))
			}
		case:
			return pbt.fail(fmt.tprintf("%s has unexpected application attribute %s", label, attribute))
		}
		if seen[attribute_index] {
			return pbt.fail(fmt.tprintf("%s repeats application attribute %s", label, attribute))
		}
		seen[attribute_index] = true
	}
	if seen[0] == expected.seed_existing || !seen[1] || !seen[2] || !seen[3] {
		return pbt.fail(fmt.tprintf(
			"%s application datoms: key=%v age=%v likes=%v rank=%v",
			label,
			seen[0],
			seen[1],
			seen[2],
			seen[3],
		))
	}
	return pbt.pass()
}

tempid_tuple_order_log_invariant :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	expected: Tempid_Order_Expected,
	expected_entity: u64,
	checkpoint, basis: u64,
	label: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {
		return pbt.error(fmt.tprintf("could not retain %s tuple log", label))
	}
	defer vev.close(&log_value)
	transactions, range_ok := vev.tx_range_coordinates(&log_value, checkpoint + 1, basis + 1)
	if !range_ok {
		return pbt.error(fmt.tprintf("%s tuple transaction range failed", label))
	}
	defer vev.close(&transactions)
	transactions_value, value_ok := vev.value(&transactions)
	if !value_ok || vev.item_count(transactions_value) != 1 {
		return pbt.fail(fmt.tprintf("%s tuple transaction range count is not one", label))
	}
	transaction, transaction_ok := vev.item(transactions_value, 0)
	t_value, t_ok := vev.get(transaction, ":t")
	data, data_ok := vev.get(transaction, ":data")
	actual_basis, actual_basis_ok := vev.as_int(t_value)
	if !transaction_ok || !t_ok || !data_ok || !actual_basis_ok || actual_basis < 0 ||
	   u64(actual_basis) != basis || vev.kind(data) != .Vector {
		return pbt.fail(fmt.tprintf("%s tuple transaction range coordinate is malformed", label))
	}
	seen_components: [2]bool
	partial_added: [2]bool
	partial_retracted: [2]bool
	full_tuple_added := false
	for datom_index in 0 ..< vev.item_count(data) {
		datom, datom_ok := vev.item(data, datom_index)
		if !datom_ok || vev.kind(datom) != .Vector || vev.item_count(datom) != 5 {
			return pbt.error(fmt.tprintf("%s tuple datom %d is malformed", label, datom_index))
		}
		entity_value, entity_ok := vev.item(datom, 0)
		attribute_value, attribute_ok := vev.item(datom, 1)
		fact_value, fact_ok := vev.item(datom, 2)
		tx_value, tx_ok := vev.item(datom, 3)
		added_value, added_ok := vev.item(datom, 4)
		attribute, attribute_string_ok := vev.as_string(attribute_value, t.value_allocator)
		if !entity_ok || !attribute_ok || !fact_ok || !tx_ok || !added_ok ||
		   !attribute_string_ok {
			return pbt.error(fmt.tprintf("%s tuple datom %d has unexpected types", label, datom_index))
		}
		if attribute == ":db/txInstant" {
			continue
		}
		entity, entity_value_ok := vev.as_entity(entity_value)
		tx, tx_entity_ok := vev.as_entity(tx_value)
		added, added_bool_ok := vev.as_bool(added_value)
		if !entity_value_ok || !tx_entity_ok || !added_bool_ok ||
		   entity != expected_entity || tx != vev.t_to_tx(basis) {
			return pbt.fail(fmt.tprintf("%s tuple datom %d has wrong envelope", label, datom_index))
		}
		switch attribute {
		case ":order/key":
			actual, actual_ok := vev.as_string(fact_value, t.value_allocator)
			if !added || !actual_ok || actual != expected.key || seen_components[0] {
				return pbt.fail(fmt.tprintf("%s has unexpected tuple key datom", label))
			}
			seen_components[0] = true
		case ":order/rank":
			actual, actual_ok := vev.as_int(fact_value)
			if !added || !actual_ok || actual != i64(expected.rank) || seen_components[1] {
				return pbt.fail(fmt.tprintf("%s has unexpected tuple rank datom", label))
			}
			seen_components[1] = true
		case ":order/key+rank":
			if vev.kind(fact_value) != .Vector || vev.item_count(fact_value) != 2 {
				return pbt.fail(fmt.tprintf("%s has malformed derived tuple datom", label))
			}
			key_value, key_ok := vev.item(fact_value, 0)
			rank_value, rank_ok := vev.item(fact_value, 1)
			if !key_ok || !rank_ok {
				return pbt.fail(fmt.tprintf("%s has malformed derived tuple items", label))
			}
			key_present := vev.kind(key_value) != .Nil
			rank_present := vev.kind(rank_value) != .Nil
			if key_present {
				key, key_value_ok := vev.as_string(key_value, t.value_allocator)
				if !key_value_ok || key != expected.key {
					return pbt.fail(fmt.tprintf("%s has unexpected derived tuple key", label))
				}
			}
			if rank_present {
				rank, rank_value_ok := vev.as_int(rank_value)
				if !rank_value_ok || rank != i64(expected.rank) {
					return pbt.fail(fmt.tprintf("%s has unexpected derived tuple rank", label))
				}
			}
			if key_present && rank_present {
				if !added || full_tuple_added {
					return pbt.fail(fmt.tprintf("%s repeats or retracts the complete tuple", label))
				}
				full_tuple_added = true
			} else if key_present != rank_present {
				partial_index := 0
				if rank_present {
					partial_index = 1
				}
				if added {
					if partial_added[partial_index] {
						return pbt.fail(fmt.tprintf("%s repeats a partial tuple addition", label))
					}
					partial_added[partial_index] = true
				} else {
					if partial_retracted[partial_index] {
						return pbt.fail(fmt.tprintf("%s repeats a partial tuple retraction", label))
					}
					partial_retracted[partial_index] = true
				}
			} else {
				return pbt.fail(fmt.tprintf("%s has unexpected derived tuple datom", label))
			}
		case:
			return pbt.fail(fmt.tprintf("%s has unexpected tuple attribute %s", label, attribute))
		}
	}
	expected_application_datoms := !expected.seed_existing
	partial_pair := (partial_added[0] && partial_retracted[0] &&
	                 !partial_added[1] && !partial_retracted[1]) ||
	                (partial_added[1] && partial_retracted[1] &&
	                 !partial_added[0] && !partial_retracted[0])
	expected_partial_pair := expected_application_datoms && strings.contains(label, "resident")
	if seen_components[0] != expected_application_datoms ||
	   seen_components[1] != expected_application_datoms ||
	   full_tuple_added != expected_application_datoms ||
	   partial_pair != expected_partial_pair {
		return pbt.fail(fmt.tprintf(
			"%s tuple application datoms: key=%v rank=%v full=%v partial=%v existing=%v",
			label,
			seen_components[0],
			seen_components[1],
			full_tuple_added,
			partial_pair,
			expected.seed_existing,
		))
	}
	return pbt.pass()
}
