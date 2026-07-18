use vevdb::*;

fn remove_sqlite_files(path: &str) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{path}-wal"));
    let _ = std::fs::remove_file(format!("{path}-shm"));
}

fn main() -> Result<(), String> {
    let version = version();
    println!("version: {version}");

    let conn = Conn::open_memory()?;
    let tx = conn.transact_report(
        r#"[{:db/id 1 :user/name "Ada" :user/email "ada@example.com"}
            {:db/id 2 :user/name "Grace" :user/email "grace@example.com"}]"#,
    )?;
    println!("tx: {}", tx.edn());
    let tx_value = tx.value();
    let tx_data = tx_value.map_get(":tx-data").and_then(|value| match value {
        Value::Vector(items) => Some(items),
        _ => None,
    });
    let has_tx_instant = tx_data.is_some_and(|items| {
        items.iter().any(|datom| {
            datom.map_get(":a") == Some(&Value::Keyword(":db/txInstant".to_string()))
                && matches!(datom.map_get(":v"), Some(Value::Instant(_)))
        })
    });
    if tx_value.map_get(":ok") != Some(&Value::Bool(true))
        || tx_data.map_or(0, Vec::len) != 5
        || !has_tx_instant
    {
        return Err("unexpected typed transaction report".to_string());
    }

    let collection_text = conn.query_text_with_inputs(
        r#"[:find ?name
           :in $ [?email ...]
           :where [?e :user/email ?email]
                  [?e :user/name ?name]]"#,
        r#"[["ada@example.com" "grace@example.com"]]"#,
    );
    println!("input-collection: {collection_text}");
    if !collection_text.contains("\"Ada\"") || !collection_text.contains("\"Grace\"") {
        return Err("unexpected collection query output".to_string());
    }

    let mut one_shot_rows = conn.q(r#"[:find ?name :where [?e :user/name ?name]]"#, "[]")?;
    one_shot_rows.sort_by(|left, right| format!("{left:?}").cmp(&format!("{right:?}")));
    if one_shot_rows
        != vec![
            vec![Value::String("Ada".to_string())],
            vec![Value::String("Grace".to_string())],
        ]
    {
        return Err("unexpected one-shot connection query rows".to_string());
    }

    conn.transact(
        r#"[[:db/add 90 :db/ident :user/email]
            [:db/add 90 :db/unique :db.unique/identity]]"#,
    );

    conn.transact(
        r#"[[:db/add 100 :db/ident :user/friend]
            [:db/add 100 :db/valueType :db.type/ref]
            [:db/add 1 :user/friend 2]]"#,
    );

    let email_query = conn.prepare(
        r#"[:find ?e ?email
           :in $ ?needle
           :where [?e :user/email ?email]
                  [(= ?email ?needle)]]"#,
    )?;
    let prepared_ast = email_query.edn();
    if !prepared_ast.contains(":clauses") || !prepared_ast.contains(":input-specs") {
        return Err("prepared query AST did not expose parser keys".to_string());
    }
    let clause_ast = conn.parse_clause_edn("[?e :user/email ?email]");
    if !clause_ast.contains(":clauses") || !clause_ast.contains(":user/email") {
        return Err("parse-clause AST did not expose parser keys".to_string());
    }
    let mut stmt = email_query.statement()?;
    let rows = stmt
        .bind_string("grace@example.com")?
        .query_conn(&conn)?
        .rows();
    println!("statement rows: {rows:?}");
    if rows
        != vec![vec![
            Value::Entity(2),
            Value::String("grace@example.com".to_string()),
        ]]
    {
        return Err("unexpected statement rows".to_string());
    }

    let collection_query = conn.prepare(
        r#"[:find ?name
           :in $ [?email ...]
           :where [?e :user/email ?email]
                  [?e :user/name ?name]]"#,
    )?;
    let mut collection_stmt = collection_query.statement()?;
    let rows = collection_stmt
        .bind_string_collection(&["ada@example.com", "grace@example.com"])?
        .query_conn(&conn)?
        .rows();
    println!("statement collection rows: {rows:?}");
    let mut names: Vec<String> = rows
        .iter()
        .filter_map(|row| match row.first() {
            Some(Value::String(name)) => Some(name.clone()),
            _ => None,
        })
        .collect();
    names.sort();
    if names != vec!["Ada".to_string(), "Grace".to_string()] {
        return Err("unexpected collection statement rows".to_string());
    }

    let all_email_texts = conn.prepare(r#"[:find ?email :where [?e :user/email ?email]]"#)?;
    let column_db = conn.db()?;
    let columns = column_db
        .query_columns(&all_email_texts, "[]")?
        .ok_or_else(|| "expected string column batch".to_string())?;
    let mut column_rows = columns.rows();
    column_rows.sort_by(|left, right| format!("{left:?}").cmp(&format!("{right:?}")));
    println!("column batch rows: {column_rows:?}");
    if columns.kinds != vec![VEV_COLUMN_STRING]
        || column_rows
            != vec![
                vec![Value::String("ada@example.com".to_string())],
                vec![Value::String("grace@example.com".to_string())],
            ]
    {
        return Err("unexpected column batch rows".to_string());
    }
    let all_email_stmt = all_email_texts.statement()?;
    let live_columns = all_email_stmt
        .columns_conn(&conn)?
        .ok_or_else(|| "expected live statement column batch".to_string())?;
    let mut live_rows = live_columns.rows();
    live_rows.sort_by(|left, right| format!("{left:?}").cmp(&format!("{right:?}")));
    if live_columns.kinds != vec![VEV_COLUMN_STRING] || live_rows != column_rows {
        return Err("unexpected live statement column batch rows".to_string());
    }
    let snapshot_columns = all_email_stmt
        .columns_db(&column_db)?
        .ok_or_else(|| "expected snapshot statement column batch".to_string())?;
    let mut snapshot_column_rows = snapshot_columns.rows();
    snapshot_column_rows.sort_by(|left, right| format!("{left:?}").cmp(&format!("{right:?}")));
    if snapshot_columns.kinds != vec![VEV_COLUMN_STRING] || snapshot_column_rows != column_rows {
        return Err("unexpected snapshot statement column batch rows".to_string());
    }

    let pull_query = conn.prepare(
        r#"[:find (pull ?e [:user/name {:user/friend [:user/name]}])
           :where [?e :user/name "Ada"]]"#,
    )?;
    let pulled = pull_query.query_conn(&conn, "[]")?.scalar()?;
    println!("pull: {pulled:?}");
    let friend_name = pulled
        .map_get(":user/friend")
        .and_then(|friend| friend.map_get(":user/name"));
    if pulled.map_get(":user/name") != Some(&Value::String("Ada".to_string()))
        || friend_name != Some(&Value::String("Grace".to_string()))
    {
        return Err("unexpected pull result".to_string());
    }

    let pull_db = conn.db()?;
    let direct_pull = pull_db.pull("[:user/name {:user/friend [:user/name]}]", 1)?;
    println!("direct pull: {direct_pull:?}");
    let direct_friend = direct_pull
        .map_get(":user/friend")
        .and_then(|friend| friend.map_get(":user/name"));
    if direct_pull.map_get(":user/name") != Some(&Value::String("Ada".to_string()))
        || direct_friend != Some(&Value::String("Grace".to_string()))
    {
        return Err("unexpected direct pull".to_string());
    }

    let lookup_pull =
        pull_db.pull_lookup_ref_string("[:user/name]", ":user/email", "ada@example.com")?;
    println!("lookup pull: {lookup_pull:?}");
    if lookup_pull.map_get(":user/name") != Some(&Value::String("Ada".to_string())) {
        return Err("unexpected lookup-ref pull".to_string());
    }

    let many_pull = pull_db.pull_many("[:user/name]", &[1, 2])?;
    println!("pull many: {many_pull:?}");
    let mut many_names: Vec<String> = match many_pull {
        Value::Vector(items) => items
            .iter()
            .filter_map(|item| match item.map_get(":user/name") {
                Some(Value::String(name)) => Some(name.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    };
    many_names.sort();
    if many_names != vec!["Ada".to_string(), "Grace".to_string()] {
        return Err("unexpected pull-many".to_string());
    }

    let ada_entity = pull_db.entity(1)?;
    let friend_entity = ada_entity.ref_entity(":user/friend")?;
    let lookup_entity = pull_db.entity_lookup_ref_string(":user/email", "ada@example.com")?;
    let ident_entity = pull_db.entity_ident(":user/email")?;
    println!("entity view: {:?}", ada_entity.touch()?);
    if !ada_entity.found()
        || ada_entity.id() != 1
        || !ada_entity.contains(":user/name")
        || ada_entity.get(":user/name")? != Value::String("Ada".to_string())
        || ada_entity.values(":user/name")? != Value::Vector(vec![Value::String("Ada".to_string())])
        || friend_entity.id() != 2
        || friend_entity.get(":user/name")? != Value::String("Grace".to_string())
        || ada_entity.refs(":user/friend") != vec![2]
        || lookup_entity.id() != 1
        || lookup_entity.get(":user/name")? != Value::String("Ada".to_string())
        || ident_entity.id() != 90
        || ada_entity.touch()?.map_get(":user/name") != Some(&Value::String("Ada".to_string()))
    {
        return Err("unexpected entity view output".to_string());
    }

    let many_lookup_pull = pull_db.pull_many_lookup_ref_string(
        "[:user/name]",
        ":user/email",
        &[
            "ada@example.com",
            "missing@example.com",
            "grace@example.com",
        ],
    )?;
    let many_lookup_items = match many_lookup_pull {
        Value::Vector(items) => items,
        _ => Vec::new(),
    };
    if many_lookup_items.len() != 3
        || many_lookup_items[0].map_get(":user/name") != Some(&Value::String("Ada".to_string()))
        || many_lookup_items[1] != Value::Nil
        || many_lookup_items[2].map_get(":user/name") != Some(&Value::String("Grace".to_string()))
    {
        return Err("unexpected pull-many lookup-ref".to_string());
    }

    let prepared_pattern = PreparedPullPattern::new("[:user/name]")?;
    let prepared_pattern_ast = prepared_pattern.edn();
    if !prepared_pattern_ast.contains(":pattern") || !prepared_pattern_ast.contains(":attr") {
        return Err("prepared pull pattern AST did not expose parser keys".to_string());
    }
    let prepared_pull = pull_db.pull_prepared(&prepared_pattern, 1)?;
    println!("prepared direct pull: {prepared_pull:?}");
    if prepared_pull.map_get(":user/name") != Some(&Value::String("Ada".to_string())) {
        return Err("unexpected prepared pull".to_string());
    }
    let prepared_many = pull_db.pull_many_prepared(&prepared_pattern, &[1, 2])?;
    let mut prepared_names: Vec<String> = match prepared_many {
        Value::Vector(items) => items
            .iter()
            .filter_map(|item| match item.map_get(":user/name") {
                Some(Value::String(name)) => Some(name.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    };
    prepared_names.sort();
    if prepared_names != vec!["Ada".to_string(), "Grace".to_string()] {
        return Err("unexpected prepared pull-many".to_string());
    }
    let prepared_lookup_pull = pull_db.pull_many_lookup_ref_string_prepared(
        &prepared_pattern,
        ":user/email",
        &["ada@example.com", "grace@example.com"],
    )?;
    let mut prepared_lookup_names: Vec<String> = match prepared_lookup_pull {
        Value::Vector(items) => items
            .iter()
            .filter_map(|item| match item.map_get(":user/name") {
                Some(Value::String(name)) => Some(name.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    };
    prepared_lookup_names.sort();
    if prepared_lookup_names != vec!["Ada".to_string(), "Grace".to_string()] {
        return Err("unexpected prepared pull-many lookup-ref".to_string());
    }

    let pull_pattern_query = conn.prepare(
        r#"[:find (pull ?e ?pattern)
           :in $ ?pattern ?name
           :where [?e :user/name ?name]]"#,
    )?;
    let mut pull_pattern_stmt = pull_pattern_query.statement()?;
    let bound_pull = pull_pattern_stmt
        .bind_pull_pattern_and_string("[:user/name {:user/friend [:user/name]}]", "Ada")?
        .query_conn(&conn)?
        .scalar()?;
    println!("statement pull pattern: {bound_pull:?}");
    let bound_friend = bound_pull
        .map_get(":user/friend")
        .and_then(|friend| friend.map_get(":user/name"));
    if bound_pull.map_get(":user/name") != Some(&Value::String("Ada".to_string()))
        || bound_friend != Some(&Value::String("Grace".to_string()))
    {
        return Err("unexpected statement pull pattern".to_string());
    }

    let all_emails = conn.prepare(r#"[:find ?e ?email :where [?e :user/email ?email]]"#)?;
    let snapshot = conn.db()?;
    conn.transact(r#"[{:db/id 3 :user/name "Alan" :user/email "alan@example.com"}]"#);
    let current_rows = all_emails.query_conn(&conn, "[]")?.row_count();
    let snapshot_rows = all_emails.query_db(&snapshot, "[]")?.row_count();
    println!("current-db rows: {current_rows}");
    println!("snapshot-db rows: {snapshot_rows}");
    if current_rows != 3 || snapshot_rows != 2 {
        return Err("unexpected snapshot row counts".to_string());
    }
    let mut snapshot_names = snapshot.q(r#"[:find ?name :where [?e :user/name ?name]]"#, "[]")?;
    snapshot_names.sort_by(|left, right| format!("{left:?}").cmp(&format!("{right:?}")));
    if snapshot_names
        != vec![
            vec![Value::String("Ada".to_string())],
            vec![Value::String("Grace".to_string())],
        ]
    {
        return Err("unexpected one-shot DB query rows".to_string());
    }

    let mut snapshot_stmt = email_query.statement()?;
    let snapshot_stmt_rows = snapshot_stmt
        .bind_string("ada@example.com")?
        .query_db(&snapshot)?
        .rows();
    if snapshot_stmt_rows
        != vec![vec![
            Value::Entity(1),
            Value::String("ada@example.com".to_string()),
        ]]
    {
        return Err("unexpected snapshot statement rows".to_string());
    }

    let barbara_query = conn.prepare(r#"[:find ?e :where [?e :user/name "Barbara"]]"#)?;
    let dorothy_query = conn.prepare(r#"[:find ?e :where [?e :user/name "Dorothy"]]"#)?;
    let with_report = snapshot.with_report(r#"[{:db/id 4 :user/name "Barbara"}]"#)?;
    println!("with-db: {}", with_report.edn());
    if with_report.value().map_get(":ok") != Some(&Value::Bool(true)) {
        return Err("unexpected typed with report".to_string());
    }
    let report_before = with_report.db_before()?;
    let report_after = with_report.db_after()?;
    let report_before_barbara_rows = barbara_query.query_db(&report_before, "[]")?.row_count();
    let report_after_barbara_rows = barbara_query.query_db(&report_after, "[]")?.row_count();
    if report_before_barbara_rows != 0 || report_after_barbara_rows != 1 {
        return Err(format!(
            "unexpected with report db rows: before={report_before_barbara_rows} after={report_after_barbara_rows}"
        ));
    }
    let next_db = snapshot.db_with(r#"[{:db/id 4 :user/name "Barbara"}]"#)?;
    let source_barbara_rows = barbara_query.query_db(&snapshot, "[]")?.row_count();
    let next_barbara_rows = barbara_query.query_db(&next_db, "[]")?.row_count();
    if source_barbara_rows != 0 || next_barbara_rows != 1 {
        return Err(format!(
            "unexpected db-with rows: source={source_barbara_rows} next={next_barbara_rows}"
        ));
    }

    let derived = Conn::from_db(&next_db)?;
    derived.transact(r#"[{:db/id 5 :user/name "Dorothy"}]"#);
    let derived_barbara_rows = barbara_query.query_conn(&derived, "[]")?.row_count();
    let derived_dorothy_rows = dorothy_query.query_conn(&derived, "[]")?.row_count();
    if derived_barbara_rows != 1 || derived_dorothy_rows != 1 {
        return Err("conn-from-db did not initialize from DB value".to_string());
    }

    let sqlite_path = "tmp.vev.rust.sqlite";
    remove_sqlite_files(sqlite_path);
    {
        let durable = DurableConn::open(sqlite_path)?;
        if durable.backend() != "sqlite" || durable.path() != sqlite_path {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable connection metadata".to_string());
        }
        if durable.basis_t() != 0 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected initial durable basis".to_string());
        }
        if durable.tx_count() != 0 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected initial durable tx count".to_string());
        }
        if durable.tx_ids() != Vec::<u64>::new() {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected initial durable tx ids".to_string());
        }
        let info = durable.info_edn();
        if !info.contains(":backend :sqlite")
            || !info.contains(":basis-t 0")
            || !info.contains(":tx-count 0")
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable connection info".to_string());
        }
        durable.transact(
            r#"[{:db/id 1 :user/name "Durable Ada" :user/email "durable-ada@example.com"}]"#,
        )?;
        let first_basis = durable.basis_t();
        if first_basis == 0 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable basis after simple tx".to_string());
        }
        let report = durable.transact_report(
            r#"[{:db/id 8 :user/name "Durable Report" :user/email "durable-report@example.com"}]"#,
        )?;
        if report.value().map_get(":ok") != Some(&Value::Bool(true)) {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite transaction report".to_string());
        }
        if durable.basis_t() != first_basis + 1 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable basis after first tx".to_string());
        }
        if durable.tx_count() != 2 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx count after first tx".to_string());
        }
        if durable.tx_ids() != vec![first_basis, first_basis + 1] {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx ids after first tx".to_string());
        }
        let bulk_a = TxBuilder::new(3)?;
        let bulk_b = TxBuilder::new(1)?;
        bulk_a.add_string(2, ":user/name", "Durable Grace")?;
        bulk_a.add_int(2, ":user/age", 37)?;
        bulk_a.add_bool(2, ":user/active", true)?;
        bulk_b.add_string(3, ":user/name", "Durable Hedy")?;
        let bulk_report = durable.transact_bulk_report(&[&bulk_a, &bulk_b])?;
        if bulk_report.value().map_get(":ok") != Some(&Value::Bool(true)) {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite bulk transaction report".to_string());
        }
        if durable.basis_t() != first_basis + 2 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable basis after bulk tx".to_string());
        }
        if durable.tx_count() != 3 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx count after bulk tx".to_string());
        }
        if durable.tx_ids() != vec![first_basis, first_basis + 1, first_basis + 2] {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx ids after bulk tx".to_string());
        }
        let logical_a = TxBuilder::new(3)?;
        let logical_b = TxBuilder::new(2)?;
        logical_a.add_string(4, ":user/name", "Durable Ada")?;
        logical_a.add_keyword(4, ":user/role", ":role/admin")?;
        logical_a.add_entity(4, ":user/friend", 5)?;
        logical_b.add_string(5, ":user/name", "Durable Dorothy")?;
        logical_b.add_symbol(5, ":user/source", "source/import")?;
        let logical_reports = durable.transact_logical_bulk_reports(&[&logical_a, &logical_b])?;
        let logical_values = logical_reports.values()?;
        if logical_values.len() != 2
            || logical_values[0].map_get(":ok") != Some(&Value::Bool(true))
            || logical_values[1].map_get(":ok") != Some(&Value::Bool(true))
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite logical group transaction reports".to_string());
        }
        let empty_logical_reports = durable.transact_logical_bulk_reports(&[])?;
        if !empty_logical_reports.values()?.is_empty() {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected empty logical group transaction reports".to_string());
        }
        let logical_edn_reports = durable.transact_logical_edn_reports(&[
            r#"[{:db/id 6 :user/name "Durable Katherine"}]"#,
            r#"[{:db/id 7 :user/name "Durable Mary"}]"#,
        ])?;
        let logical_edn_values = logical_edn_reports.values()?;
        if logical_edn_values.len() != 2
            || logical_edn_values[0].map_get(":ok") != Some(&Value::Bool(true))
            || logical_edn_values[1].map_get(":ok") != Some(&Value::Bool(true))
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite logical EDN group transaction reports".to_string());
        }
        if durable.basis_t() != first_basis + 6 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable basis after logical group tx".to_string());
        }
        if durable.tx_count() != 7 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx count after logical group tx".to_string());
        }
        if durable.tx_ids()
            != (0..7)
                .map(|offset| first_basis + offset)
                .collect::<Vec<_>>()
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected durable tx ids after logical group tx".to_string());
        }
        let durable_query =
            PreparedQuery::new(r#"[:find ?e ?email :where [?e :user/email ?email]]"#)?;
        let durable_db = durable.db()?;
        let live_rows = durable_query.query_db(&durable_db, "[]")?.row_count();
        println!("sqlite-live rows: {live_rows}");
        let durable_q_rows = durable.q(
            r#"[:find ?name :where [?e :user/email "durable-ada@example.com"] [?e :user/name ?name]]"#,
            "[]",
        )?;
        if live_rows != 2 || durable_q_rows != vec![vec![Value::String("Durable Ada".to_string())]]
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite live row count".to_string());
        }
    }
    {
        let durable = DurableConn::open(sqlite_path)?;
        let first_basis = durable.tx_ids().first().copied().unwrap_or(0);
        if first_basis == 0 || durable.basis_t() != first_basis + 6 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected reopened durable basis".to_string());
        }
        if durable.tx_count() != 7 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected reopened durable tx count".to_string());
        }
        if durable.tx_ids()
            != (0..7)
                .map(|offset| first_basis + offset)
                .collect::<Vec<_>>()
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected reopened durable tx ids".to_string());
        }
        let durable_query =
            PreparedQuery::new(r#"[:find ?e ?email :where [?e :user/email ?email]]"#)?;
        let durable_db = durable.db()?;
        let reopened_rows = durable_query.query_db(&durable_db, "[]")?.row_count();
        println!("sqlite-reopened rows: {reopened_rows}");
        if reopened_rows != 2 {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite reopened row count".to_string());
        }
        let durable_entity = durable_db.entity(1)?;
        if durable_entity.get(":user/name")? != Value::String("Durable Ada".to_string())
            || durable_entity.get(":user/email")?
                != Value::String("durable-ada@example.com".to_string())
        {
            remove_sqlite_files(sqlite_path);
            return Err("unexpected SQLite entity view".to_string());
        }
    }
    remove_sqlite_files(sqlite_path);

    Ok(())
}
