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
	inputs := fmt.tprintf("[%d]", entity)
	result, query_ok := vev.query(
		database,
		`[:find ?name . :in $ ?e :where [?e :user/name ?name]]`,
		inputs,
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
	}

	pbt.run_cli(properties[:], os.args[1:], {
		num_tests = 200,
		max_size = 100,
		shrink = true,
	})
}
