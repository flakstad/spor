#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/smoke_jvm_remote_coordinates.sh <version> <staged-m2-dir>" >&2
  exit 1
fi

VERSION="$1"
STAGED_M2_DIR="$(cd "$2" && pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-jvm-remote.XXXXXX")"
PORT_FILE="$TMP_DIR/port"
CERT_FILE="$TMP_DIR/cert.pem"
KEY_FILE="$TMP_DIR/key.pem"
TRUST_STORE="$TMP_DIR/truststore"
SERVER_PID=""
SERVER_LOG="$TMP_DIR/server.log"

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

report_failure() {
  local status="$1"
  local line="$2"
  local command="$3"
  echo "fresh JVM coordinate smoke failed at line $line with status $status: $command" >&2
  if [[ -s "$SERVER_LOG" ]]; then
    echo "temporary Maven repository log:" >&2
    cat "$SERVER_LOG" >&2
  fi
  exit "$status"
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required for the temporary HTTPS Maven repository" >&2
  exit 1
}
command -v keytool >/dev/null 2>&1 || {
  echo "keytool is required for the temporary HTTPS Maven repository" >&2
  exit 1
}

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 1 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  >/dev/null 2>&1

JAVA_HOME_PATH="$(
  java -XshowSettings:properties -version 2>&1 |
    sed -n 's/^[[:space:]]*java.home = //p' |
    head -1
)"
cp "$JAVA_HOME_PATH/lib/security/cacerts" "$TRUST_STORE"
keytool \
  -importcert \
  -noprompt \
  -alias vev-staged \
  -file "$CERT_FILE" \
  -keystore "$TRUST_STORE" \
  -storepass changeit \
  >/dev/null

python3 -u - "$STAGED_M2_DIR" "$PORT_FILE" "$CERT_FILE" "$KEY_FILE" >"$SERVER_LOG" 2>&1 <<'PY' &
import http.server
import os
from pathlib import Path
import socketserver
import ssl
import sys

root = sys.argv[1]
port_file = Path(sys.argv[2])
cert_file = sys.argv[3]
key_file = sys.argv[4]
os.chdir(root)
with socketserver.TCPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler) as server:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert_file, key_file)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    port_file.write_text(str(server.server_address[1]))
    server.serve_forever()
PY
SERVER_PID="$!"

for _ in $(seq 1 100); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.05
done
[[ -s "$PORT_FILE" ]] || { echo "temporary Maven repository did not start" >&2; exit 1; }

PORT="$(cat "$PORT_FILE")"
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "temporary Maven HTTPS repository exited before the consumer smoke" >&2
  wait "$SERVER_PID"
fi

VEV_MAVEN_REPOSITORY_URL="https://127.0.0.1:$PORT" \
VEV_MAVEN_CACHE="$TMP_DIR/consumer-m2" \
VEV_MAVEN_TRUST_STORE="$TRUST_STORE" \
  "$ROOT/scripts/smoke_jvm_coordinates.sh" "$VERSION" "$STAGED_M2_DIR"
