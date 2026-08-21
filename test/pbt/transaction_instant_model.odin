// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"
import "core:time"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

TRANSACTION_INSTANT_TAGS := [?]string{"core", "transaction", "instant", "metadata", "atomic", "snapshot", "history", "log", "durable", "differential", "reopen"}

Transaction_Instant_Case :: struct {
	base_day:      int,
	offset:        int,
	sequence:      int,
	reverse_setup: bool,
}

transaction_instant_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Transaction_Instant_Case{
		base_day = pbt.draw(t, pbt.int_range(2, 20)),
		offset = pbt.draw(t, pbt.int_range(-1, 1)),
		sequence = pbt.draw(t, pbt.int_range(1, 8)),
		reverse_setup = pbt.draw(t, pbt.boolean()),
	}
	pbt.cover(t, scenario.offset < 0, 20, "explicit-instant-older")
	pbt.cover(t, scenario.offset == 0, 20, "explicit-instant-equal")
	pbt.cover(t, scenario.offset > 0, 20, "explicit-instant-newer")
	pbt.cover(t, scenario.reverse_setup, 35, "explicit-instant-reverse-setup")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {return pbt.error("could not create explicit-instant resident connection")}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate explicit-instant durable path")}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {return pbt.error("could not create explicit-instant durable connection")}
	defer vev.close(&durable)

	seed := transaction_instant_seed_edn(scenario)
	if scenario.reverse_setup {
		seed = transaction_instant_seed_reversed_edn(scenario)
	}
	pbt.note(t, fmt.tprintf("explicit-instant seed=%s", seed))
	resident_seed, resident_seed_ok := vev.transact(&resident, seed, t.value_allocator)
	durable_seed, durable_seed_ok := vev.transact(&durable, seed, t.value_allocator)
	if !resident_seed_ok || !strings.contains(resident_seed, ":ok true") ||
	   !durable_seed_ok || !strings.contains(durable_seed, ":ok true") {
		return pbt.error(fmt.tprintf("could not initialize explicit instants: resident=%s durable=%s", resident_seed, durable_seed))
	}

	resident_before, resident_before_ok := transaction_cas_resident_basis(&resident)
	durable_before, durable_before_ok := vev.connection_basis_t(&durable)
	count_before, count_before_ok := vev.connection_tx_count(&durable)
	pbt.note(t, fmt.tprintf("explicit-instant coordinates resident=%d/%v durable=%d/%v count=%d/%v", resident_before, resident_before_ok, durable_before, durable_before_ok, count_before, count_before_ok))
	if !resident_before_ok || !durable_before_ok || !count_before_ok {
		return pbt.error("could not read explicit-instant coordinates")
	}
	resident_source, resident_source_ok := vev.db(&resident)
	if !resident_source_ok {return pbt.error("could not retain explicit-instant resident source")}
	defer vev.close(&resident_source)
	durable_source, durable_source_ok := vev.db(&durable)
	if !durable_source_ok {return pbt.error("could not retain explicit-instant durable source")}
	defer vev.close(&durable_source)

	tx := transaction_instant_candidate_edn(scenario)
	resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
	durable_report, durable_committed := vev.transact(&durable, tx, t.value_allocator)
	resident_committed := resident_call_ok && strings.contains(resident_report, ":ok true")
	expected_commit := scenario.offset >= 0
	pbt.note(t, fmt.tprintf(
		"explicit-instant offset=%d tx=%s resident=%s durable=%s",
		scenario.offset,
		tx,
		resident_report,
		durable_report,
	))
	if resident_committed != expected_commit || durable_committed != expected_commit {
		return pbt.fail(fmt.tprintf(
			"explicit-instant commit mismatch: expected=%v resident=%v durable=%v",
			expected_commit,
			resident_committed,
			durable_committed,
		))
	}
	if !expected_commit &&
	   (!strings.contains(resident_report, ":db/txInstant must be monotonic") ||
	    !strings.contains(durable_report, ":db/txInstant must be monotonic")) {
		return pbt.fail(fmt.tprintf("explicit-instant rollback error mismatch: resident=%s durable=%s", resident_report, durable_report))
	}
	if expected_commit {
		candidate := transaction_instant_text(scenario.base_day + scenario.offset)
		if !strings.contains(resident_report, candidate) || !strings.contains(durable_report, candidate) ||
		   !strings.contains(resident_report, ":audit/sequence") || !strings.contains(durable_report, ":audit/sequence") {
			return pbt.fail(fmt.tprintf("explicit-instant reports omitted timestamp or metadata: resident=%s durable=%s", resident_report, durable_report))
		}
	}

	resident_after, resident_after_ok := transaction_cas_resident_basis(&resident)
	durable_after, durable_after_ok := vev.connection_basis_t(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	delta := u64(0)
	if expected_commit {delta = 1}
	if !resident_after_ok || !durable_after_ok || !count_after_ok ||
	   resident_after != resident_before + delta || durable_after != durable_before + delta ||
	   count_after != count_before + delta {
		return pbt.fail(fmt.tprintf(
			"explicit-instant coordinates changed incorrectly: resident=%d/%d durable=%d/%d count=%d/%d",
			resident_before,
			resident_after,
			durable_before,
			durable_after,
			count_before,
			count_after,
		))
	}
	if result := transaction_instant_database_check(t, &resident_source, scenario, false, "resident source"); result.status != .Pass {return result}
	if result := transaction_instant_database_check(t, &durable_source, scenario, false, "durable source"); result.status != .Pass {return result}
	resident_db, resident_db_ok := vev.db(&resident)
	if !resident_db_ok {return pbt.error("could not retain explicit-instant resident result")}
	defer vev.close(&resident_db)
	durable_db, durable_db_ok := vev.db(&durable)
	if !durable_db_ok {return pbt.error("could not retain explicit-instant durable result")}
	defer vev.close(&durable_db)
	if result := transaction_instant_database_check(t, &resident_db, scenario, expected_commit, "resident result"); result.status != .Pass {return result}
	if result := transaction_instant_database_check(t, &durable_db, scenario, expected_commit, "durable result"); result.status != .Pass {return result}
	if result := transaction_instant_time_views_check(t, &resident_db, scenario, expected_commit, "resident result"); result.status != .Pass {return result}
	if result := transaction_instant_time_views_check(t, &durable_db, scenario, expected_commit, "durable result"); result.status != .Pass {return result}
	if result := transaction_instant_log_check(t, &resident, scenario, expected_commit, "resident log"); result.status != .Pass {return result}
	if result := transaction_instant_log_check(t, &durable, scenario, expected_commit, "durable log"); result.status != .Pass {return result}

	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen explicit-instant durable connection")}
	reopened_basis, reopened_basis_ok := vev.connection_basis_t(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != durable_after || reopened_count != count_after {
		return pbt.fail(fmt.tprintf("explicit-instant coordinates changed across reopen: basis=%d/%d count=%d/%d", durable_after, reopened_basis, count_after, reopened_count))
	}
	reopened_db, reopened_db_ok := vev.db(&durable)
	if !reopened_db_ok {return pbt.error("could not retain reopened explicit-instant database")}
	defer vev.close(&reopened_db)
	if result := transaction_instant_database_check(t, &reopened_db, scenario, expected_commit, "durable reopened result"); result.status != .Pass {return result}
	if result := transaction_instant_time_views_check(t, &reopened_db, scenario, expected_commit, "durable reopened result"); result.status != .Pass {return result}
	return transaction_instant_log_check(t, &durable, scenario, expected_commit, "durable reopened log")
}

transaction_instant_seed_edn :: proc(scenario: Transaction_Instant_Case) -> string {
	return fmt.tprintf(
		`[[:db/add :db/current-tx :db/txInstant #inst "%s"] [:db/add :db/current-tx :audit/sequence 0] [:db/add 1 :item/name "base"]]`,
		transaction_instant_text(scenario.base_day),
	)
}

transaction_instant_seed_reversed_edn :: proc(scenario: Transaction_Instant_Case) -> string {
	return fmt.tprintf(
		`[[:db/add 1 :item/name "base"] [:db/add :db/current-tx :audit/sequence 0] [:db/add :db/current-tx :db/txInstant #inst "%s"]]`,
		transaction_instant_text(scenario.base_day),
	)
}

transaction_instant_candidate_edn :: proc(scenario: Transaction_Instant_Case) -> string {
	return fmt.tprintf(
		`[[:db/add :db/current-tx :audit/sequence %d] [:db/add :db/current-tx :db/txInstant #inst "%s"] [:db/add 1 :item/name "value-%d"]]`,
		scenario.sequence,
		transaction_instant_text(scenario.base_day + scenario.offset),
		scenario.sequence,
	)
}

transaction_instant_text :: proc(day: int) -> string {
	return fmt.tprintf("2020-01-%02dT00:00:00.000Z", day)
}

transaction_instant_time :: proc(day: int) -> (result: time.Time, ok: bool) {
	return time.components_to_time(2020, 1, i64(day), 0, 0, 0)
}

transaction_instant_database_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: Transaction_Instant_Case,
	candidate_committed: bool,
	backend: string,
) -> pbt.Result {
	expected_name := "base"
	if candidate_committed {expected_name = fmt.tprintf("value-%d", scenario.sequence)}
	name := query_name_attr(t, database, 1, ":item/name")
	if !name.ok || !name.found || name.name != expected_name {
		return pbt.fail(fmt.tprintf("%s explicit-instant name mismatch: expected=%s actual=%s", backend, expected_name, name.name))
	}
	if result := transaction_instant_audit_check(t, database, 0, scenario.base_day, true, backend); result.status != .Pass {return result}
	return transaction_instant_audit_check(
		t,
		database,
		scenario.sequence,
		scenario.base_day + scenario.offset,
		candidate_committed,
		backend,
	)
}

transaction_instant_audit_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	sequence, day: int,
	expected: bool,
	backend: string,
) -> pbt.Result {
	query := fmt.tprintf(
		"[:find ?instant ?sequence :where [?tx :audit/sequence %d] [?tx :db/txInstant ?instant] [?tx :audit/sequence ?sequence]]",
		sequence,
	)
	result, query_ok := vev.query(database, query)
	if !query_ok {return pbt.error(fmt.tprintf("%s explicit-instant audit query failed", backend))}
	defer vev.close(&result)
	relation, relation_ok := vev.value(&result)
	expected_count := 0
	if expected {expected_count = 1}
	if !relation_ok || vev.item_count(relation) != expected_count {
		return pbt.fail(fmt.tprintf("%s explicit-instant audit count mismatch for sequence=%d", backend, sequence))
	}
	if !expected {return pbt.pass()}
	row, row_ok := vev.item(relation, 0)
	instant_value, instant_ok := vev.item(row, 0)
	sequence_value, sequence_ok := vev.item(row, 1)
	instant, instant_value_ok := vev.as_instant(instant_value)
	actual_sequence, sequence_value_ok := vev.as_int(sequence_value)
	expected_instant := i64(1_577_836_800_000 + (day - 1) * 86_400_000)
	if !row_ok || !instant_ok || !sequence_ok || !instant_value_ok || !sequence_value_ok ||
	   instant != expected_instant || actual_sequence != i64(sequence) {
		return pbt.fail(fmt.tprintf(
			"%s explicit-instant audit mismatch: sequence=%d/%d instant=%d/%d",
			backend,
			sequence,
			actual_sequence,
			expected_instant,
			instant,
		))
	}
	return pbt.pass()
}

transaction_instant_time_views_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: Transaction_Instant_Case,
	candidate_committed: bool,
	backend: string,
) -> pbt.Result {
	before_time, before_time_ok := transaction_instant_time(scenario.base_day - 1)
	base_time, base_time_ok := transaction_instant_time(scenario.base_day)
	after_time, after_time_ok := transaction_instant_time(scenario.base_day + 2)
	if !before_time_ok || !base_time_ok || !after_time_ok {
		return pbt.error("could not construct explicit-instant time boundaries")
	}
	as_of_before, as_of_before_ok := vev.as_of_time(database, before_time)
	if !as_of_before_ok {return pbt.error(fmt.tprintf("%s as-of before boundary failed", backend))}
	defer vev.close(&as_of_before)
	as_of_base, as_of_base_ok := vev.as_of_time(database, base_time)
	if !as_of_base_ok {return pbt.error(fmt.tprintf("%s as-of exact boundary failed", backend))}
	defer vev.close(&as_of_base)
	as_of_after, as_of_after_ok := vev.as_of_time(database, after_time)
	if !as_of_after_ok {return pbt.error(fmt.tprintf("%s as-of after boundary failed", backend))}
	defer vev.close(&as_of_after)
	since_before, since_before_ok := vev.since_time(database, before_time)
	if !since_before_ok {return pbt.error(fmt.tprintf("%s since before boundary failed", backend))}
	defer vev.close(&since_before)
	since_base, since_base_ok := vev.since_time(database, base_time)
	if !since_base_ok {return pbt.error(fmt.tprintf("%s since exact boundary failed", backend))}
	defer vev.close(&since_base)

	final_name := "base"
	if candidate_committed {final_name = fmt.tprintf("value-%d", scenario.sequence)}
	base_name := "base"
	if candidate_committed && scenario.offset == 0 {base_name = final_name}
	if result := transaction_instant_view_name_check(t, &as_of_before, "", fmt.tprintf("%s as-of before", backend)); result.status != .Pass {return result}
	if result := transaction_instant_view_name_check(t, &as_of_base, base_name, fmt.tprintf("%s as-of exact", backend)); result.status != .Pass {return result}
	if result := transaction_instant_view_name_check(t, &as_of_after, final_name, fmt.tprintf("%s as-of after", backend)); result.status != .Pass {return result}
	if result := transaction_instant_view_name_check(t, &since_before, final_name, fmt.tprintf("%s since before", backend)); result.status != .Pass {return result}
	since_name := ""
	if candidate_committed && scenario.offset > 0 {since_name = final_name}
	return transaction_instant_view_name_check(t, &since_base, since_name, fmt.tprintf("%s since exact", backend))
}

transaction_instant_view_name_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	expected, backend: string,
) -> pbt.Result {
	actual := query_name_attr(t, database, 1, ":item/name")
	if !actual.ok {return pbt.error(fmt.tprintf("%s name query failed", backend))}
	if expected == "" {
		if actual.found {return pbt.fail(fmt.tprintf("%s unexpectedly found name=%s", backend, actual.name))}
		return pbt.pass()
	}
	if !actual.found || actual.name != expected {
		return pbt.fail(fmt.tprintf("%s name mismatch: expected=%s actual=%s", backend, expected, actual.name))
	}
	return pbt.pass()
}

transaction_instant_log_check :: proc(
	t: ^pbt.T,
	connection: ^$Connection,
	scenario: Transaction_Instant_Case,
	candidate_committed: bool,
	backend: string,
) -> pbt.Result {
	log_value, log_ok := vev.log(connection)
	if !log_ok {return pbt.error(fmt.tprintf("%s could not retain transaction log", backend))}
	defer vev.close(&log_value)
	base_time, base_time_ok := transaction_instant_time(scenario.base_day)
	next_time, next_time_ok := transaction_instant_time(scenario.base_day + 1)
	if !base_time_ok || !next_time_ok {return pbt.error("could not construct explicit-instant log boundaries")}
	all, all_ok := vev.tx_range_all(&log_value)
	if !all_ok {return pbt.error(fmt.tprintf("%s all transaction range failed", backend))}
	defer vev.close(&all)
	first_day, first_day_ok := vev.tx_range(
		&log_value,
		vev.Time_Point(base_time),
		vev.Time_Point(next_time),
	)
	if !first_day_ok {return pbt.error(fmt.tprintf("%s bounded transaction range failed", backend))}
	defer vev.close(&first_day)
	from_next, from_next_ok := vev.tx_range(
		&log_value,
		vev.Time_Point(next_time),
		nil,
	)
	if !from_next_ok {return pbt.error(fmt.tprintf("%s open transaction range failed", backend))}
	defer vev.close(&from_next)
	before_base, before_base_ok := vev.tx_range(
		&log_value,
		nil,
		vev.Time_Point(base_time),
	)
	if !before_base_ok {return pbt.error(fmt.tprintf("%s prehistory transaction range failed", backend))}
	defer vev.close(&before_base)
	all_value, all_value_ok := vev.value(&all)
	first_day_value, first_day_value_ok := vev.value(&first_day)
	from_next_value, from_next_value_ok := vev.value(&from_next)
	before_base_value, before_base_value_ok := vev.value(&before_base)
	if !all_value_ok || !first_day_value_ok || !from_next_value_ok || !before_base_value_ok {
		return pbt.error(fmt.tprintf("%s could not read transaction range values", backend))
	}

	expected_all := 1
	if candidate_committed {expected_all += 1}
	expected_first_day := 1
	if candidate_committed && scenario.offset == 0 {expected_first_day += 1}
	expected_from_next := 0
	if candidate_committed && scenario.offset > 0 {expected_from_next = 1}
	if vev.item_count(all_value) != expected_all || vev.item_count(first_day_value) != expected_first_day ||
	   vev.item_count(from_next_value) != expected_from_next || vev.item_count(before_base_value) != 0 {
		return pbt.fail(fmt.tprintf(
			"%s instant transaction ranges mismatch: all=%d/%d first=%d/%d next=%d/%d before=%d/0",
			backend,
			vev.item_count(all_value),
			expected_all,
			vev.item_count(first_day_value),
			expected_first_day,
			vev.item_count(from_next_value),
			expected_from_next,
			vev.item_count(before_base_value),
		))
	}
	return pbt.pass()
}
