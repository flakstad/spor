// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:os"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

CORE_TAGS := [?]string{"core", "model"}
SNAPSHOT_TAGS := [?]string{"core", "snapshot", "transaction"}

library: vev.Library

Query_Name_Result :: struct {
	name:  string,
	found: bool,
	ok:    bool,
}

query_name :: proc(t: ^pbt.T, database: ^vev.DB, entity: u64) -> Query_Name_Result {
	return query_name_attr(t, database, entity, ":user/name")
}

query_name_attr :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	entity: u64,
	attribute: string,
) -> Query_Name_Result {
	query := fmt.tprintf(
		`[:find ?name . :where [%d %s ?name]]`,
		entity,
		attribute,
	)
	result, query_ok := vev.query(
		database,
		query,
	)
	if !query_ok {
		return {}
	}
	defer vev.close(&result)

	value, value_ok := vev.value(&result)
	if !value_ok {
		return {}
	}
	if vev.kind(value) == .Nil {
		return Query_Name_Result{found = false, ok = true}
	}

	name, name_ok := vev.as_string(value, t.value_allocator)
	if !name_ok {
		return {}
	}
	return Query_Name_Result{name = name, found = true, ok = true}
}

expect_name :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	entity: u64,
	expected: string,
	label: string,
) -> pbt.Result {
	actual := query_name(t, database, entity)
	if !actual.ok {
		return pbt.error(fmt.tprintf("%s query failed", label))
	}
	if !actual.found {
		return pbt.fail(fmt.tprintf("%s: expected name %q, found nil", label, expected))
	}
	if actual.name != expected {
		return pbt.fail(fmt.tprintf("%s: expected name %q, found %q", label, expected, actual.name))
	}
	return pbt.pass()
}

expect_no_name :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	entity: u64,
	label: string,
) -> pbt.Result {
	actual := query_name(t, database, entity)
	if !actual.ok {
		return pbt.error(fmt.tprintf("%s query failed", label))
	}
	if actual.found {
		return pbt.fail(fmt.tprintf("%s: expected nil, found name %q", label, actual.name))
	}
	return pbt.pass()
}

time_coordinate_round_trips :: proc(t: ^pbt.T) -> pbt.Result {
	zero_case := pbt.draw(t, pbt.int_range(0, 9)) == 0
	basis := u64(0)
	if !zero_case {
		basis = pbt.draw(t, pbt.u64_range(1, 1_000_000))
	}
	pbt.cover(t, basis == 0, 5, "zero-basis")
	pbt.cover(t, basis > 0, 80, "transaction-basis")
	return pbt.equal(vev.tx_to_t(vev.t_to_tx(basis)), basis)
}

db_with_preserves_source_snapshot :: proc(t: ^pbt.T) -> pbt.Result {
	entity := u64(pbt.draw(t, pbt.int_range(1, 128)))
	base_name := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 1, 16))
	later_name := fmt.tprintf("%s-later", base_name)
	pbt.note(t, fmt.tprintf("entity=%d base=%q later=%q", entity, base_name, later_name))
	pbt.cover(t, entity <= 16, 10, "low-entity")
	pbt.cover(t, entity > 16, 70, "high-entity")

	connection, connection_ok := vev.create_conn(&library)
	if !connection_ok {
		return pbt.error("could not create in-memory Vev connection")
	}
	defer vev.close(&connection)

	source, source_ok := vev.db(&connection)
	if !source_ok {
		return pbt.error("could not retain source snapshot")
	}
	defer vev.close(&source)

	with_tx := fmt.tprintf(`[[:db/add %d :user/name "%s"]]`, entity, base_name)
	derived, derived_ok := vev.db_with(&source, with_tx)
	if !derived_ok {
		return pbt.error("db-with failed for generated transaction")
	}
	defer vev.close(&derived)

	if result := expect_no_name(t, &source, entity, "source after db-with"); result.status != .Pass {
		return result
	}
	if result := expect_name(t, &derived, entity, base_name, "derived snapshot"); result.status != .Pass {
		return result
	}

	live_tx := fmt.tprintf(`[[:db/add %d :user/name "%s"]]`, entity, later_name)
	tx_result, tx_ok := vev.transact(&connection, live_tx, t.value_allocator)
	if !tx_ok {
		return pbt.error(fmt.tprintf("connection transaction failed: %s", tx_result))
	}

	live, live_ok := vev.db(&connection)
	if !live_ok {
		return pbt.error("could not retain live database")
	}
	defer vev.close(&live)

	if result := expect_no_name(t, &source, entity, "source after connection transaction"); result.status != .Pass {
		return result
	}
	if result := expect_name(t, &derived, entity, base_name, "derived after connection transaction"); result.status != .Pass {
		return result
	}
	return expect_name(t, &live, entity, later_name, "live database")
}

main :: proc() {
	loaded: bool
	library, loaded = vev.load_default()
	if !loaded {
		fmt.eprintln("could not load Vev native library; set VEV_LIB to its path")
		os.exit(1)
	}

	properties := [?]pbt.Property_Case{
		{
			name = "time coordinates round-trip",
			property = time_coordinate_round_trips,
			description = "converting a basis t to a transaction entity and back preserves t",
			tags = CORE_TAGS[:],
		},
		{
			name = "db-with preserves source snapshot",
			property = db_with_preserves_source_snapshot,
			description = "a hypothetical database and a later live transaction cannot mutate retained snapshots",
			tags = SNAPSHOT_TAGS[:],
		},
		{
			name = "resident transactions agree with model",
			property = transaction_model_property,
			description = "generated add and retract sequences agree with an independent cardinality model",
			tags = TRANSACTION_MODEL_TAGS[:],
		},
		{
			name = "resident and durable transactions agree",
			property = transaction_differential_property,
			description = "generated transactions preserve snapshots, time filters, history, and exact transaction-log ranges across backends and reopen",
			tags = DIFFERENTIAL_MODEL_TAGS[:],
		},
		{
			name = "atomic transaction batches agree with model",
			property = transaction_batch_property,
			description = "generated multi-operation transactions apply atomically and in order across resident, SQLite, and reopen",
			tags = BATCH_MODEL_TAGS[:],
		},
		{
			name = "conditional transactions preserve atomicity",
			property = transaction_cas_property,
			description = "generated successful and stale CAS transactions preserve state, coordinates, and exact logs across backends and reopen",
			tags = CAS_MODEL_TAGS[:],
		},
		{
			name = "lookup refs agree across backends",
			property = transaction_lookup_property,
			description = "generated lookup-ref updates, retractions, missing refs, and identity upserts preserve state, coordinates, and exact logs",
			tags = LOOKUP_MODEL_TAGS[:],
		},
		{
			name = "identity upserts allocate stable entities",
			property = identity_allocation_property,
			description = "generated identity upserts allocate once, resolve tempids consistently, and preserve exact state and logs across backends and reopen",
			tags = IDENTITY_ALLOCATION_TAGS[:],
		},
		{
			name = "identity conflicts roll back atomically",
			property = identity_conflict_property,
			description = "generated multi-identity upserts either merge consistently or roll back preceding work without changing coordinates or logs",
			tags = IDENTITY_CONFLICT_TAGS[:],
		},
		{
			name = "tempid upserts are order independent",
			property = tempid_order_property,
			description = "generated permutations of same-transaction tempid upserts converge on one entity with isomorphic state, consistent reports, exact logs, and reopen results",
			tags = TEMPID_ORDER_TAGS[:],
		},
		{
			name = "tuple tempid upserts are order independent",
			property = tempid_tuple_order_property,
			description = "generated component permutations converge through tuple identities with stable allocation, state parity, backend-specific exact logs, and reopen results",
			tags = TEMPID_TUPLE_ORDER_TAGS[:],
		},
		{
			name = "tuple map updates preserve atomic grouping",
			property = tuple_update_property,
			description = "generated vector updates roll back on tuple intermediate conflicts while equivalent map updates commit atomically with exact state, logs, and reopen results",
			tags = TUPLE_UPDATE_TAGS[:],
		},
		{
			name = "component lifecycle follows statechart",
			property = component_lifecycle_property,
			description = "generated component lifecycle transitions preserve cascade semantics, exact logs, backend parity, and reopen state",
			tags = COMPONENT_LIFECYCLE_TAGS[:],
		},
		{
			name = "component trees cascade transitively",
			property = component_tree_property,
			description = "generated cardinality-many component trees retract exactly the selected subtree across resident, durable, logs, and reopen",
			tags = COMPONENT_TREE_TAGS[:],
		},
		{
			name = "datalog joins agree with relation model",
			property = query_join_property,
			description = "generated text and prepared joins, inputs, predicates, clause permutations, and empty relations agree with an independent model across resident, durable, and reopen",
			tags = QUERY_JOIN_TAGS[:],
		},
		{
			name = "datalog aggregates agree with grouped model",
			property = query_aggregate_property,
			description = "generated grouped aggregates over duplicates, mutations, filters, and clause permutations agree with an independent model across resident, durable, and reopen",
			tags = QUERY_AGGREGATE_TAGS[:],
		},
		{
			name = "datalog logic agrees with set model",
			property = query_logic_property,
			description = "generated or, not, or-join, and not-join queries agree with bitset algebra across resident, durable, mutations, and reopen",
			tags = QUERY_LOGIC_TAGS[:],
		},
		{
			name = "recursive rules agree with graph closure",
			property = query_recursive_property,
			description = "generated cyclic graphs and edge mutations agree with an independent transitive-closure model across resident, durable, and reopen",
			tags = QUERY_RECURSIVE_TAGS[:],
		},
		{
			name = "pull agrees with nested entity model",
			property = pull_model_property,
			description = "direct, many, and Datalog pull agree with generated scalar, cardinality-many, and nested-reference state across resident, durable, mutations, and reopen",
			tags = PULL_MODEL_TAGS[:],
		},
		{
			name = "datom indexes agree with ordered model",
			property = index_read_property,
			description = "generated scalar, cardinality-many, and reference facts preserve exact EAVT, AEVT, AVET, VAET, and index-range ordering across resident, durable, mutations, and reopen",
			tags = INDEX_READ_TAGS[:],
		},
		{
			name = "index pull agrees with paged walk model",
			property = index_pull_property,
			description = "generated AVET and AEVT walks preserve forward and reverse ordering, duplicate targets, offset, limit, mutations, backend parity, and reopen",
			tags = INDEX_PULL_TAGS[:],
		},
		{
			name = "entity views agree with fact model",
			property = entity_view_property,
			description = "entity lookup, get, values, reverse refs, touch, schema entities, and attribute metadata agree with generated state across resident, durable, mutations, and reopen",
			tags = ENTITY_VIEW_TAGS[:],
		},
		{
			name = "unique schema evolution follows statechart",
			property = schema_unique_property,
			description = "generated unique-schema transitions and data conflicts preserve atomic rollback, exact logs, backend parity, and reopen state",
			tags = SCHEMA_UNIQUE_TAGS[:],
		},
		{
			name = "cardinality schema evolution follows statechart",
			property = schema_cardinality_property,
			description = "generated one/many schema transitions and writes preserve modeled values, rollback, backend parity, transaction coordinates, and reopen state",
			tags = SCHEMA_CARDINALITY_TAGS[:],
		},
		{
			name = "value type schema evolution follows statechart",
			property = schema_value_type_property,
			description = "generated string/long schema transitions and typed writes preserve modeled values, rollback, backend parity, transaction coordinates, and reopen state",
			tags = SCHEMA_VALUE_TYPE_TAGS[:],
		},
		{
			name = "component schema evolution follows statechart",
			property = schema_component_property,
			description = "generated component enable/disable transitions preserve modeled cascade behavior, schema validation, rollback, backend parity, transaction coordinates, and reopen state",
			tags = SCHEMA_COMPONENT_TAGS[:],
		},
		{
			name = "index schema evolution follows statechart",
			property = schema_index_property,
			description = "generated index enable/disable transitions and writes preserve modeled AVET visibility, schema validation, rollback, backend parity, transaction coordinates, and reopen state",
			tags = SCHEMA_INDEX_TAGS[:],
		},
	}

	pbt.run_cli(properties[:], os.args[1:], {
		num_tests = 200,
		max_size = 100,
		shrink = true,
	})
}
