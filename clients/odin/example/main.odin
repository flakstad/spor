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
		`[:find ?name :where [?e :user/name ?name]]`,
	)
	if !queried {
		fmt.eprintln("query failed")
		os.exit(1)
	}
	defer delete(query_result)

	if !strings.contains(tx_result, ":ok true") ||
	   !strings.contains(query_result, `"Ada"`) {
		fmt.eprintln("unexpected VevDB result:", tx_result, query_result)
		os.exit(1)
	}

	fmt.println(query_result)

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

	rows, durable_queried := vev.query_rows(
		&durable,
		`[:find ?name :where [?e :user/name ?name]]`,
	)
	if !durable_queried {
		error := vev.rows_error(&rows)
		fmt.eprintln("durable query failed:", error)
		delete(error)
		vev.close(&rows)
		os.exit(1)
	}
	defer vev.close(&rows)
	if vev.row_count(&rows) < 1 || vev.value_count(&rows, 0) != 1 {
		fmt.eprintln("unexpected durable query shape")
		os.exit(1)
	}
	name, name_ok := vev.value_edn(&rows, 0, 0)
	if !name_ok || name != `"Grace"` {
		fmt.eprintln("unexpected durable query value:", name)
		if name_ok {
			delete(name)
		}
		os.exit(1)
	}
	defer delete(name)
	fmt.println(name)
}
