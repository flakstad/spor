// Copyright (c) Andreas Flakstad and Vev contributors
// SPDX-License-Identifier: EPL-2.0

package main

import "core:fmt"
import "core:os"
import "core:strings"
import vev "../vev"

main :: proc() {
	library_path := vev.library_filename()
	if len(os.args) > 1 {
		library_path = os.args[1]
	}

	library, loaded := vev.load(library_path)
	if !loaded {
		fmt.eprintln("could not load VevDB:", library_path)
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
}
