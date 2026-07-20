// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:os"
import "core:strings"
import vev "../vev"

main :: proc() {
	package_root := "."
	if len(os.args) > 1 {
		package_root = os.args[1]
	}

	library, loaded := vev.load_bundled(package_root)
	if !loaded {
		fmt.eprintln("could not load bundled VevDB from:", package_root)
		os.exit(1)
	}
	defer vev.unload(&library)

	connection, opened := vev.open_memory(&library)
	if !opened {
		fmt.eprintln("could not open an in-memory VevDB connection")
		os.exit(1)
	}
	defer vev.close(&connection)

	tx_result, transacted := vev.transact(
		&connection,
		`[{:db/id 1 :user/name "Ada"}]`,
	)
	if !transacted {
		fmt.eprintln("transaction failed")
		os.exit(1)
	}
	defer delete(tx_result)

	query_result, queried := vev.query(
		&connection,
		`[:find ?name . :where [?e :user/name ?name]]`,
	)
	if !queried {
		fmt.eprintln("query failed")
		os.exit(1)
	}
	defer vev.close(&query_result)

	query_value, value_ok := vev.value(&query_result)
	name, name_ok := vev.as_string(query_value)
	if !value_ok || !name_ok ||
	   !strings.contains(tx_result, ":ok true") ||
	   name != "Ada" {
		fmt.eprintln("unexpected VevDB result:", tx_result, name)
		os.exit(1)
	}
	defer delete(name)

	fmt.println(name)

	tx_query, tx_queried := vev.query(
		&connection,
		`[:find ?tx . :where [1 :user/name "Ada" ?tx]]`,
	)
	if !tx_queried {
		fmt.eprintln("transaction query failed")
		os.exit(1)
	}
	defer vev.close(&tx_query)
	tx_value, tx_value_ok := vev.value(&tx_query)
	tx, tx_ok := vev.as_int(tx_value)
	if !tx_value_ok || !tx_ok {
		fmt.eprintln("transaction query did not return a transaction id")
		os.exit(1)
	}

	update_result, updated := vev.transact(
		&connection,
		`[[:db/retract 1 :user/name "Ada"]
		  [:db/add 1 :user/name "Grace"]]`,
	)
	if !updated {
		fmt.eprintln("update transaction failed")
		os.exit(1)
	}
	defer delete(update_result)

	current_db, db_ok := vev.db(&connection)
	if !db_ok {
		fmt.eprintln("could not retain an immutable DB value")
		os.exit(1)
	}
	defer vev.close(&current_db)

	earlier_db, as_of_ok := vev.as_of(&current_db, u64(tx))
	recent_db, since_ok := vev.since(&current_db, u64(tx))
	history_db, history_ok := vev.history(&current_db)
	if !as_of_ok || !since_ok || !history_ok {
		fmt.eprintln("could not create historical DB values")
		os.exit(1)
	}
	defer vev.close(&earlier_db)
	defer vev.close(&recent_db)
	defer vev.close(&history_db)

	basis, basis_ok := vev.basis_t(&current_db)
	next, next_ok := vev.next_t(&current_db)
	earlier_t, earlier_t_ok := vev.as_of_t(&earlier_db)
	recent_t, recent_t_ok := vev.since_t(&recent_db)
	if !basis_ok || !next_ok || !earlier_t_ok || !recent_t_ok ||
	   next != basis+1 || earlier_t+1 != basis ||
	   recent_t != earlier_t || !vev.is_history(&history_db) {
		fmt.eprintln("unexpected historical DB metadata")
		os.exit(1)
	}

	earlier_result, earlier_ok := vev.query(
		&earlier_db,
		`[:find ?name . :where [1 :user/name ?name]]`,
	)
	recent_result, recent_ok := vev.query(
		&recent_db,
		`[:find ?name . :where [1 :user/name ?name]]`,
	)
	history_result, history_query_ok := vev.query(
		&history_db,
		`[:find ?name ?tx ?added :where [1 :user/name ?name ?tx ?added]]`,
	)
	if !earlier_ok || !recent_ok || !history_query_ok {
		fmt.eprintln("historical DB query failed")
		os.exit(1)
	}
	defer vev.close(&earlier_result)
	defer vev.close(&recent_result)
	defer vev.close(&history_result)

	earlier_value, earlier_value_ok := vev.value(&earlier_result)
	recent_value, recent_value_ok := vev.value(&recent_result)
	history_value, history_value_ok := vev.value(&history_result)
	earlier_name, earlier_name_ok := vev.as_string(earlier_value)
	recent_name, recent_name_ok := vev.as_string(recent_value)
	if !earlier_value_ok || !recent_value_ok || !history_value_ok ||
	   !earlier_name_ok || !recent_name_ok ||
	   earlier_name != "Ada" || recent_name != "Grace" ||
	   vev.kind(history_value) != .Set || vev.item_count(history_value) != 3 {
		earlier_edn, _ := vev.edn(&earlier_result)
		recent_edn, _ := vev.edn(&recent_result)
		history_edn, _ := vev.edn(&history_result)
		fmt.eprintln("unexpected historical DB results:", earlier_edn, recent_edn, history_edn)
		delete(earlier_edn)
		delete(recent_edn)
		delete(history_edn)
		os.exit(1)
	}
	defer delete(earlier_name)
	defer delete(recent_name)

	log_value, log_ok := vev.log(&connection)
	if !log_ok {
		fmt.eprintln("could not retain transaction log")
		os.exit(1)
	}
	defer vev.close(&log_value)
	transactions, tx_range_ok := vev.tx_range(&log_value)
	if !tx_range_ok {
		fmt.eprintln("transaction range failed")
		os.exit(1)
	}
	defer vev.close(&transactions)
	transactions_value, transactions_value_ok := vev.value(&transactions)
	if !transactions_value_ok ||
	   vev.kind(transactions_value) != .Vector ||
	   vev.item_count(transactions_value) != 2 {
		fmt.eprintln("unexpected transaction range")
		os.exit(1)
	}

	database_path := "example.vev"
	if len(os.args) > 2 {
		database_path = os.args[2]
	}
	durable, connected := vev.connect(&library, database_path)
	if !connected {
		error := vev.connection_error(&durable)
		fmt.eprintln("could not open durable VevDB:", error)
		delete(error)
		vev.close(&durable)
		os.exit(1)
	}
	defer vev.close(&durable)

	durable_tx, durable_transacted := vev.transact(
		&durable,
		`[{:db/id 2 :user/name "Grace"}]`,
	)
	if !durable_transacted {
		fmt.eprintln("durable transaction failed:", durable_tx)
		delete(durable_tx)
		os.exit(1)
	}
	defer delete(durable_tx)

	result, durable_queried := vev.query(
		&durable,
		`[:find ?name . :where [?e :user/name ?name]]`,
	)
	if !durable_queried {
		fmt.eprintln("durable query failed")
		os.exit(1)
	}
	defer vev.close(&result)
	durable_value, durable_value_ok := vev.value(&result)
	durable_name, durable_name_ok := vev.as_string(durable_value)
	if !durable_value_ok || !durable_name_ok || durable_name != "Grace" {
		fmt.eprintln("unexpected durable query value:", durable_name)
		os.exit(1)
	}
	defer delete(durable_name)
	fmt.println(durable_name)
}
