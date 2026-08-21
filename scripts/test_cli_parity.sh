#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

trap 'status=$?; printf "cli-parity-error line=%s status=%s\n" "$LINENO" "$status" >&2; exit "$status"' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/build/vevdb"

if [[ ! -x "$CLI" ]]; then
  "$ROOT/scripts/build_cli.sh" >/dev/null
fi

TMP_DIR="$(mktemp -d "$ROOT/build/vevdb-cli-parity.XXXXXX")"
DB="$TMP_DIR/example.db"
trap 'rm -rf "$TMP_DIR"' EXIT

tx1="$($CLI transact "$DB" '[{:db/id 1 :person/name "Ada"}]')"
tx2="$($CLI transact "$DB" '[{:db/id 2 :person/name "Grace"}]')"
case "$tx1$tx2" in *":db-before"*":db-after"*) ;; *) exit 1 ;; esac

as_of="$($CLI query "$DB" \
  '[:find ?name :where [?e :person/name ?name]]' \
  --result q --db '[[:as-of 1]]')"
case "$as_of" in *'"Ada"'*) ;; *) exit 1 ;; esac
case "$as_of" in *'"Grace"'*) exit 1 ;; esac

hypothetical="$($CLI pull "$DB" '[:person/name]' 3 \
  --db '[[:with [{:db/id 3 :person/name "Lin"}]]]')"
case "$hypothetical" in *'"Lin"'*) ;; *) exit 1 ;; esac

hypothetical_entity="$($CLI entity-get "$DB" 3 :person/name \
  --db '[[:with [{:db/id 3 :person/name "Lin"}]]]')"
test "$hypothetical_entity" = '"Lin"'

datoms="$($CLI datoms "$DB" :eavt '[]')"
case "$datoms" in '[[['*) ;; *) exit 1 ;; esac

logical="$($CLI transact-many "$DB" \
  '[[{:db/id 4 :person/name "Edsger"}]
    [{:db/id 5 :person/name "Barbara"}]]' --mode logical)"
case "$logical" in '[{'*'} {'*'}]') ;; *) exit 1 ;; esac

flatten="$($CLI transact-many "$DB" \
  '[[{:db/id 6 :person/name "Margaret"}]
    [{:db/id 7 :person/name "Donald"}]]' --mode flatten)"
case "$flatten" in '{'*':ok true'*) ;; *) exit 1 ;; esac

exec_result="$($CLI exec "$DB" \
  '{:steps [{:id :current :op :db}
            {:id :old :op :as-of :db [:ref :current] :time 1}
            {:id :prepared :op :prepare-query
             :sources {$old nil}
             :query [:find ?e ?name
                     :in $ $old
                     :where [$old ?e :person/name ?name]
                            [?e :person/name ?name]]}
            {:id :joined :op :query
             :db [:ref :current]
             :sources {$old [:ref :old]}
             :query [:ref :prepared]}]
    :return {:old [:ref :old]
             :joined [:ref :joined]}}')"
case "$exec_result" in *':as-of-t 1'*'"Ada"'*) ;; *) exit 1 ;; esac
case "$exec_result" in *'"Grace"'*) exit 1 ;; esac

captured="$($CLI exec --memory \
  '{:steps [{:id :bad :op :query :query nope :on-error :capture}]
    :return [:ref :bad]}')"
case "$captured" in *':ok false'*':step :bad'*) ;; *) exit 1 ;; esac

uuid_result="$($CLI exec --memory \
  '{:steps [{:id :uuid :op :squuid}
            {:id :millis :op :squuid-time-millis :uuid [:ref :uuid]}]
    :return {:uuid [:ref :uuid] :millis [:ref :millis]}}')"
case "$uuid_result" in *':uuid #uuid '*':millis '*) ;; *) exit 1 ;; esac

$CLI transact "$DB" \
  '[{:db/ident :person/email
     :db/valueType :db.type/string
     :db/cardinality :db.cardinality/one
     :db/index true}]' >/dev/null
$CLI transact "$DB" '[{:db/id 100 :person/email "ada@example.test"}]' >/dev/null

info="$($CLI info "$DB")"
case "$info" in *':backend :sqlite'*':tx-count '*':tx-ids ['*) ;; *) exit 1 ;; esac

synced="$($CLI sync "$DB" 1)"
case "$synced" in *':basis-t '*':history? false'*) ;; *) exit 1 ;; esac

db_info="$($CLI db-info "$DB")"
case "$db_info" in *':stats {'*':datoms '*) ;; *) exit 1 ;; esac

pull_many="$($CLI pull-many "$DB" '[:person/name]' '[1 2 999]')"
case "$pull_many" in *'"Ada"'*'"Grace"'*'nil'*) ;; *) exit 1 ;; esac

attribute="$($CLI attribute "$DB" :person/email)"
case "$attribute" in *':ident :person/email'*':indexed true'*) ;; *) exit 1 ;; esac
test "$($CLI entity-contains "$DB" 100 :person/email)" = 'true'
case "$($CLI entid "$DB" :person/email)" in '[:vev/entity '*) ;; *) exit 1 ;; esac

seeked="$($CLI seek-datoms "$DB" :avet '[:person/email]')"
rseeked="$($CLI rseek-datoms "$DB" :avet '[:person/email "zzzz"]')"
ranged="$($CLI index-range "$DB" :person/email nil nil)"
case "$seeked$rseeked$ranged" in *'"ada@example.test"'*) ;; *) exit 1 ;; esac

index_pulled="$($CLI index-pull "$DB" \
  '{:index :avet :selector [:person/email] :start [:person/email]}')"
case "$index_pulled" in *'"ada@example.test"'*) ;; *) exit 1 ;; esac

maintained="$($CLI maintain-indexes "$DB" --max-steps 0)"
case "$maintained" in *':ok true'*':steps '*) ;; *) exit 1 ;; esac
index_info="$($CLI index-info "$DB" :eavt)"
case "$index_info" in *':index :eavt'*':run-count '*) ;; *) exit 1 ;; esac

if rejected="$($CLI transact-many "$DB" \
  '[[[:db.fn/cas 1 :person/name "Wrong" "Changed"]]]' \
  --mode logical 2>&1)"; then
  exit 1
fi
case "$rejected" in *':ok false'*':operation :transact-many'*) ;; *) exit 1 ;; esac
case "$rejected" in *'Ada'*) ;; *) exit 1 ;; esac

tx_range="$($CLI tx-range "$DB" 1)"
case "$tx_range" in *':t 1'*':data ['*) ;; *) exit 1 ;; esac

schema_and_pull="$($CLI exec "$DB" \
  '{:steps [{:id :attribute :op :attribute :attribute :person/email}
            {:id :pulled :op :index-pull
             :index :avet
             :selector [:person/email]
             :start [:person/email]}]
    :return {:attribute [:ref :attribute]
             :pulled [:ref :pulled]}}')"
case "$schema_and_pull" in *':ident :person/email'*'"ada@example.test"'*) ;; *) exit 1 ;; esac

prepared_pull_many="$($CLI exec "$DB" \
  '{:steps [{:id :pattern :op :prepare-pull :pattern [:person/name]}
            {:id :people :op :pull-many
             :pattern [:ref :pattern]
             :entities [1 2]}]
    :return [:ref :people]}')"
case "$prepared_pull_many" in *'"Ada"'*'"Grace"'*) ;; *) exit 1 ;; esac

tempid_composition="$($CLI exec --memory \
  '{:steps [{:id :hyp :op :with
             :tx [{:db/id "new" :person/name "Temp"}]}
            {:id :eid :op :resolve-tempid
             :report [:ref :hyp] :tempid "new"}
            {:id :pulled :op :pull
             :db [:ref :hyp :db-after]
             :pattern [:person/name]
             :entity [:ref :eid]}]
    :return {:eid [:ref :eid]
             :pulled [:ref :pulled]
             :before [:ref :hyp :db-before]}}')"
case "$tempid_composition" in *':eid [:vev/entity '*'"Temp"'*':basis-t 0'*) ;; *) exit 1 ;; esac

rules_result="$($CLI exec --memory \
  '{:steps [{:id :facts :op :init-db
             :tx [{:db/id 1 :person/name "Ivan" :person/age 19}
                  {:db/id 2 :person/name "Petr" :person/age 17}]}
            {:id :adult :op :query :db [:ref :facts]
             :query "[:find ?name :in % :where (adult ?e) [?e :person/name ?name]]"
             :rules "[[(adult ?e) [?e :person/age ?age] [(>= ?age 18)]]]"}]
    :return [:ref :adult]}')"
case "$rules_result" in *'"Ivan"'*) ;; *) exit 1 ;; esac
case "$rules_result" in *'"Petr"'*) exit 1 ;; esac

rules_and_sources="$($CLI exec --memory \
  '{:steps [{:id :current :op :init-db
             :tx [{:db/id 1 :person/name "New"}]}
            {:id :old :op :init-db
             :tx [{:db/id 1 :person/name "Old"}]}
            {:id :prepared :op :prepare-query
             :sources {$old nil}
             :query "[:find ?name :in $ $old % :where (old-name ?e ?name)]"
             :rules "[[(old-name ?e ?name) [$old ?e :person/name ?name]]]"}
            {:id :answer :op :query
             :db [:ref :current]
             :sources {$old [:ref :old]}
             :query [:ref :prepared]}]
    :return [:ref :answer]}')"
case "$rules_and_sources" in *'"Old"'*) ;; *) exit 1 ;; esac
case "$rules_and_sources" in *'"New"'*) exit 1 ;; esac

relation_result="$($CLI exec --memory \
  '{:steps [{:id :adult :op :query
             :query "[:find ?name :in $rows :where [$rows ?e :age ?age] [(>= ?age 18)] [$rows ?e :name ?name]]"
             :inputs [[[1 :age 19] [1 :name "Ivan"]
                       [2 :age 17] [2 :name "Petr"]]]}]
    :return [:ref :adult]}')"
case "$relation_result" in *'"Ivan"'*) ;; *) exit 1 ;; esac
case "$relation_result" in *'"Petr"'*) exit 1 ;; esac

ALT_DB_EDN="${TMP_DIR#"$ROOT"/}/alternate.db"
alternate_result="$($CLI exec --memory \
  "{:steps [{:id :tx :op :transact :store \"$ALT_DB_EDN\"
             :tx [{:db/id 1 :source/name \"alternate\"}]}
            {:id :q :op :query :db [:ref :tx :db-after]
             :query [:find ?name . :where [1 :source/name ?name]]}]
    :return [:ref :q]}")"
test "$alternate_result" = '"alternate"'

alternate_db="$($CLI exec --memory \
  "{:steps [{:id :db :op :db :store \"$ALT_DB_EDN\"}]
    :return [:ref :db]}")"
case "$alternate_db" in *':basis-t 1'*) ;; *) exit 1 ;; esac

alternate_reopened="$($CLI exec --memory \
  "{:steps [{:id :tx :op :transact :store \"$ALT_DB_EDN\"
             :tx [{:db/id 2 :source/name \"reopened\"}]}
            {:id :db :op :db :store \"$ALT_DB_EDN\"}
            {:id :q :op :query :db [:ref :db]
             :query [:find ?name . :where [2 :source/name ?name]]}]
    :return {:answer [:ref :q] :tx-db [:ref :tx :db-after]}}")"
case "$alternate_reopened" in *':answer "reopened"'*':basis-t 2'*) ;; *) exit 1 ;; esac

alternate_maintenance="$($CLI exec --memory \
  "{:steps [{:id :info :op :index-info :store \"$ALT_DB_EDN\" :index :eavt}
            {:id :maintain :op :maintain-indexes :store \"$ALT_DB_EDN\"
             :max-steps 0}]
    :return {:info [:ref :info] :maintenance [:ref :maintain]}}")"
case "$alternate_maintenance" in *':index :eavt'*':steps 0'*) ;; *) exit 1 ;; esac

if "$CLI" query "$DB" not-edn >"$TMP_DIR/error.out" 2>"$TMP_DIR/error.err"; then
  exit 1
fi
test ! -s "$TMP_DIR/error.out"
case "$(cat "$TMP_DIR/error.err")" in
  *':vev/error :vev.error/invalid-input'*':operation :query'*) ;;
  *) exit 1 ;;
esac

printf '%s\n' '[:person/name]' | "$CLI" pull "$DB" - 1 >"$TMP_DIR/stdin.out"
case "$(cat "$TMP_DIR/stdin.out")" in *'"Ada"'*) ;; *) exit 1 ;; esac

if "$CLI" query "$DB" - - >"$TMP_DIR/double-stdin.out" 2>"$TMP_DIR/double-stdin.err"; then
  exit 1
fi
case "$(cat "$TMP_DIR/double-stdin.err")" in *'at most one argument'*) ;; *) exit 1 ;; esac

"$CLI" watch "$DB" --after 0 >"$TMP_DIR/watch.out" &
watch_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$TMP_DIR/watch.out" ]] && break
  sleep 0.1
done
kill -INT "$watch_pid" 2>/dev/null || true
wait "$watch_pid" 2>/dev/null || true
case "$(cat "$TMP_DIR/watch.out")" in *':tx-data'*':tx '*) ;; *) exit 1 ;; esac

echo :vevdb-cli-parity-ok
