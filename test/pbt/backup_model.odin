// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

BACKUP_MODEL_TAGS := [?]string{"core", "durable", "backup", "snapshot", "transaction", "log", "atomic", "reopen", "model"}
BACKUP_MAX_ENTITIES :: 6
BACKUP_VALUE_COUNT :: 8
BACKUP_SCHEMA :: `[
	{:db/id 100 :db/ident :backup/score :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
]`

Backup_Case :: struct {
	entity_count:   int,
	scores:         [BACKUP_MAX_ENTITIES]int,
	source_entity:  int,
	source_score:   int,
	snapshot_entity: int,
	snapshot_score: int,
	reverse_seed:   bool,
}

backup_model_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := Backup_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, BACKUP_MAX_ENTITIES)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	for index in 0 ..< scenario.entity_count {
		scenario.scores[index] = pbt.draw(t, pbt.int_range(0, BACKUP_VALUE_COUNT - 1))
	}
	scenario.source_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.snapshot_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	scenario.source_score = pbt.draw(t, pbt.int_range(0, BACKUP_VALUE_COUNT - 2))
	if scenario.source_score >= scenario.scores[scenario.source_entity - 1] {scenario.source_score += 1}
	scenario.snapshot_score = pbt.draw(t, pbt.int_range(0, BACKUP_VALUE_COUNT - 2))
	if scenario.snapshot_score >= scenario.scores[scenario.snapshot_entity - 1] {scenario.snapshot_score += 1}
	pbt.cover(t, scenario.reverse_seed, 35, "backup-reverse-seed")
	pbt.cover(t, scenario.source_entity == scenario.snapshot_entity, 10, "backup-same-branch-entity")
	pbt.cover(t, scenario.source_entity != scenario.snapshot_entity, 45, "backup-different-branch-entity")
	pbt.cover(t, scenario.source_score == scenario.snapshot_score, 5, "backup-same-branch-value")

	source_path, source_path_ok := transaction_model_temp_path(t)
	if !source_path_ok {return pbt.error("could not allocate backup source path")}
	defer transaction_model_remove_store(source_path)
	snapshot_path, snapshot_path_ok := transaction_model_temp_path(t)
	if !snapshot_path_ok {return pbt.error("could not allocate backup destination path")}
	defer transaction_model_remove_store(snapshot_path)
	source, source_ok := vev.connect(&library, source_path)
	if !source_ok {return pbt.error("could not create backup source connection")}
	defer vev.close(&source)

	seed := backup_seed_edn(t, scenario)
	setup := [?]string{BACKUP_SCHEMA, seed}
	for tx in setup {
		report, ok := vev.transact(&source, tx, t.value_allocator)
		if !ok || !strings.contains(report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize backup model: %s", report))
		}
	}
	checkpoint_basis, checkpoint_basis_ok := vev.connection_basis_t(&source)
	checkpoint_count, checkpoint_count_ok := vev.connection_tx_count(&source)
	checkpoint_ids, checkpoint_ids_ok := vev.connection_tx_ids(&source, t.value_allocator)
	if !checkpoint_basis_ok || !checkpoint_count_ok || !checkpoint_ids_ok ||
	   len(checkpoint_ids) != int(checkpoint_count) {
		return pbt.error("could not read backup checkpoint coordinates")
	}
	source_checkpoint, source_checkpoint_ok := vev.db(&source)
	if !source_checkpoint_ok {return pbt.error("could not retain backup source checkpoint")}
	defer vev.close(&source_checkpoint)
	checkpoint_t, checkpoint_t_ok := vev.basis_t(&source_checkpoint)
	if !checkpoint_t_ok {return pbt.error("could not read backup checkpoint basis t")}

	backup_basis, backup_ok, backup_error := vev.backup(&source, snapshot_path, t.value_allocator)
	if !backup_ok || backup_error != "" || backup_basis != checkpoint_t {
		return pbt.fail(fmt.tprintf(
			"backup checkpoint mismatch: basis=%d/%d ok=%v error=%s",
			checkpoint_t,
			backup_basis,
			backup_ok,
			backup_error,
		))
	}
	basis_after_backup, basis_after_backup_ok := vev.connection_basis_t(&source)
	count_after_backup, count_after_backup_ok := vev.connection_tx_count(&source)
	if !basis_after_backup_ok || !count_after_backup_ok ||
	   basis_after_backup != checkpoint_basis || count_after_backup != checkpoint_count {
		return pbt.fail("backup changed source transaction coordinates")
	}

	source_tx := fmt.tprintf(
		"[[:db/add %d :backup/score %d]]",
		scenario.source_entity,
		scenario.source_score,
	)
	source_report, source_committed := vev.transact(&source, source_tx, t.value_allocator)
	if !source_committed || !strings.contains(source_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not mutate backup source branch: %s", source_report))
	}
	_, overwrite_ok, overwrite_error := vev.backup(&source, snapshot_path, t.value_allocator)
	if overwrite_ok || overwrite_error == "" {
		return pbt.fail(fmt.tprintf("backup overwrote existing destination: ok=%v error=%s", overwrite_ok, overwrite_error))
	}

	snapshot, snapshot_ok := vev.connect(&library, snapshot_path)
	if !snapshot_ok {return pbt.error("could not open backup snapshot")}
	defer vev.close(&snapshot)
	snapshot_basis, snapshot_basis_ok := vev.connection_basis_t(&snapshot)
	snapshot_count, snapshot_count_ok := vev.connection_tx_count(&snapshot)
	snapshot_ids, snapshot_ids_ok := vev.connection_tx_ids(&snapshot, t.value_allocator)
	if !snapshot_basis_ok || !snapshot_count_ok || !snapshot_ids_ok ||
	   snapshot_basis != checkpoint_basis || snapshot_count != checkpoint_count ||
	   !backup_tx_ids_equal(checkpoint_ids[:], snapshot_ids[:]) {
		return pbt.fail(fmt.tprintf(
			"backup snapshot coordinates mismatch: basis=%d/%d count=%d/%d",
			checkpoint_basis,
			snapshot_basis,
			checkpoint_count,
			snapshot_count,
		))
	}
	snapshot_checkpoint, snapshot_checkpoint_ok := vev.db(&snapshot)
	if !snapshot_checkpoint_ok {return pbt.error("could not retain backup destination checkpoint")}
	defer vev.close(&snapshot_checkpoint)
	if result := backup_database_check(t, &source_checkpoint, scenario, .Checkpoint, "retained source checkpoint"); result.status != .Pass {return result}
	if result := backup_database_check(t, &snapshot_checkpoint, scenario, .Checkpoint, "backup checkpoint"); result.status != .Pass {return result}

	snapshot_tx := fmt.tprintf(
		"[[:db/add %d :backup/score %d]]",
		scenario.snapshot_entity,
		scenario.snapshot_score,
	)
	snapshot_report, snapshot_committed := vev.transact(&snapshot, snapshot_tx, t.value_allocator)
	if !snapshot_committed || !strings.contains(snapshot_report, ":ok true") {
		return pbt.error(fmt.tprintf("could not mutate backup snapshot branch: %s", snapshot_report))
	}
	if result := backup_connection_check(t, &source, scenario, .Source, checkpoint_basis, checkpoint_count, checkpoint_ids[:], "source branch"); result.status != .Pass {return result}
	if result := backup_connection_check(t, &snapshot, scenario, .Snapshot, checkpoint_basis, checkpoint_count, checkpoint_ids[:], "snapshot branch"); result.status != .Pass {return result}

	vev.close(&source)
	vev.close(&snapshot)
	source_reopened_ok: bool
	source, source_reopened_ok = vev.connect(&library, source_path)
	if !source_reopened_ok {return pbt.error("could not reopen backup source branch")}
	snapshot_reopened_ok: bool
	snapshot, snapshot_reopened_ok = vev.connect(&library, snapshot_path)
	if !snapshot_reopened_ok {return pbt.error("could not reopen backup snapshot branch")}
	if result := backup_connection_check(t, &source, scenario, .Source, checkpoint_basis, checkpoint_count, checkpoint_ids[:], "reopened source branch"); result.status != .Pass {return result}
	return backup_connection_check(t, &snapshot, scenario, .Snapshot, checkpoint_basis, checkpoint_count, checkpoint_ids[:], "reopened snapshot branch")
}

Backup_Branch :: enum {
	Checkpoint,
	Source,
	Snapshot,
}

backup_seed_edn :: proc(t: ^pbt.T, scenario: Backup_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {entity = scenario.entity_count - offset}
		append(&parts, fmt.tprintf("[:db/add %d :backup/score %d]", entity, scenario.scores[entity - 1]))
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

backup_connection_check :: proc(
	t: ^pbt.T,
	connection: ^vev.Durable_Connection,
	scenario: Backup_Case,
	branch: Backup_Branch,
	checkpoint_basis, checkpoint_count: u64,
	checkpoint_ids: []u64,
	backend: string,
) -> pbt.Result {
	basis, basis_ok := vev.connection_basis_t(connection)
	count, count_ok := vev.connection_tx_count(connection)
	ids, ids_ok := vev.connection_tx_ids(connection, t.value_allocator)
	if !basis_ok || !count_ok || !ids_ok || basis != checkpoint_basis + 1 ||
	   count != checkpoint_count + 1 || len(ids) != len(checkpoint_ids) + 1 ||
	   !backup_tx_ids_prefix(checkpoint_ids, ids[:]) {
		return pbt.fail(fmt.tprintf(
			"%s backup branch coordinates mismatch: basis=%d/%d count=%d/%d ids=%d/%d",
			backend,
			basis,
			checkpoint_basis + 1,
			count,
			checkpoint_count + 1,
			len(ids),
			len(checkpoint_ids) + 1,
		))
	}
	database, database_ok := vev.db(connection)
	if !database_ok {return pbt.error(fmt.tprintf("could not retain %s database", backend))}
	defer vev.close(&database)
	return backup_database_check(t, &database, scenario, branch, backend)
}

backup_database_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: Backup_Case,
	branch: Backup_Branch,
	backend: string,
) -> pbt.Result {
	for entity in 1 ..= scenario.entity_count {
		expected := scenario.scores[entity - 1]
		if branch == .Source && entity == scenario.source_entity {expected = scenario.source_score}
		if branch == .Snapshot && entity == scenario.snapshot_entity {expected = scenario.snapshot_score}
		query := fmt.tprintf("[:find ?score . :where [%d :backup/score ?score]]", entity)
		result, query_ok := vev.query(database, query)
		if !query_ok {return pbt.error(fmt.tprintf("%s backup score query failed", backend))}
		value, value_ok := vev.value(&result)
		actual, actual_ok := vev.as_int(value)
		vev.close(&result)
		if !value_ok || !actual_ok || actual != i64(expected) {
			return pbt.fail(fmt.tprintf("%s backup score mismatch for entity=%d: expected=%d actual=%d", backend, entity, expected, actual))
		}
	}
	return pbt.pass()
}

backup_tx_ids_equal :: proc(left, right: []u64) -> bool {
	return len(left) == len(right) && backup_tx_ids_prefix(left, right)
}

backup_tx_ids_prefix :: proc(prefix, values: []u64) -> bool {
	if len(values) < len(prefix) {return false}
	for value, index in prefix {
		if value != values[index] {return false}
	}
	return true
}
