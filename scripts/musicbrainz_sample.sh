#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATOMIC_HOME="${DATOMIC_HOME:-}"
DATOMIC_BIN="$DATOMIC_HOME/bin/datomic"
TRANSACTOR_BIN="$DATOMIC_HOME/bin/transactor"

SAMPLE_URL="${SAMPLE_URL:-https://s3.amazonaws.com/mbrainz/datomic-mbrainz-1968-1973-backup-2017-07-20.tar}"
WORK_DIR="${WORK_DIR:-$ROOT/build/musicbrainz}"
TAR_PATH="$WORK_DIR/datomic-mbrainz-1968-1973-backup-2017-07-20.tar"
BACKUP_DIR="$WORK_DIR/mbrainz-1968-1973"
CONFIG_PATH="$WORK_DIR/dev-transactor.properties"
LOG_DIR="$WORK_DIR/log"
DATA_DIR="$WORK_DIR/data"
PID_FILE="$WORK_DIR/transactor.pid"
PORT="${DATOMIC_PORT:-4334}"
H2_PORT="${DATOMIC_H2_PORT:-$((PORT + 1))}"
DB_NAME="${DATOMIC_DB_NAME:-mbrainz-1968-1973}"
DB_URI="datomic:dev://localhost:$PORT/$DB_NAME"
BACKUP_URI="file://$BACKUP_DIR"

usage() {
  cat <<EOF
usage: scripts/musicbrainz_sample.sh <command>

commands:
  download          download the 1968-1973 backup tar into build/musicbrainz
  extract           extract the backup tar into build/musicbrainz
  write-config      write a local dev transactor config under build/musicbrainz
  start             start a local Datomic dev transactor if it is not running
  stop              stop the transactor started by this script
  restore           restore the sample backup into $DB_URI
  smoke-datomic     start Datomic, run a tiny peer query, then stop Datomic
  query-matrix-datomic
                    start Datomic, run the MusicBrainz query matrix, then stop
                    optional args: passed to scripts/musicbrainz_query_matrix.clj
  export-subset     start Datomic, export Vev-compatible subset EDN, then stop
                    optional args: [output-path] [item-limit]
  export-subset-split
                    start Datomic, export schema/values EDN files, then stop
                    optional args: [output-prefix] [value-limit]
  export-subset-chunks
                    start Datomic, export schema EDN plus chunked value EDN files
                    optional args: [output-prefix] [value-limit] [chunk-size]
  prepare           download, extract, write-config, start, restore
  status            print local paths and transactor status

env:
  DATOMIC_HOME      required path to a Datomic Pro installation
  DATOMIC_PORT      default: 4334
  DATOMIC_H2_PORT   default: DATOMIC_PORT + 1
  DATOMIC_DB_NAME   default: mbrainz-1968-1973
  WORK_DIR          default: \$repo/build/musicbrainz
EOF
}

require-datomic() {
  if [[ -z "$DATOMIC_HOME" ]]; then
    echo "Set DATOMIC_HOME to a Datomic Pro installation." >&2
    exit 1
  fi
  if [[ ! -x "$DATOMIC_BIN" || ! -x "$TRANSACTOR_BIN" ]]; then
    echo "Datomic binaries not found under DATOMIC_HOME=$DATOMIC_HOME" >&2
    exit 1
  fi
}

download() {
  mkdir -p "$WORK_DIR"
  if [[ -f "$TAR_PATH" ]]; then
    echo "download: exists $TAR_PATH"
    return
  fi
  curl -L "$SAMPLE_URL" -o "$TAR_PATH"
}

extract() {
  download
  if [[ -d "$BACKUP_DIR" ]]; then
    echo "extract: exists $BACKUP_DIR"
    return
  fi
  tar -xf "$TAR_PATH" -C "$WORK_DIR"
}

write-config() {
  mkdir -p "$WORK_DIR" "$LOG_DIR" "$DATA_DIR"
  cat > "$CONFIG_PATH" <<EOF
protocol=dev
host=localhost
port=$PORT
h2-port=$H2_PORT
memory-index-threshold=32m
memory-index-max=256m
object-cache-max=128m
data-dir=$DATA_DIR
log-dir=$LOG_DIR
pid-file=$PID_FILE
EOF
  echo "write-config: $CONFIG_PATH"
}

is-running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

start() {
  require-datomic
  write-config
  if [[ -f "$PID_FILE" ]] && ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    rm -f "$PID_FILE"
  fi
  if is-running; then
    echo "start: already running pid=$(cat "$PID_FILE")"
    return
  fi
  nohup "$TRANSACTOR_BIN" "$CONFIG_PATH" > "$WORK_DIR/transactor.out" 2>&1 < /dev/null &
  local pid="$!"
  echo "$pid" > "$PID_FILE"
  for _ in {1..60}; do
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 &&
       lsof -nP -iTCP:"$H2_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "start: running pid=$pid port=$PORT h2-port=$H2_PORT"
      return
    fi
    sleep 1
  done
  echo "start: transactor did not listen on ports $PORT and $H2_PORT" >&2
  tail -80 "$WORK_DIR/transactor.out" >&2 || true
  exit 1
}

stop() {
  if is-running; then
    local pid
    pid="$(cat "$PID_FILE")"
    kill "$pid"
    for _ in {1..20}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
    rm -f "$PID_FILE"
    echo "stop: pid=$pid"
  else
    rm -f "$PID_FILE"
    echo "stop: not running"
  fi
}

restore() {
  require-datomic
  extract
  start
  echo "restore: $BACKUP_URI -> $DB_URI"
  "$DATOMIC_BIN" restore-db "$BACKUP_URI" "$DB_URI"
}

smoke-datomic() {
  require-datomic
  start
  trap stop EXIT
  clojure -Sdeps '{:deps {com.datomic/peer {:mvn/version "1.0.7277"}}}' -M -e "
(require '[datomic.api :as d])
(def uri \"$DB_URI\")
(def conn (d/connect uri))
(def db (d/db conn))
(println :basis-t (d/basis-t db))
(println :datom-sample (take 3 (d/datoms db :eavt)))
(println :artist-sample (take 3 (d/q '[:find ?name :where [?a :artist/name ?name]] db)))
(shutdown-agents)
(System/exit 0)"
}

query-matrix-datomic() {
  require-datomic
  start
  trap stop EXIT
  clojure -Sdeps '{:deps {com.datomic/peer {:mvn/version "1.0.7277"}}}' -M \
    "$ROOT/scripts/musicbrainz_query_matrix.clj" "$@"
}

export-subset() {
  require-datomic
  start
  trap stop EXIT
  local out_path="${1:-$WORK_DIR/vev-mbrainz-subset.edn}"
  local limit="${2:-0}"
  clojure -Sdeps '{:deps {com.datomic/peer {:mvn/version "1.0.7277"}}}' -M \
    "$ROOT/scripts/export_mbrainz_subset.clj" "$DB_URI" "$out_path" "$limit"
}

export-subset-split() {
  require-datomic
  start
  trap stop EXIT
  local out_prefix="${1:-$WORK_DIR/vev-mbrainz-subset}"
  local limit="${2:-0}"
  clojure -Sdeps '{:deps {com.datomic/peer {:mvn/version "1.0.7277"}}}' -M \
    "$ROOT/scripts/export_mbrainz_subset.clj" "$DB_URI" "$out_prefix" "$limit" split
}

export-subset-chunks() {
  require-datomic
  start
  trap stop EXIT
  local out_prefix="${1:-$WORK_DIR/vev-mbrainz-subset}"
  local limit="${2:-0}"
  local chunk_size="${3:-100000}"
  clojure -Sdeps '{:deps {com.datomic/peer {:mvn/version "1.0.7277"}}}' -M \
    "$ROOT/scripts/export_mbrainz_subset.clj" "$DB_URI" "$out_prefix" "$limit" split-chunks "$chunk_size"
}

status() {
  cat <<EOF
DATOMIC_HOME=$DATOMIC_HOME
WORK_DIR=$WORK_DIR
TAR_PATH=$TAR_PATH
BACKUP_DIR=$BACKUP_DIR
CONFIG_PATH=$CONFIG_PATH
DB_URI=$DB_URI
BACKUP_URI=$BACKUP_URI
EOF
  if is-running; then
    echo "transactor=running pid=$(cat "$PID_FILE")"
  else
    echo "transactor=stopped"
  fi
}

case "${1:-}" in
  download) download ;;
  extract) extract ;;
  write-config) write-config ;;
  start) start ;;
  stop) stop ;;
  restore) restore ;;
  smoke-datomic) smoke-datomic ;;
  query-matrix-datomic) shift; query-matrix-datomic "$@" ;;
  export-subset) shift; export-subset "$@" ;;
  export-subset-split) shift; export-subset-split "$@" ;;
  export-subset-chunks) shift; export-subset-chunks "$@" ;;
  prepare) download; extract; write-config; start; restore ;;
  status) status ;;
  ""|-h|--help|help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
