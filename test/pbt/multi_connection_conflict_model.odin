package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

MULTI_CONNECTION_CONFLICT_TAGS := [?]string{"core", "transaction", "durable", "multi-connection", "resident", "cas", "unique", "atomic", "failure", "snapshot", "log", "reopen", "model"}

MULTI_CONNECTION_CONFLICT_SCHEMA :: `[
	{:db/id 100 :db/ident :conflict/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :conflict/email :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/value}
	{:db/id 102 :db/ident :conflict/marker :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
]`

Multi_Connection_Conflict_Kind :: enum {
	CAS,
	Unique,
}

Multi_Connection_Conflict_Case :: struct {
	kind:              Multi_Connection_Conflict_Kind,
	stale_is_right:    bool,
	external_value:    int,
	replacement_value: int,
	followup_value:    int,
}

multi_connection_conflict_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Multi_Connection_Conflict_Case{
		kind = Multi_Connection_Conflict_Kind(pbt.draw(t, pbt.int_range(0, 1))),
		stale_is_right = pbt.draw(t, pbt.boolean()),
		external_value = pbt.draw(t, pbt.int_range(1, MODEL_VALUE_COUNT - 1)),
		replacement_value = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1)),
		followup_value = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1)),
	}
	pbt.cover(t, scenario.kind == .CAS, 35, "stale-conflict-cas")
	pbt.cover(t, scenario.kind == .Unique, 35, "stale-conflict-unique")
	pbt.cover(t, scenario.stale_is_right, 35, "stale-conflict-right-resident")
	pbt.cover(t, !scenario.stale_is_right, 35, "stale-conflict-left-resident")
	pbt.cover(t, scenario.replacement_value == scenario.external_value, 10, "stale-conflict-same-replacement")

	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate stale-conflict path")}
	defer transaction_model_remove_store(path)
	left, left_ok := vev.connect(&library, path)
	if !left_ok {return pbt.error("could not open stale-conflict left connection")}
	defer vev.close(&left)
	right, right_ok := vev.connect(&library, path)
	if !right_ok {return pbt.error("could not open stale-conflict right connection")}
	defer vev.close(&right)

	stale := &left
	fresh := &right
	if scenario.stale_is_right {
		stale = &right
		fresh = &left
	}
	setup := [?]string{
		MULTI_CONNECTION_CONFLICT_SCHEMA,
		`[{:db/id 1 :conflict/name "ada"}]`,
	}
	for tx in setup {
		report, ok := vev.transact(fresh, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize stale conflict: tx=%s report=%s", tx, report))
		}
	}
	if !vev.ensure_resident(stale) {return pbt.error("could not make conflict peer resident")}

	checkpoint, checkpoint_ok := vev.db(stale)
	if !checkpoint_ok {return pbt.error("could not retain pre-conflict checkpoint")}
	defer vev.close(&checkpoint)
	if result := multi_connection_conflict_state_check(t, &checkpoint, scenario, .Checkpoint, "pre-conflict checkpoint"); result.status != .Pass {
		return result
	}

	external_tx := multi_connection_conflict_external_tx(scenario)
	external_report, external_ok := vev.transact(fresh, external_tx, t.value_allocator)
	if !external_ok || !strings.contains(external_report, ":ok true") {
		return pbt.error(fmt.tprintf("external conflict setup failed: tx=%s report=%s", external_tx, external_report))
	}
	if result := multi_connection_metadata_check(t, &left, &right, 3, "after external conflict setup"); result.status != .Pass {
		return result
	}
	external_log, external_log_ok := index_maintenance_log_edn(t, fresh)
	if !external_log_ok {return pbt.error("could not retain external conflict log")}

	conflict_tx := multi_connection_conflict_tx(scenario)
	conflict_report, conflict_committed := vev.transact(stale, conflict_tx, t.value_allocator)
	if conflict_committed || !strings.contains(conflict_report, ":ok false") {
		return pbt.fail(fmt.tprintf("stale semantic conflict committed: tx=%s report=%s", conflict_tx, conflict_report))
	}
	expected_error := ":db.fn/cas failed"
	if scenario.kind == .Unique {expected_error = "schema unique conflict"}
	if !strings.contains(conflict_report, expected_error) {
		return pbt.fail(fmt.tprintf("stale conflict returned wrong error: expected=%q report=%s", expected_error, conflict_report))
	}
	if result := multi_connection_metadata_check(t, &left, &right, 3, "after rejected stale conflict"); result.status != .Pass {
		return result
	}
	left_basis, left_basis_ok := vev.connection_basis_t(&left)
	right_basis, right_basis_ok := vev.connection_basis_t(&right)
	if !left_basis_ok || !right_basis_ok || left_basis != vev.t_to_tx(3) || right_basis != vev.t_to_tx(3) {
		return pbt.fail(fmt.tprintf("rejected conflict did not converge connection bases: left=%d right=%d", left_basis, right_basis))
	}
	stale_db, stale_db_ok := vev.db(stale)
	if !stale_db_ok {return pbt.error("could not retain refreshed stale database")}
	if result := multi_connection_conflict_state_check(t, &stale_db, scenario, .External, "refreshed stale connection"); result.status != .Pass {
		vev.close(&stale_db)
		return result
	}
	vev.close(&stale_db)
	stale_log, stale_log_ok := index_maintenance_log_edn(t, stale)
	if !stale_log_ok || stale_log != external_log {
		return pbt.fail("rejected stale conflict changed or failed to refresh the transaction log")
	}
	if result := multi_connection_conflict_state_check(t, &checkpoint, scenario, .Checkpoint, "checkpoint after rejection"); result.status != .Pass {
		return result
	}

	followup_tx := fmt.tprintf(
		`[[:db/add 2 :conflict/marker "%s"]]`,
		MODEL_NAMES[scenario.followup_value],
	)
	followup_report, followup_ok := vev.transact(stale, followup_tx, t.value_allocator)
	if !followup_ok || !strings.contains(followup_report, ":ok true") {
		return pbt.fail(fmt.tprintf("valid transaction after stale conflict failed: %s", followup_report))
	}
	if result := multi_connection_metadata_check(t, &left, &right, 4, "after valid stale-conflict followup"); result.status != .Pass {
		return result
	}
	final_db, final_db_ok := vev.db(stale)
	if !final_db_ok {return pbt.error("could not retain final conflict database")}
	if result := multi_connection_conflict_state_check(t, &final_db, scenario, .Final, "final conflict writer"); result.status != .Pass {
		vev.close(&final_db)
		return result
	}
	vev.close(&final_db)
	final_log, final_log_ok := index_maintenance_log_edn(t, stale)
	if !final_log_ok {return pbt.error("could not retain final conflict log")}

	vev.close(&left)
	vev.close(&right)
	left, left_ok = vev.connect(&library, path)
	right, right_ok = vev.connect(&library, path)
	if !left_ok || !right_ok {return pbt.error("could not reopen stale-conflict connections")}
	connections := [?]^vev.Durable_Connection{&left, &right}
	for connection, index in connections {
		database, database_ok := vev.db(connection)
		if !database_ok {return pbt.error("could not retain reopened conflict database")}
		result := multi_connection_conflict_state_check(t, &database, scenario, .Final, fmt.tprintf("reopened conflict %d", index))
		vev.close(&database)
		if result.status != .Pass {return result}
		log_text, log_ok := index_maintenance_log_edn(t, connection)
		if !log_ok || log_text != final_log {return pbt.fail("reopened conflict log differs from committed log")}
	}
	return multi_connection_conflict_state_check(t, &checkpoint, scenario, .Checkpoint, "checkpoint after reopen")
}

Multi_Connection_Conflict_Phase :: enum {
	Checkpoint,
	External,
	Final,
}

multi_connection_conflict_external_tx :: proc(scenario: Multi_Connection_Conflict_Case) -> string {
	if scenario.kind == .CAS {
		return fmt.tprintf(
			`[[:db/add 1 :conflict/name "%s"]]`,
			MODEL_NAMES[scenario.external_value],
		)
	}
	return fmt.tprintf(
		`[[:db/add 1 :conflict/email "%s@example.test"]]`,
		MODEL_NAMES[scenario.external_value],
	)
}

multi_connection_conflict_tx :: proc(scenario: Multi_Connection_Conflict_Case) -> string {
	prefix := fmt.tprintf(
		`[:db/add 2 :conflict/marker "%s"]`,
		MODEL_NAMES[scenario.replacement_value],
	)
	if scenario.kind == .CAS {
		return fmt.tprintf(
			`[%s [:db.fn/cas 1 :conflict/name "ada" "%s"]]`,
			prefix,
			MODEL_NAMES[scenario.replacement_value],
		)
	}
	return fmt.tprintf(
		`[%s [:db/add 2 :conflict/email "%s@example.test"]]`,
		prefix,
		MODEL_NAMES[scenario.external_value],
	)
}

multi_connection_conflict_state_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: Multi_Connection_Conflict_Case,
	phase: Multi_Connection_Conflict_Phase,
	label: string,
) -> pbt.Result {
	expected_basis := u64(2)
	if phase == .External {expected_basis = 3}
	if phase == .Final {expected_basis = 4}
	basis, basis_ok := vev.basis_t(database)
	if !basis_ok || basis != expected_basis {
		return pbt.fail(fmt.tprintf("%s basis: expected=%d actual=%d", label, expected_basis, basis))
	}
	expected_name := "ada"
	if phase != .Checkpoint && scenario.kind == .CAS {
		expected_name = MODEL_NAMES[scenario.external_value]
	}
	if result := multi_connection_conflict_attr_check(t, database, 1, ":conflict/name", expected_name, true, label); result.status != .Pass {
		return result
	}
	expect_email := phase != .Checkpoint && scenario.kind == .Unique
	email := fmt.tprintf("%s@example.test", MODEL_NAMES[scenario.external_value])
	if result := multi_connection_conflict_attr_check(t, database, 1, ":conflict/email", email, expect_email, label); result.status != .Pass {
		return result
	}
	if result := multi_connection_conflict_attr_check(t, database, 2, ":conflict/email", email, false, label); result.status != .Pass {
		return result
	}
	marker := MODEL_NAMES[scenario.followup_value]
	return multi_connection_conflict_attr_check(t, database, 2, ":conflict/marker", marker, phase == .Final, label)
}

multi_connection_conflict_attr_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	entity: u64,
	attribute, expected: string,
	expect_value: bool,
	label: string,
) -> pbt.Result {
	actual := query_name_attr(t, database, entity, attribute)
	if !actual.ok {return pbt.error(fmt.tprintf("%s query failed for %s", label, attribute))}
	if !expect_value && actual.found {
		return pbt.fail(fmt.tprintf("%s expected no %s on entity %d, found %q", label, attribute, entity, actual.name))
	}
	if expect_value && (!actual.found || actual.name != expected) {
		return pbt.fail(fmt.tprintf("%s expected %s=%q on entity %d, found=%v value=%q", label, attribute, expected, entity, actual.found, actual.name))
	}
	return pbt.pass()
}
