#!/usr/bin/env bash
# End-to-end proof that the one unit works together.
#
#   fabric/tests/e2e.sh
#
# It starts (or reuses) the Durable Object worker, starts a fabric against a
# scratch postgres database, drives two agents through a task, refuses the
# things that must be refused, mirrors to the Durable Object, rebuilds a second
# fabric's database from that Object alone, observes a lease expiring, and runs
# the WebAssembly peer against a block stored in IPFS.
#
# Nothing here is mocked: postgres, the relay, IPFS, the IPLD pool, the local
# wrangler/workerd and the wasm kernel are the real ones on this host.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
BIN="${FABRIC_BIN:-$repo/target/debug/agent-fabric}"
PORT="${FABRIC_E2E_PORT:-18190}"
PORT2="${FABRIC_E2E_PORT2:-18191}"
DO_PORT="${FABRIC_E2E_DO_PORT:-18793}"
DB="${FABRIC_E2E_DB:-agent_fabric_e2e}"
DB2="${FABRIC_E2E_DB2:-agent_fabric_e2e_rebuild}"
BASE="http://127.0.0.1:$PORT"
BASE2="http://127.0.0.1:$PORT2"
export PGCONNECT_TIMEOUT=5

log="$(mktemp -d)"
pids=()
fail=0
cleanup() {
  for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
  if [ -n "${DO_PID:-}" ]; then kill "$DO_PID" 2>/dev/null || true; fi
  wait 2>/dev/null || true
}
trap cleanup EXIT

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
expect() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: got '$2' want '$3'"; fi; }

wait_for() {
  local url=$1 tries=${2:-60}
  for _ in $(seq "$tries"); do
    curl -sf --max-time 2 "$url" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

[ -x "$BIN" ] || { echo "no agent-fabric binary at $BIN (cargo build --bin agent-fabric)"; exit 2; }

# ---------------------------------------------------------------- datastores
for db in "$DB" "$DB2"; do
  createdb -w "$db" 2>/dev/null || true
  psql -w -q -d "$db" -c 'drop schema if exists fabric cascade;' >/dev/null 2>&1 || {
    echo "cannot reach postgres database $db"; exit 2; }
done
ok "scratch databases $DB and $DB2"

# ------------------------------------------------------- durable object board
if [ -n "${FABRIC_DO_URL:-}" ]; then
  DO_URL="$FABRIC_DO_URL"
  ok "using the Durable Object board at $DO_URL"
else
  if ! command -v wrangler >/dev/null 2>&1; then
    echo "skip: no wrangler; set FABRIC_DO_URL to test Durable Object sync"
    DO_URL=""
  else
    ( cd "$here/../durable" && rm -rf .wrangler && exec wrangler dev --local --port "$DO_PORT" ) \
      >"$log/wrangler.log" 2>&1 &
    DO_PID=$!
    DO_URL="http://127.0.0.1:$DO_PORT/board"
    if wait_for "http://127.0.0.1:$DO_PORT/board/health" 80; then
      ok "Durable Object worker up on $DO_URL"
    else
      bad "Durable Object worker did not become ready (see $log/wrangler.log)"
      tail -20 "$log/wrangler.log"
    fi
  fi
fi

# ------------------------------------------------------------------- services
start_fabric() {
  local db=$1 port=$2 sock=$3 out=$4
  env FABRIC_DB="$db" FABRIC_HTTP="127.0.0.1:$port" FABRIC_SOCKET="$sock" \
      FABRIC_DO_URL="$DO_URL" FABRIC_TICK_SECS=1 FABRIC_LEASE_SECS=30 \
      "$BIN" serve >"$out" 2>&1 &
  pids+=($!)
}

start_fabric "$DB" "$PORT" "$log/fabric.sock" "$log/fabric.log"
wait_for "$BASE/health" 60 || { bad "fabric did not start"; cat "$log/fabric.log"; exit 1; }
ok "fabric serving on $BASE"

# ----------------------------------------------------------------------- gate
if env FABRIC_DB="$DB" FABRIC_DO_URL="$DO_URL" "$BIN" gate >"$log/gate.json" 2>"$log/gate.err"; then
  ok "gate: every required dependency answered"
else
  bad "gate refused to pass"
  cat "$log/gate.err"
fi

jq_py() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

# ----------------------------------------------------------------- the task
offer=$(curl -s -X POST "$BASE/tasks" -H 'content-type: application/json' \
  -d '{"agent":"orchestrator","title":"join seven services","kind":"integration","payload":{"unit":1}}')
id=$(printf '%s' "$offer" | jq_py 'd["task"]["id"]')
expect "offer creates an offered task" "$(printf '%s' "$offer" | jq_py 'd["task"]["state"]')" "offered"
expect "offer is content addressed" "$(printf '%s' "$offer" | jq_py 'd["block_cid"][:7]')" "bafkrei"

claim=$(curl -s -X POST "$BASE/tasks/$id/claim" -H 'content-type: application/json' -d '{"agent":"agent-a"}')
expect "agent-a claims it" "$(printf '%s' "$claim" | jq_py 'd["task"]["state"]')" "claimed"

rival=$(curl -s -o "$log/rival.json" -w '%{http_code}' -X POST "$BASE/tasks/$id/claim" \
  -H 'content-type: application/json' -d '{"agent":"agent-b"}')
expect "agent-b is refused the live lease" "$rival" "409"

curl -s -X POST "$BASE/tasks/$id/start" -H 'content-type: application/json' -d '{"agent":"agent-a"}' >/dev/null
started=$(curl -s -X POST "$BASE/tasks/$id/start" -H 'content-type: application/json' -d '{"agent":"agent-a"}')
expect "a second start is refused" "$(printf '%s' "$started" | jq_py 'd["ok"]')" "False"

chat=$(curl -s -X POST "$BASE/tasks/$id/chat" -H 'content-type: application/json' \
  -d '{"agent":"agent-a","text":"claiming this one; wiring the unit"}')
text_cid=$(printf '%s' "$chat" | jq_py 'd["event"]["body"]["text_cid"]')
expect "chat text is a block" "${text_cid:0:7}" "bafkrei"
expect "chat reached the relay" "$(printf '%s' "$chat" | jq_py 'd["relay"]["ok"]')" "True"

result=$(curl -s -X POST "$BASE/tasks/$id/result" -H 'content-type: application/json' \
  -d '{"agent":"agent-a","ok":true,"result":"all seven services answered the gate"}')
expect "result completes the task" "$(printf '%s' "$result" | jq_py 'd["task"]["state"]')" "done"
result_cid=$(printf '%s' "$result" | jq_py 'd["task"]["result_cid"]')

# ------------------------------------------------------- refusals that matter
forged=$(printf '%s' "$offer" | python3 -c '
import sys,json
d=json.load(sys.stdin)["event"]
d["body"]["title"]="a title nobody signed"
print(json.dumps(d))')
code=$(curl -s -o "$log/forged.json" -w '%{http_code}' -X POST "$BASE/events" \
  -H 'content-type: application/json' -d "$forged")
expect "a doctored event is refused" "$code" "400"

late=$(curl -s -o "$log/late.json" -w '%{http_code}' -X POST "$BASE/tasks/$id/result" \
  -H 'content-type: application/json' -d '{"agent":"agent-b","ok":true}')
expect "a terminal task cannot be moved by anyone" "$late" "409"

# --------------------------------------------------------------------- blocks
body=$(curl -s "$BASE/blocks/$result_cid")
if [ "$body" = "all seven services answered the gate" ]; then
  ok "the result block reads back byte for byte"
else
  bad "result block mismatch: '$body'"
fi
if curl -sf --max-time 5 "http://127.0.0.1:8081/ipfs/$result_cid" | grep -q 'seven services'; then
  ok "the same block is retrievable from the IPFS gateway"
else
  bad "IPFS gateway did not serve $result_cid"
fi
if [ -S "$log/fabric.sock" ]; then
  unix_ok=$(curl -s --unix-socket "$log/fabric.sock" http://localhost/health | jq_py 'd["service"]')
  expect "the unix socket serves the same router" "$unix_ok" "agent-fabric"
else
  bad "no unix socket at $log/fabric.sock"
fi

# ------------------------------------------------------------- lease expiry
leased=$(curl -s -X POST "$BASE/tasks" -H 'content-type: application/json' \
  -d '{"agent":"orchestrator","title":"short lease","kind":"general"}')
lid=$(printf '%s' "$leased" | jq_py 'd["task"]["id"]')
curl -s -X POST "$BASE/tasks/$lid/claim" -H 'content-type: application/json' \
  -d '{"agent":"agent-c","lease_secs":1}' >/dev/null
state="claimed"
for _ in $(seq 1 30); do
  sleep 0.5
  state=$(curl -s "$BASE/tasks/$lid" | jq_py 'd["task"]["state"]')
  [ "$state" = "offered" ] && break
done
expect "an expired lease is re-offered" "$state" "offered"

# ------------------------------------------------------- durable object sync
if [ -n "$DO_URL" ]; then
  sync=$(curl -s -X POST "$BASE/sync")
  pushed=$(printf '%s' "$sync" | jq_py 'd["sync"]["pushed"]')
  if [ "$pushed" -gt 0 ]; then ok "pushed $pushed events to the Durable Object"; else bad "pushed nothing"; fi

  do_lines=$(curl -s "$DO_URL/all" | jq_py 'len(d["lines"])')
  local_events=$(curl -s "$BASE/health" | jq_py 'd["events"]')
  expect "the Durable Object holds every event" "$do_lines" "$local_events"

  # A second fabric with an empty database must rebuild the board from the
  # object alone. Its own push sends nothing; its pull applies everything.
  start_fabric "$DB2" "$PORT2" "$log/fabric2.sock" "$log/fabric2.log"
  if wait_for "$BASE2/health" 60; then
    curl -s -X POST "$BASE2/sync" >"$log/sync2.json"
    got=$(curl -s "$BASE2/tasks" | jq_py 'len(d["tasks"])')
    expect "a fresh fabric rebuilds every task from the object" "$got" "2"
    rebuilt=$(curl -s "$BASE2/tasks/$id" | jq_py 'd["task"]["state"]')
    expect "the rebuilt task keeps its terminal state" "$rebuilt" "done"
    chat_back=$(curl -s "$BASE2/tasks/$id/chat" | jq_py 'len(d["messages"])')
    expect "chat survives the rebuild" "$chat_back" "1"
  else
    bad "second fabric did not start"
    cat "$log/fabric2.log"
  fi
else
  echo "skip: Durable Object sync (no board)"
fi

# ----------------------------------------------------------- wasm peer
if command -v node >/dev/null 2>&1; then
  if node "$here/wasm_peer.mjs" "$BASE" "$result_cid" >"$log/wasm.log" 2>&1; then
    ok "the wasm peer agreed with the native daemon over IPFS"
    sed 's/^/     /' "$log/wasm.log"
  else
    bad "wasm peer failed"
    sed 's/^/     /' "$log/wasm.log"
  fi
else
  echo "skip: wasm peer (no node)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "e2e: all checks passed"
else
  echo "e2e: failures above; logs in $log"
  echo "--- fabric log ---"
  tail -30 "$log/fabric.log"
fi
exit "$fail"
