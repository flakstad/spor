#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Vev contributors
# SPDX-License-Identifier: EPL-2.0

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/smoke_clojure_git_coordinates.sh <version> <m2-dir>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$1"
M2_DIR="$(cd "$2" && pwd)"
GIT_URL="${VEV_CLJ_GIT_URL:-https://github.com/vevdb/vev-clj.git}"
GIT_SHA="${VEV_CLJ_GIT_SHA:-}"
GIT_REF="${VEV_CLJ_GIT_REF:-${GITHUB_HEAD_REF:-main}}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vev-clojure-git-coordinates.XXXXXX")"

if [[ -z "$GIT_SHA" ]]; then
  GIT_SHA="$(git ls-remote "$GIT_URL" "refs/heads/$GIT_REF" | awk 'NR == 1 {print $1}')"
fi
if [[ -z "$GIT_SHA" && "$GIT_REF" != "main" ]]; then
  GIT_REF="main"
  GIT_SHA="$(git ls-remote "$GIT_URL" refs/heads/main | awk 'NR == 1 {print $1}')"
fi
if [[ -z "$GIT_SHA" ]]; then
  echo "could not resolve vev-clj $GIT_REF from $GIT_URL" >&2
  exit 1
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/deps.edn" <<EOF
{:mvn/local-repo "$M2_DIR"
 :deps {com.vevdb/vev-clj
        {:git/url "$GIT_URL"
         :git/sha "$GIT_SHA"}}
 :aliases {:run {:jvm-opts ["--enable-native-access=ALL-UNNAMED"]}}}
EOF

(
  cd "$TMP_DIR"
  env -u VEV_LIB clojure -M:run -e "(require '[vev.core :as d])
(let [conn (d/connect \"git-coordinate.vev\")]
  (try
    (d/transact conn [{:db/id 1 :user/name \"Ada\"}])
    (assert (= #{[\"Ada\"]}
               (d/q '[:find ?name :where [?e :user/name ?name]]
                    (d/db conn))))
    (finally
      (.close conn))))
(println :vev-clojure-git-coordinate-ok)"
)
