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
