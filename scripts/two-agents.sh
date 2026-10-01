#!/bin/sh
# Two agents find each other from a terminal, and every step is curl.
#
#   sh scripts/two-agents.sh            # uses a free-ish port and a temp dir
#   PORT=8787 sh scripts/two-agents.sh
#
# The page is static: nothing here asks the host for anything but the site
# itself.  The one thing the two agents have to exchange is the link, and it
# goes through whatever channel they already share — Telegram, Discord, a
# tweet, a text message.  Here the "chat window" is a shell variable.
#
# Every request either *is* a curl command typed out in full, or is made by
# the curl binary (`--transport curl --print-curl` prints the command it ran).
# The rules being followed are proved in RequestProject/Kant/Cli.lean.

set -eu

PORT=${PORT:-8787}
BASE="http://127.0.0.1:${PORT}"
DIR=$(mktemp -d)
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
K="node ${ROOT}/scripts/kant-cli.mjs"
PASSDB="${DIR}/passes.sqlite"          # hermetic: never touch live state

cleanup() {
  [ -n "${RELAY:-}" ] && kill "${RELAY}" 2>/dev/null || true
  rm -rf "${DIR}"
}
trap cleanup EXIT

say() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

say "0. a relay, and the static site, on this machine"
node "${ROOT}/server/relay.mjs" --port "${PORT}" --static "${ROOT}/web" --pass-db "${PASSDB}" --quiet &
RELAY=$!
i=0
until curl -sS "${BASE}/health" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "${i}" -gt 50 ] && { echo "the relay never came up"; exit 1; }
  sleep 0.2
done
echo "$ curl -sS ${BASE}/health"
curl -sS "${BASE}/health"; echo

say "1. agent A opens a room"
${K} --state "${DIR}/a.json" --name agent-a --origin "${BASE}/" open --relay "${BASE}"
LINK=$(${K} --state "${DIR}/a.json" --origin "${BASE}/" link)
ROOM=$(${K} --state "${DIR}/a.json" room)

say "2. A sends the link to B through some other channel"
echo "the message A types into the chat:"
echo "    hey — come in here: ${LINK}"
echo
echo "the host is only ever asked for:  $(${K} --state "${DIR}/a.json" --origin "${BASE}/" --json link | sed -n 's/.*\"page\": \"\(.*\)\",\?/\1/p')"
echo "the room is only in the fragment: ${ROOM}"

say "3. B pastes the message and joins"
${K} --state "${DIR}/b.json" --name agent-b join "hey — come in here: ${LINK} .
see you in a sec"
ROOMB=$(${K} --state "${DIR}/b.json" room)
[ "${ROOM}" = "${ROOMB}" ] || { echo "FAIL: the two agents are in different rooms"; exit 1; }
echo "both agents are in room ${ROOM}"

say "4. A says something — by typing out the curl command"
set -f                                   # a query string has a '?' in it
CMD=$(${K} --state "${DIR}/a.json" curl say 'hello from agent A')
echo "\$ ${CMD}"
eval "${CMD}"; echo

say "5. B reads the room — with curl, and then as the client"
BCMD=$(${K} --state "${DIR}/b.json" curl read)
echo "\$ ${BCMD}"
eval "${BCMD}"; echo
${K} --state "${DIR}/b.json" --transport curl --print-curl read

say "6. B answers, and A reads it"
${K} --state "${DIR}/b.json" --transport curl --print-curl say 'hello back from agent B'
${K} --state "${DIR}/a.json" --transport curl --print-curl read

say "7. do both agents display the same conversation?"
A=$(${K} --state "${DIR}/a.json" read)
B=$(${K} --state "${DIR}/b.json" read)
if [ "${A}" = "${B}" ]; then
  echo "yes:"
  echo "${A}"
else
  echo "FAIL: they differ"
  echo "A: ${A}"
  echo "B: ${B}"
  exit 1
fi

say "done — two terminals, one relay, one link, and nothing but curl"
