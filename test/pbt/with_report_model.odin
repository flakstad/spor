// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import vev "../../clients/odin/vev"

WITH_REPORT_TAGS := [?]string{"core", "transaction", "with-report", "snapshot", "overlay", "tempid", "model", "durable", "differential", "reopen"}
WITH_REPORT_BATCH_TAGS := [?]string{"core", "transaction", "with-report", "snapshot", "overlay", "batch", "order", "model", "durable", "differential", "reopen"}
WITH_REPORT_TEMPID_ORDER_TAGS := [?]string{"core", "transaction", "with-report", "snapshot", "overlay", "batch", "order", "tempid", "ref", "durable", "differential", "reopen"}
WITH_REPORT_FAILURE_TAGS := [?]string{"core", "transaction", "with-report", "snapshot", "overlay", "batch", "atomic", "failure", "cas", "unique", "durable", "differential", "reopen"}
WITH_REPORT_MAX_ENTITIES :: 6
WITH_REPORT_TAG_COUNT :: 4

WITH_REPORT_SCHEMA :: `[
	{:db/id 100 :db/ident :report/score :db/valueType :db.type/long :db/cardinality :db.cardinality/one}
	{:db/id 101 :db/ident :report/tag :db/valueType :db.type/long :db/cardinality :db.cardinality/many}
	{:db/id 102 :db/ident :report/link :db/valueType :db.type/ref :db/cardinality :db.cardinality/one}
	{:db/id 103 :db/ident :report/key :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/value}
]`

WITH_REPORT_TEMPID_FORM_COUNT :: 4
WITH_REPORT_TEMPID :: `"report-batch-new"`

With_Report_Case :: struct {
	entity_count:    int,
	scores:          [WITH_REPORT_MAX_ENTITIES]int,
	tags:            [WITH_REPORT_MAX_ENTITIES]u8,
	operation:       int,
	selected_entity: int,
	value:           int,
	reverse_seed:    bool,
}

With_Report_Batch_Case :: struct {
	initial_names: [MODEL_ENTITY_COUNT]int,
	initial_tags:  [MODEL_ENTITY_COUNT][MODEL_VALUE_COUNT]bool,
	command:       Batch_Command,
	mode:          int,
	reverse_seed:  bool,
}

With_Report_Failure_Case :: struct {
	base:             With_Report_Case,
	failure_mode:     int,
	failure_position: int,
	new_score:        int,
	tag:              int,
}

with_report_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := With_Report_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, WITH_REPORT_MAX_ENTITIES)),
		operation = pbt.draw(t, pbt.int_range(0, 3)),
		value = pbt.draw(t, pbt.int_range(0, 7)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	scenario.selected_entity = pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	force_empty_tags := pbt.draw(t, pbt.int_range(0, 9)) == 0
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, 7))
		if !force_empty_tags {
			scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << WITH_REPORT_TAG_COUNT) - 1)))
		}
	}
	pbt.note(t, fmt.tprintf("with-report scenario=%v", scenario))
	pbt.cover(t, scenario.operation == 0, 15, "with-report-replace-score")
	pbt.cover(t, scenario.operation == 1, 15, "with-report-toggle-tag")
	pbt.cover(t, scenario.operation == 2, 15, "with-report-retract-entity")
	pbt.cover(t, scenario.operation == 3, 15, "with-report-create-tempid")
	pbt.cover(t, scenario.tags[scenario.selected_entity - 1] == 0, 5, "with-report-selected-empty-tags")
	pbt.cover(t, scenario.reverse_seed, 35, "with-report-reverse-seed")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {return pbt.error("could not create with-report resident connection")}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate with-report durable path")}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {return pbt.error("could not create with-report durable connection")}
	defer vev.close(&durable)

	seed := with_report_seed_edn(t, scenario)
	setup := [?]string{WITH_REPORT_SCHEMA, seed}
	for tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize with-report model: resident=%s durable=%s", resident_report, durable_report))
		}
	}
	basis_before, basis_ok := vev.connection_basis_t(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {return pbt.error("could not read with-report durable coordinates")}

	resident_db, resident_db_ok := vev.db(&resident)
	if !resident_db_ok {return pbt.error("could not retain with-report resident source")}
	defer vev.close(&resident_db)
	durable_db, durable_db_ok := vev.db(&durable)
	if !durable_db_ok {return pbt.error("could not retain with-report durable source")}
	defer vev.close(&durable_db)
	tx := with_report_tx_edn(scenario)
	if result := with_report_source_check(t, &resident_db, scenario, tx, "resident"); result.status != .Pass {return result}
	if result := with_report_source_check(t, &durable_db, scenario, tx, "durable"); result.status != .Pass {return result}

	basis_after, basis_after_ok := vev.connection_basis_t(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf("with-report changed durable coordinates: basis=%d/%d count=%d/%d", basis_before, basis_after, count_before, count_after))
	}
	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen with-report durable connection")}
	reopened_db, reopened_db_ok := vev.db(&durable)
	if !reopened_db_ok {return pbt.error("could not retain reopened with-report source")}
	defer vev.close(&reopened_db)
	if result := with_report_database_check(t, &reopened_db, scenario, false, 0, "durable reopened source"); result.status != .Pass {return result}
	reopened_basis, reopened_basis_ok := vev.connection_basis_t(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf("with-report coordinates changed across reopen: basis=%d/%d count=%d/%d", basis_before, reopened_basis, count_before, reopened_count))
	}
	return pbt.pass()
}

with_report_batch_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Model_Context
	scenario := With_Report_Batch_Case{
		mode = pbt.draw(t, pbt.int_range(0, 5)),
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	initial := Model_State{ctx = &ctx}
	for entity in 0 ..< MODEL_ENTITY_COUNT {
		initial.names[entity] = pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT))
		for value in 0 ..< MODEL_VALUE_COUNT {
			initial.tags[entity][value] = pbt.draw(t, pbt.boolean())
		}
	}
	scenario.initial_names = initial.names
	scenario.initial_tags = initial.tags

	entity := pbt.draw(t, pbt.int_range(1, MODEL_ENTITY_COUNT))
	value := pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 1))
	other_value := (value + 1 + pbt.draw(t, pbt.int_range(0, MODEL_VALUE_COUNT - 2))) % MODEL_VALUE_COUNT
	scenario.command.count = 2
	switch scenario.mode {
	case 0:
		scenario.command.operations[0] = Model_Command{kind = .Add_Name, entity = entity, value_index = value}
		scenario.command.operations[1] = Model_Command{kind = .Add_Name, entity = entity, value_index = other_value}
	case 1:
		scenario.command.operations[0] = Model_Command{kind = .Add_Tag, entity = entity, value_index = value}
		scenario.command.operations[1] = Model_Command{kind = .Retract_Tag, entity = entity, value_index = value}
	case 2:
		scenario.command.operations[0] = Model_Command{kind = .Retract_Tag, entity = entity, value_index = value}
		scenario.command.operations[1] = Model_Command{kind = .Add_Tag, entity = entity, value_index = value}
	case 3:
		scenario.command.operations[0] = Model_Command{kind = .Retract_Entity, entity = entity}
		scenario.command.operations[1] = Model_Command{kind = .Add_Name, entity = entity, value_index = value}
	case 4:
		scenario.command.operations[0] = Model_Command{kind = .Add_Name, entity = entity, value_index = value}
		scenario.command.operations[1] = Model_Command{kind = .Retract_Entity, entity = entity}
	case 5:
		scenario.command.operations[0] = Model_Command{kind = .Retract_Name_Attribute, entity = entity}
		scenario.command.operations[1] = Model_Command{kind = .Add_Name, entity = entity, value_index = value}
	}
	if pbt.draw(t, pbt.boolean()) {
		scenario.command.operations[2] = transaction_model_command(t, initial)
		scenario.command.count = 3
	}

	expected := initial
	for index in 0 ..< scenario.command.count {
		expected = transaction_model_apply_command(expected, scenario.command.operations[index])
	}
	tx := transaction_batch_edn(scenario.command)
	pbt.note(t, fmt.tprintf("with-report batch mode=%d reverse=%v tx=%s", scenario.mode, scenario.reverse_seed, tx))
	for mode in 0 ..= 5 {
		pbt.cover(t, scenario.mode == mode, 10, fmt.tprintf("with-report-batch-mode-%d", mode))
	}
	pbt.cover(t, scenario.command.count == 3, 35, "with-report-batch-third-operation")
	pbt.cover(t, scenario.reverse_seed, 35, "with-report-batch-reverse-seed")

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {return pbt.error("could not create with-report batch resident connection")}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate with-report batch durable path")}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {return pbt.error("could not create with-report batch durable connection")}
	defer vev.close(&durable)

	seed := with_report_batch_seed_edn(t, scenario)
	setup := [?]string{MODEL_SCHEMA, seed}
	for setup_tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, setup_tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, setup_tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize with-report batch: resident=%s durable=%s", resident_report, durable_report))
		}
	}
	basis_before, basis_ok := vev.connection_basis_t(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {return pbt.error("could not read with-report batch durable coordinates")}

	resident_db, resident_db_ok := vev.db(&resident)
	if !resident_db_ok {return pbt.error("could not retain with-report batch resident source")}
	defer vev.close(&resident_db)
	durable_db, durable_db_ok := vev.db(&durable)
	if !durable_db_ok {return pbt.error("could not retain with-report batch durable source")}
	defer vev.close(&durable_db)
	if result := with_report_batch_source_check(t, &resident_db, initial, expected, tx, "resident"); result.status != .Pass {return result}
	if result := with_report_batch_source_check(t, &durable_db, initial, expected, tx, "durable"); result.status != .Pass {return result}

	basis_after, basis_after_ok := vev.connection_basis_t(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf("with-report batch changed durable coordinates: basis=%d/%d count=%d/%d", basis_before, basis_after, count_before, count_after))
	}
	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen with-report batch durable connection")}
	reopened_db, reopened_db_ok := vev.db(&durable)
	if !reopened_db_ok {return pbt.error("could not retain reopened with-report batch source")}
	defer vev.close(&reopened_db)
	if result := transaction_model_database_invariant(t, initial, &reopened_db, "with-report batch durable reopened source"); result.status != .Pass {return result}
	reopened_basis, reopened_basis_ok := vev.connection_basis_t(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf("with-report batch coordinates changed across reopen: basis=%d/%d count=%d/%d", basis_before, reopened_basis, count_before, reopened_count))
	}
	return pbt.pass()
}

with_report_tempid_order_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := With_Report_Case{
		entity_count = pbt.draw(t, pbt.int_range(1, WITH_REPORT_MAX_ENTITIES - 1)),
		selected_entity = 1,
		reverse_seed = pbt.draw(t, pbt.boolean()),
	}
	for entity in 0 ..< scenario.entity_count {
		scenario.scores[entity] = pbt.draw(t, pbt.int_range(0, 7))
		scenario.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << WITH_REPORT_TAG_COUNT) - 1)))
	}
	target := pbt.draw(t, pbt.int_range(1, scenario.entity_count))
	new_score := pbt.draw(t, pbt.int_range(0, 7))
	new_tag := pbt.draw(t, pbt.int_range(0, WITH_REPORT_TAG_COUNT - 1))
	canonical := [WITH_REPORT_TEMPID_FORM_COUNT]int{0, 1, 2, 3}
	permuted := canonical
	for index := WITH_REPORT_TEMPID_FORM_COUNT - 1; index > 0; index -= 1 {
		swap_index := pbt.draw(t, pbt.int_range(0, index))
		permuted[index], permuted[swap_index] = permuted[swap_index], permuted[index]
	}
	noncanonical := permuted != canonical
	pbt.cover(t, noncanonical, 75, "with-report-tempid-noncanonical-order")
	pbt.cover(t, permuted[0] < 2, 35, "with-report-tempid-payload-first")
	pbt.cover(t, permuted[0] >= 2, 35, "with-report-tempid-reference-first")
	pbt.cover(t, scenario.reverse_seed, 35, "with-report-tempid-reverse-seed")
	canonical_tx := with_report_tempid_order_edn(target, new_score, new_tag, canonical)
	permuted_tx := with_report_tempid_order_edn(target, new_score, new_tag, permuted)
	pbt.note(t, fmt.tprintf("with-report tempid target=%d canonical=%s permuted=%s", target, canonical_tx, permuted_tx))

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {return pbt.error("could not create with-report tempid resident connection")}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate with-report tempid durable path")}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {return pbt.error("could not create with-report tempid durable connection")}
	defer vev.close(&durable)

	seed := with_report_seed_edn(t, scenario)
	setup := [?]string{WITH_REPORT_SCHEMA, seed}
	for setup_tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, setup_tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, setup_tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize with-report tempid model: resident=%s durable=%s", resident_report, durable_report))
		}
	}
	basis_before, basis_ok := vev.connection_basis_t(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {return pbt.error("could not read with-report tempid durable coordinates")}
	resident_db, resident_db_ok := vev.db(&resident)
	if !resident_db_ok {return pbt.error("could not retain with-report tempid resident source")}
	defer vev.close(&resident_db)
	durable_db, durable_db_ok := vev.db(&durable)
	if !durable_db_ok {return pbt.error("could not retain with-report tempid durable source")}
	defer vev.close(&durable_db)

	resident_canonical_entity, result := with_report_tempid_source_check(t, &resident_db, scenario, canonical_tx, target, new_score, new_tag, "resident canonical")
	if result.status != .Pass {return result}
	resident_permuted_entity: u64
	resident_permuted_entity, result = with_report_tempid_source_check(t, &resident_db, scenario, permuted_tx, target, new_score, new_tag, "resident permuted")
	if result.status != .Pass {return result}
	durable_canonical_entity: u64
	durable_canonical_entity, result = with_report_tempid_source_check(t, &durable_db, scenario, canonical_tx, target, new_score, new_tag, "durable canonical")
	if result.status != .Pass {return result}
	durable_permuted_entity: u64
	durable_permuted_entity, result = with_report_tempid_source_check(t, &durable_db, scenario, permuted_tx, target, new_score, new_tag, "durable permuted")
	if result.status != .Pass {return result}
	if resident_canonical_entity != resident_permuted_entity ||
	   resident_canonical_entity != durable_canonical_entity ||
	   resident_canonical_entity != durable_permuted_entity {
		return pbt.fail(fmt.tprintf(
			"with-report tempid allocation differs: resident=%d/%d durable=%d/%d",
			resident_canonical_entity,
			resident_permuted_entity,
			durable_canonical_entity,
			durable_permuted_entity,
		))
	}

	basis_after, basis_after_ok := vev.connection_basis_t(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf("with-report tempid changed durable coordinates: basis=%d/%d count=%d/%d", basis_before, basis_after, count_before, count_after))
	}
	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen with-report tempid durable connection")}
	reopened_db, reopened_db_ok := vev.db(&durable)
	if !reopened_db_ok {return pbt.error("could not retain reopened with-report tempid source")}
	defer vev.close(&reopened_db)
	if result := with_report_database_check(t, &reopened_db, scenario, false, 0, "with-report tempid durable reopened source"); result.status != .Pass {return result}
	reopened_basis, reopened_basis_ok := vev.connection_basis_t(&durable)
	reopened_count, reopened_count_ok := vev.connection_tx_count(&durable)
	if !reopened_basis_ok || !reopened_count_ok || reopened_basis != basis_before || reopened_count != count_before {
		return pbt.fail(fmt.tprintf("with-report tempid coordinates changed across reopen: basis=%d/%d count=%d/%d", basis_before, reopened_basis, count_before, reopened_count))
	}
	return pbt.pass()
}

with_report_failure_property :: proc(t: ^pbt.T) -> pbt.Result {
	scenario := With_Report_Failure_Case{
		base = With_Report_Case{
			entity_count = pbt.draw(t, pbt.int_range(2, WITH_REPORT_MAX_ENTITIES)),
			reverse_seed = pbt.draw(t, pbt.boolean()),
		},
		failure_mode = pbt.draw(t, pbt.int_range(0, 2)),
		failure_position = pbt.draw(t, pbt.int_range(0, 2)),
		new_score = pbt.draw(t, pbt.int_range(0, 7)),
		tag = pbt.draw(t, pbt.int_range(0, WITH_REPORT_TAG_COUNT - 1)),
	}
	scenario.base.selected_entity = pbt.draw(t, pbt.int_range(1, scenario.base.entity_count))
	for entity in 0 ..< scenario.base.entity_count {
		scenario.base.scores[entity] = pbt.draw(t, pbt.int_range(0, 7))
		scenario.base.tags[entity] = u8(pbt.draw(t, pbt.int_range(0, (1 << WITH_REPORT_TAG_COUNT) - 1)))
	}
	tx := with_report_failure_edn(scenario)
	pbt.note(t, fmt.tprintf("with-report failure mode=%d position=%d tx=%s", scenario.failure_mode, scenario.failure_position, tx))
	pbt.cover(t, scenario.failure_mode == 0, 20, "with-report-failure-type")
	pbt.cover(t, scenario.failure_mode == 1, 20, "with-report-failure-cas")
	pbt.cover(t, scenario.failure_mode == 2, 20, "with-report-failure-unique")
	pbt.cover(t, scenario.failure_position == 0, 20, "with-report-failure-first")
	pbt.cover(t, scenario.failure_position == 1, 20, "with-report-failure-middle")
	pbt.cover(t, scenario.failure_position == 2, 20, "with-report-failure-last")
	pbt.cover(t, scenario.base.reverse_seed, 35, "with-report-failure-reverse-seed")
	pbt.cover(
		t,
		index_read_mask_has(scenario.base.tags[scenario.base.selected_entity - 1], scenario.tag),
		35,
		"with-report-failure-existing-tag",
	)

	resident, resident_ok := vev.create_conn(&library)
	if !resident_ok {return pbt.error("could not create with-report failure resident connection")}
	defer vev.close(&resident)
	path, path_ok := transaction_model_temp_path(t)
	if !path_ok {return pbt.error("could not allocate with-report failure durable path")}
	defer transaction_model_remove_store(path)
	durable, durable_ok := vev.connect(&library, path)
	if !durable_ok {return pbt.error("could not create with-report failure durable connection")}
	defer vev.close(&durable)

	seed := with_report_failure_seed_edn(t, scenario)
	setup := [?]string{WITH_REPORT_SCHEMA, seed}
	for setup_tx in setup {
		resident_report, resident_call_ok := vev.transact(&resident, setup_tx, t.value_allocator)
		durable_report, durable_call_ok := vev.transact(&durable, setup_tx, t.value_allocator)
		if !resident_call_ok || !strings.contains(resident_report, ":ok true") ||
		   !durable_call_ok || !strings.contains(durable_report, ":ok true") {
			return pbt.error(fmt.tprintf("could not initialize with-report failure model: resident=%s durable=%s", resident_report, durable_report))
		}
	}
	basis_before, basis_ok := vev.connection_basis_t(&durable)
	count_before, count_ok := vev.connection_tx_count(&durable)
	if !basis_ok || !count_ok {return pbt.error("could not read with-report failure durable coordinates")}
	resident_db, resident_db_ok := vev.db(&resident)
	if !resident_db_ok {return pbt.error("could not retain with-report failure resident source")}
	defer vev.close(&resident_db)
	durable_db, durable_db_ok := vev.db(&durable)
	if !durable_db_ok {return pbt.error("could not retain with-report failure durable source")}
	defer vev.close(&durable_db)
	if result := with_report_failure_source_check(t, &resident_db, scenario, tx, "resident"); result.status != .Pass {return result}
	if result := with_report_failure_source_check(t, &durable_db, scenario, tx, "durable"); result.status != .Pass {return result}

	basis_after, basis_after_ok := vev.connection_basis_t(&durable)
	count_after, count_after_ok := vev.connection_tx_count(&durable)
	if !basis_after_ok || !count_after_ok || basis_after != basis_before || count_after != count_before {
		return pbt.fail(fmt.tprintf("with-report failure changed durable coordinates: basis=%d/%d count=%d/%d", basis_before, basis_after, count_before, count_after))
	}
	vev.close(&durable)
	reopened_ok: bool
	durable, reopened_ok = vev.connect(&library, path)
	if !reopened_ok {return pbt.error("could not reopen with-report failure durable connection")}
	reopened_db, reopened_db_ok := vev.db(&durable)
	if !reopened_db_ok {return pbt.error("could not retain reopened with-report failure source")}
	defer vev.close(&reopened_db)
	if result := with_report_failure_database_check(t, &reopened_db, scenario, "durable reopened source"); result.status != .Pass {return result}
	return pbt.pass()
}

with_report_failure_edn :: proc(scenario: With_Report_Failure_Case) -> string {
	target := scenario.base.selected_entity
	valid_tag := fmt.tprintf("[:db/add %d :report/tag %d]", target, scenario.tag)
	valid_score := fmt.tprintf("[:db/add %d :report/score %d]", target, scenario.new_score)
	failure := ""
	switch scenario.failure_mode {
	case 0:
		failure = fmt.tprintf(`[:db/add %d :report/score "invalid"]`, target)
	case 1:
		stale := (scenario.base.scores[target - 1] + 1) % 8
		if stale == scenario.new_score {stale = (stale + 1) % 8}
		failure = fmt.tprintf("[:db.fn/cas %d :report/score %d %d]", target, stale, scenario.new_score)
	case 2:
		other := target % scenario.base.entity_count + 1
		failure = fmt.tprintf(`[:db/add %d :report/key "key-%d"]`, other, target)
	}
	forms := [3]string{valid_tag, valid_score, failure}
	forms[scenario.failure_position], forms[2] = forms[2], forms[scenario.failure_position]
	return fmt.tprintf("[%s %s %s]", forms[0], forms[1], forms[2])
}

with_report_failure_seed_edn :: proc(t: ^pbt.T, scenario: With_Report_Failure_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.base.entity_count {
		entity := offset + 1
		if scenario.base.reverse_seed {entity = scenario.base.entity_count - offset}
		append(&parts, fmt.tprintf(`[:db/add %d :report/key "key-%d"]`, entity, entity))
		append(&parts, fmt.tprintf("[:db/add %d :report/score %d]", entity, scenario.base.scores[entity - 1]))
		for tag in 0 ..< WITH_REPORT_TAG_COUNT {
			if index_read_mask_has(scenario.base.tags[entity - 1], tag) {
				append(&parts, fmt.tprintf("[:db/add %d :report/tag %d]", entity, tag))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

with_report_failure_source_check :: proc(
	t: ^pbt.T,
	source: ^vev.DB,
	scenario: With_Report_Failure_Case,
	tx, backend: string,
) -> pbt.Result {
	source_basis, source_basis_ok := vev.basis_t(source)
	if !source_basis_ok {return pbt.error(fmt.tprintf("could not read %s failure source basis", backend))}
	report, report_ok := vev.with_report(source, tx)
	if !report_ok {return pbt.error(fmt.tprintf("%s with-report failure returned no report", backend))}
	report_text, report_text_ok := vev.tx_report_edn(&report, t.value_allocator)
	if !report_text_ok || !strings.contains(report_text, ":ok false") {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s invalid batch status disagreed for tx=%s: %s", backend, tx, report_text))
	}
	before, before_ok := vev.tx_report_db_before(&report)
	after, after_ok := vev.tx_report_db_after(&report)
	if !before_ok || !after_ok {
		if before_ok {vev.close(&before)}
		if after_ok {vev.close(&after)}
		vev.close(&report)
		return pbt.error(fmt.tprintf("%s failure report omitted before/after databases", backend))
	}
	vev.close(&report)
	defer vev.close(&before)
	defer vev.close(&after)
	before_basis, before_basis_ok := vev.basis_t(&before)
	after_basis, after_basis_ok := vev.basis_t(&after)
	if !before_basis_ok || !after_basis_ok || before_basis != source_basis || after_basis != source_basis {
		return pbt.fail(fmt.tprintf("%s failure report bases: source=%d before=%d after=%d", backend, source_basis, before_basis, after_basis))
	}
	if result := with_report_failure_database_check(t, source, scenario, fmt.tprintf("%s source", backend)); result.status != .Pass {return result}
	if result := with_report_failure_database_check(t, &before, scenario, fmt.tprintf("%s before", backend)); result.status != .Pass {return result}
	return with_report_failure_database_check(t, &after, scenario, fmt.tprintf("%s failed after", backend))
}

with_report_failure_database_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: With_Report_Failure_Case,
	backend: string,
) -> pbt.Result {
	if result := with_report_database_check(t, database, scenario.base, false, 0, backend); result.status != .Pass {return result}
	query, query_ok := vev.query(database, `[:find ?e ?key :where [?e :report/key ?key]]`)
	if !query_ok {return pbt.error(fmt.tprintf("%s key query failed", backend))}
	defer vev.close(&query)
	relation, relation_ok := vev.value(&query)
	if !relation_ok || vev.item_count(relation) != scenario.base.entity_count {
		return pbt.fail(fmt.tprintf("%s key count disagreed", backend))
	}
	for index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, index)
		entity_value, entity_ok := vev.item(row, 0)
		key_value, key_ok := vev.item(row, 1)
		entity, entity_value_ok := vev.as_int(entity_value)
		key, key_value_ok := vev.as_string(key_value, t.value_allocator)
		if !row_ok || !entity_ok || !key_ok || !entity_value_ok || !key_value_ok ||
		   entity < 1 || entity > i64(scenario.base.entity_count) || key != fmt.tprintf("key-%d", entity) {
			return pbt.fail(fmt.tprintf("%s returned unexpected key row", backend))
		}
	}
	return pbt.pass()
}

with_report_tempid_order_edn :: proc(target, score, tag: int, order: [WITH_REPORT_TEMPID_FORM_COUNT]int) -> string {
	forms := [WITH_REPORT_TEMPID_FORM_COUNT]string{
		fmt.tprintf(`[:db/add %s :report/score %d]`, WITH_REPORT_TEMPID, score),
		fmt.tprintf(`[:db/add %s :report/tag %d]`, WITH_REPORT_TEMPID, tag),
		fmt.tprintf(`[:db/add %s :report/link %d]`, WITH_REPORT_TEMPID, target),
		fmt.tprintf(`[:db/add %d :report/link %s]`, target, WITH_REPORT_TEMPID),
	}
	return fmt.tprintf(
		"[%s %s %s %s]",
		forms[order[0]],
		forms[order[1]],
		forms[order[2]],
		forms[order[3]],
	)
}

with_report_tempid_source_check :: proc(
	t: ^pbt.T,
	source: ^vev.DB,
	scenario: With_Report_Case,
	tx: string,
	target, score, tag: int,
	backend: string,
) -> (entity: u64, result: pbt.Result) {
	source_basis, source_basis_ok := vev.basis_t(source)
	if !source_basis_ok {return 0, pbt.error(fmt.tprintf("could not read %s source basis", backend))}
	report, report_ok := vev.with_report(source, tx)
	if !report_ok {return 0, pbt.error(fmt.tprintf("%s with-report tempid returned no report", backend))}
	report_text, report_text_ok := vev.tx_report_edn(&report, t.value_allocator)
	if !report_text_ok || !strings.contains(report_text, ":ok true") {
		vev.close(&report)
		return 0, pbt.fail(fmt.tprintf("%s with-report tempid failed for tx=%s: %s", backend, tx, report_text))
	}
	entity_ok: bool
	entity, entity_ok = vev.tx_report_resolve_tempid(&report, WITH_REPORT_TEMPID)
	if !entity_ok {
		vev.close(&report)
		return 0, pbt.fail(fmt.tprintf("%s did not resolve with-report batch tempid", backend))
	}
	before, before_ok := vev.tx_report_db_before(&report)
	after, after_ok := vev.tx_report_db_after(&report)
	if !before_ok || !after_ok {
		if before_ok {vev.close(&before)}
		if after_ok {vev.close(&after)}
		vev.close(&report)
		return 0, pbt.error(fmt.tprintf("%s with-report tempid omitted before/after databases", backend))
	}
	vev.close(&report)
	defer vev.close(&before)
	defer vev.close(&after)
	before_basis, before_basis_ok := vev.basis_t(&before)
	after_basis, after_basis_ok := vev.basis_t(&after)
	if !before_basis_ok || !after_basis_ok || before_basis != source_basis || after_basis != source_basis + 1 {
		return 0, pbt.fail(fmt.tprintf("%s with-report tempid bases: source=%d before=%d after=%d", backend, source_basis, before_basis, after_basis))
	}
	if invariant := with_report_database_check(t, source, scenario, false, 0, fmt.tprintf("%s source", backend)); invariant.status != .Pass {return 0, invariant}
	if invariant := with_report_database_check(t, &before, scenario, false, 0, fmt.tprintf("%s before", backend)); invariant.status != .Pass {return 0, invariant}
	result = with_report_tempid_after_check(t, &after, scenario, entity, target, score, tag, backend)
	return entity, result
}

with_report_tempid_after_check :: proc(
	t: ^pbt.T,
	database: ^vev.DB,
	scenario: With_Report_Case,
	new_entity: u64,
	target, score, tag: int,
	backend: string,
) -> pbt.Result {
	for entity in 1 ..= scenario.entity_count {
		entity_value, entity_ok := vev.entity(database, u64(entity))
		if !entity_ok {return pbt.fail(fmt.tprintf("%s omitted source entity %d", backend, entity))}
		if invariant := entity_view_get_int_check(t, &entity_value, ":report/score", scenario.scores[entity - 1], true, backend); invariant.status != .Pass {vev.close(&entity_value); return invariant}
		if invariant := entity_view_values_check(t, &entity_value, ":report/tag", scenario.tags[entity - 1], false, backend); invariant.status != .Pass {vev.close(&entity_value); return invariant}
		expected_link := int(new_entity)
		if entity != target {expected_link = 0}
		if invariant := entity_view_get_entity_check(t, &entity_value, ":report/link", expected_link, entity == target, backend); invariant.status != .Pass {vev.close(&entity_value); return invariant}
		vev.close(&entity_value)
	}
	created, created_ok := vev.entity(database, new_entity)
	if !created_ok {return pbt.fail(fmt.tprintf("%s omitted tempid entity %d", backend, new_entity))}
	defer vev.close(&created)
	if invariant := entity_view_get_int_check(t, &created, ":report/score", score, true, backend); invariant.status != .Pass {return invariant}
	if invariant := entity_view_values_check(t, &created, ":report/tag", u8(1) << u8(tag), false, backend); invariant.status != .Pass {return invariant}
	return entity_view_get_entity_check(t, &created, ":report/link", target, true, backend)
}

with_report_batch_seed_edn :: proc(t: ^pbt.T, scenario: With_Report_Batch_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< MODEL_ENTITY_COUNT {
		entity := offset + 1
		if scenario.reverse_seed {entity = MODEL_ENTITY_COUNT - offset}
		name := scenario.initial_names[entity - 1]
		if name != 0 {
			append(&parts, fmt.tprintf(`[:db/add %d :item/name "%s"]`, entity, MODEL_NAMES[name - 1]))
		}
		for value in 0 ..< MODEL_VALUE_COUNT {
			if scenario.initial_tags[entity - 1][value] {
				append(&parts, fmt.tprintf(`[:db/add %d :item/tags "%s"]`, entity, MODEL_TAGS[value]))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

with_report_batch_source_check :: proc(
	t: ^pbt.T,
	source: ^vev.DB,
	initial, expected: Model_State,
	tx, backend: string,
) -> pbt.Result {
	source_basis, source_basis_ok := vev.basis_t(source)
	if !source_basis_ok {return pbt.error(fmt.tprintf("could not read %s with-report batch source basis", backend))}
	report, report_ok := vev.with_report(source, tx)
	if !report_ok {return pbt.error(fmt.tprintf("%s with-report batch returned no report", backend))}
	report_text, report_text_ok := vev.tx_report_edn(&report, t.value_allocator)
	if !report_text_ok || !strings.contains(report_text, ":ok true") {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report batch failed for tx=%s: %s", backend, tx, report_text))
	}
	report_value, report_value_ok := vev.tx_report_value(&report)
	if !report_value_ok || vev.kind(report_value) != .Map {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report batch value was not a map", backend))
	}
	tx_value, tx_ok := vev.get(report_value, ":tx")
	tx_entity, tx_entity_ok := vev.as_entity(tx_value)
	tx_data, tx_data_ok := vev.get(report_value, ":tx-data")
	tempids, tempids_ok := vev.get(report_value, ":tempids")
	if !tx_ok || !tx_entity_ok || tx_entity != vev.t_to_tx(source_basis + 1) ||
	   !tx_data_ok || vev.kind(tx_data) != .Vector || vev.item_count(tx_data) < 1 ||
	   !tempids_ok || vev.kind(tempids) != .Map {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report batch metadata disagreed at basis %d", backend, source_basis))
	}
	before, before_ok := vev.tx_report_db_before(&report)
	after, after_ok := vev.tx_report_db_after(&report)
	if !before_ok || !after_ok {
		if before_ok {vev.close(&before)}
		if after_ok {vev.close(&after)}
		vev.close(&report)
		return pbt.error(fmt.tprintf("%s with-report batch omitted before/after databases", backend))
	}
	vev.close(&report)
	defer vev.close(&before)
	defer vev.close(&after)
	before_basis, before_basis_ok := vev.basis_t(&before)
	after_basis, after_basis_ok := vev.basis_t(&after)
	if !before_basis_ok || !after_basis_ok || before_basis != source_basis || after_basis != source_basis + 1 {
		return pbt.fail(fmt.tprintf("%s with-report batch bases: source=%d before=%d after=%d", backend, source_basis, before_basis, after_basis))
	}
	if result := transaction_model_database_invariant(t, initial, source, fmt.tprintf("%s with-report batch source", backend)); result.status != .Pass {return result}
	if result := transaction_model_database_invariant(t, initial, &before, fmt.tprintf("%s with-report batch before", backend)); result.status != .Pass {return result}
	return transaction_model_database_invariant(t, expected, &after, fmt.tprintf("%s with-report batch after", backend))
}

with_report_seed_edn :: proc(t: ^pbt.T, scenario: With_Report_Case) -> string {
	parts := make([dynamic]string, t.value_allocator)
	append(&parts, "[")
	for offset in 0 ..< scenario.entity_count {
		entity := offset + 1
		if scenario.reverse_seed {entity = scenario.entity_count - offset}
		append(&parts, fmt.tprintf("[:db/add %d :report/score %d]", entity, scenario.scores[entity - 1]))
		for tag in 0 ..< WITH_REPORT_TAG_COUNT {
			if index_read_mask_has(scenario.tags[entity - 1], tag) {
				append(&parts, fmt.tprintf("[:db/add %d :report/tag %d]", entity, tag))
			}
		}
	}
	append(&parts, "]")
	return strings.concatenate(parts[:])
}

with_report_tx_edn :: proc(scenario: With_Report_Case) -> string {
	switch scenario.operation {
	case 0:
		return fmt.tprintf("[[:db/add %d :report/score %d]]", scenario.selected_entity, scenario.value)
	case 1:
		tag := scenario.value % WITH_REPORT_TAG_COUNT
		op := ":db/add"
		if index_read_mask_has(scenario.tags[scenario.selected_entity - 1], tag) {op = ":db/retract"}
		return fmt.tprintf("[[%s %d :report/tag %d]]", op, scenario.selected_entity, tag)
	case 2:
		return fmt.tprintf("[[:db/retractEntity %d]]", scenario.selected_entity)
	case 3:
		body := fmt.tprintf(":db/id \"report-new\" :report/score %d :report/tag %d", scenario.value, scenario.value % WITH_REPORT_TAG_COUNT)
		return strings.concatenate([]string{"[{", body, "}]"})
	}
	return "[]"
}

with_report_source_check :: proc(t: ^pbt.T, source: ^vev.DB, scenario: With_Report_Case, tx, backend: string) -> pbt.Result {
	source_basis, source_basis_ok := vev.basis_t(source)
	if !source_basis_ok {return pbt.error(fmt.tprintf("could not read %s source basis", backend))}
	report, report_ok := vev.with_report(source, tx)
	if !report_ok {return pbt.error(fmt.tprintf("%s with-report returned no report", backend))}
	report_text, report_text_ok := vev.tx_report_edn(&report, t.value_allocator)
	if !report_text_ok || !strings.contains(report_text, ":ok true") {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report failed for tx=%s: %s", backend, tx, report_text))
	}
	report_value, report_value_ok := vev.tx_report_value(&report)
	if !report_value_ok || vev.kind(report_value) != .Map {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report value was not a map", backend))
	}
	tx_value, tx_ok := vev.get(report_value, ":tx")
	tx_entity, tx_entity_ok := vev.as_entity(tx_value)
	tx_data, tx_data_ok := vev.get(report_value, ":tx-data")
	tempids, tempids_ok := vev.get(report_value, ":tempids")
	if !tx_ok || !tx_entity_ok || tx_entity != vev.t_to_tx(source_basis + 1) ||
	   !tx_data_ok || vev.kind(tx_data) != .Vector || vev.item_count(tx_data) < 1 ||
	   !tempids_ok || vev.kind(tempids) != .Map {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s with-report metadata disagreed at basis %d", backend, source_basis))
	}
	tempid: u64
	tempid_ok := false
	if scenario.operation == 3 {
		tempid, tempid_ok = vev.tx_report_resolve_tempid(&report, `"report-new"`)
		if !tempid_ok {vev.close(&report); return pbt.fail(fmt.tprintf("%s did not resolve with-report tempid", backend))}
	} else if _, unexpected_tempid := vev.tx_report_resolve_tempid(&report, `"report-new"`); unexpected_tempid {
		vev.close(&report)
		return pbt.fail(fmt.tprintf("%s unexpectedly resolved absent with-report tempid", backend))
	}
	before, before_ok := vev.tx_report_db_before(&report)
	after, after_ok := vev.tx_report_db_after(&report)
	if !before_ok || !after_ok {
		if before_ok {vev.close(&before)}
		if after_ok {vev.close(&after)}
		vev.close(&report)
		return pbt.error(fmt.tprintf("%s with-report omitted before/after databases", backend))
	}
	// Returned DB handles retain their snapshots independently of the report.
	vev.close(&report)
	defer vev.close(&before)
	defer vev.close(&after)
	before_basis, before_basis_ok := vev.basis_t(&before)
	after_basis, after_basis_ok := vev.basis_t(&after)
	if !before_basis_ok || !after_basis_ok || before_basis != source_basis || after_basis != source_basis + 1 {
		return pbt.fail(fmt.tprintf("%s with-report bases: source=%d before=%d after=%d", backend, source_basis, before_basis, after_basis))
	}
	if result := with_report_database_check(t, source, scenario, false, 0, fmt.tprintf("%s source", backend)); result.status != .Pass {return result}
	if result := with_report_database_check(t, &before, scenario, false, 0, fmt.tprintf("%s before", backend)); result.status != .Pass {return result}
	return with_report_database_check(t, &after, scenario, true, tempid, fmt.tprintf("%s after", backend))
}

with_report_database_check :: proc(t: ^pbt.T, database: ^vev.DB, scenario: With_Report_Case, after: bool, tempid: u64, backend: string) -> pbt.Result {
	query, query_ok := vev.query(database, "[:find ?e ?score :where [?e :report/score ?score]]")
	if !query_ok {return pbt.error(fmt.tprintf("%s score query failed", backend))}
	defer vev.close(&query)
	relation, relation_ok := vev.value(&query)
	expected_count := scenario.entity_count
	if after && scenario.operation == 2 {expected_count -= 1}
	if after && scenario.operation == 3 {expected_count += 1}
	if !relation_ok || vev.item_count(relation) != expected_count {
		actual, _ := vev.edn(relation, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s scores count: expected=%d actual=%s", backend, expected_count, actual))
	}
	seen: [WITH_REPORT_MAX_ENTITIES]bool
	seen_tempid := false
	for index in 0 ..< vev.item_count(relation) {
		row, row_ok := vev.item(relation, index)
		entity_value, entity_ok := vev.item(row, 0)
		score_value, score_ok := vev.item(row, 1)
		entity, entity_value_ok := vev.as_int(entity_value)
		score, score_value_ok := vev.as_int(score_value)
		if !row_ok || !entity_ok || !score_ok || !entity_value_ok || !score_value_ok {
			return pbt.fail(fmt.tprintf("%s returned malformed score row", backend))
		}
		if after && scenario.operation == 3 && u64(entity) == tempid {
			if seen_tempid || score != i64(scenario.value) {return pbt.fail(fmt.tprintf("%s returned wrong tempid score", backend))}
			seen_tempid = true
			continue
		}
		if entity < 1 || entity > i64(scenario.entity_count) || seen[entity - 1] ||
		   (after && scenario.operation == 2 && entity == i64(scenario.selected_entity)) {
			return pbt.fail(fmt.tprintf("%s returned unexpected entity %d", backend, entity))
		}
		expected_score := scenario.scores[entity - 1]
		if after && scenario.operation == 0 && entity == i64(scenario.selected_entity) {expected_score = scenario.value}
		if score != i64(expected_score) {return pbt.fail(fmt.tprintf("%s entity %d score: expected=%d actual=%d", backend, entity, expected_score, score))}
		seen[entity - 1] = true
	}
	if after && scenario.operation == 3 && !seen_tempid {return pbt.fail(fmt.tprintf("%s omitted tempid entity", backend))}
	for entity in 1 ..= scenario.entity_count {
		expected_present := !(after && scenario.operation == 2 && entity == scenario.selected_entity)
		if seen[entity - 1] != expected_present {return pbt.fail(fmt.tprintf("%s presence disagreed for entity %d", backend, entity))}
		if !expected_present {continue}
		entity_view, entity_view_ok := vev.entity(database, u64(entity))
		if !entity_view_ok {return pbt.fail(fmt.tprintf("%s did not resolve entity %d", backend, entity))}
		tags, tags_ok := vev.entity_values(&entity_view, ":report/tag")
		vev.close(&entity_view)
		if !tags_ok {return pbt.error(fmt.tprintf("%s could not read tags for entity %d", backend, entity))}
		expected_tags := scenario.tags[entity - 1]
		if after && scenario.operation == 1 && entity == scenario.selected_entity {
			expected_tags = expected_tags ~ (u8(1) << u8(scenario.value % WITH_REPORT_TAG_COUNT))
		}
		if result := with_report_tags_check(t, &tags, expected_tags, fmt.tprintf("%s entity %d", backend, entity)); result.status != .Pass {
			vev.close(&tags)
			return result
		}
		vev.close(&tags)
	}
	return pbt.pass()
}

with_report_tags_check :: proc(t: ^pbt.T, data: ^vev.Data, expected: u8, backend: string) -> pbt.Result {
	value, value_ok := vev.value(data)
	if !value_ok || vev.kind(value) != .Vector || vev.item_count(value) != entity_view_mask_count(expected) {
		actual, _ := vev.edn(value, t.value_allocator)
		return pbt.fail(fmt.tprintf("%s tags shape: expected=%02x actual=%s", backend, expected, actual))
	}
	seen: u8
	for index in 0 ..< vev.item_count(value) {
		item, item_ok := vev.item(value, index)
		tag, tag_ok := vev.as_int(item)
		if !item_ok || !tag_ok || tag < 0 || tag >= WITH_REPORT_TAG_COUNT {return pbt.fail(fmt.tprintf("%s returned invalid tag", backend))}
		seen |= u8(1) << u8(tag)
	}
	if seen != expected {return pbt.fail(fmt.tprintf("%s tags: expected=%02x actual=%02x", backend, expected, seen))}
	return pbt.pass()
}
