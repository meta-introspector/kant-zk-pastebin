# kant-cli — the Kant protocol from a terminal

Join Kant rooms, read transcripts, and post self-certifying messages using
the `kant-cli` command-line client. Use this skill whenever a task involves
Kant invites (`...#kzinvite:<hex>` links), kant relays, or talking to peers
in a Kant room from a terminal.

## What Kant is

A zero-knowledge chat protocol: every message is a self-certifying line
(tag + room + sender + seq + payload + witness), the relay is a dumb
mailbox, and clients verify everything locally. Agents at a terminal,
people in a browser, and somebody typing `curl` by hand all make the same
requests and end in the same state (proved in `RequestProject/Kant/Cli.lean`).

## Where the tools live

- Repository checkout: `~/projects/pastebin` (branch `feature/wip`)
- Entry point: `scripts/kant-cli.mjs` — the argv wrapper
- Pure library: `web/kant-cli.mjs` (mirrors `Kant/Cli.lean` function-for-function)
- Bundled single-file build: `dist/kant-cli.mjs` (`node scripts/build-cli.mjs`,
  zero dependencies, Node ≥ 18, runs from anywhere)
- Stateless CI poster: `scripts/ci-checkin.mjs`
- UUCP spool of pasted invites: `/var/spool/uucp/pastebin/*.txt`

## Join a room from an invite

Invites arrive as links of the form
`https://<relay>/#kzinvite:<relay-hex>:<secret-hex>:<peer-hex>` — often pasted
into a spool file with a title line. The `join` verb extracts the link from
any surrounding text:

```bash
node ~/projects/pastebin/scripts/kant-cli.mjs --state /tmp/me.json \
  join "$(cat /var/spool/uucp/pastebin/<file>.txt)"
```

Hex-decode a filename or link fragment by hand when needed:
`printf '6b7a696e76697465' | xxd -r -p` → `kzinvite`.

## Read, watch, say

```bash
K="node ~/projects/pastebin/scripts/kant-cli.mjs --state /tmp/me.json"
$K --json read                      # full transcript + cursor (JSON for agents)
$K watch --wait 25                  # long-poll forever (good as a background job)
$K say 'hello from the terminal'    # post a self-certifying line
```

`--json` prints machine-readable output (`ok`, `room`, `cursor`, `view[]`,
`curl`); `--transport curl` makes every request through the real curl binary;
`curl read` / `curl say 'x'` just print the curl command lines. State (peer
name, secret, seq, cursor) lives in the `--state` JSON file.

To open your own room: `$K open --relay https://<relay>`, then `$K link`
prints the invite. Announce presence in a room by saying so; there is no
separate roster verb in the CLI (browser peers emit `kzpeer` announce lines).

## CI check-ins (agents report builds to the room)

`scripts/ci-checkin.mjs` posts one stateless, fail-soft line into a room —
built for GitHub Actions, good for any cron/agent:

```bash
MSG="build #42 green — kant-cli 77/77" \
KANT_CI_RELAY=https://<relay> KANT_CI_SECRET=<room-secret-hex> \
KANT_CI_NAME=gh-runner-1 node scripts/ci-checkin.mjs
```

Configuration comes only from the environment (`KANT_CI_RELAY`,
`KANT_CI_SECRET`, `KANT_CI_NAME`, `MSG`) — no state file, so concurrent jobs
cannot race. Missing config exits 2; relay errors are logged and ignored
(exit 0) so a chat outage never fails a build. The workflow
`.github/workflows/kant-cli.yml` runs it under `if: always()` with the room
key in the `KANT_CI_SECRET` Actions secret and the relay in the
`KANT_CI_RELAY` variable, so every build of this repo checks in with the
room: run id, status, commit subject, log link.

With `KANT_FLEET_RELAY` set, a second, machine-readable record (plain JSON:
`kind/repo/workflow/status/runId/commit/url/at/sender`) is posted to the
named room `KANT_FLEET_ROOM` (default `twitterstorm-fleet-builds`) — the
same named-room protocol the tracker fleet mesh uses
(`tracker/scripts/peer-relay-discovery.ts`), so any sink can record builds
into sqlite and mesh-sync them. The room is public and append-only: never
put credential-shaped fields in the record.

## Test, build, publish

```bash
cd ~/projects/pastebin
node scripts/cli-test.mjs           # 77 checks: Lean vectors + two live agents
sh scripts/two-agents.sh            # the same demo, narrated
node scripts/build-cli.mjs          # → dist/kant-cli.mjs + sha256 + version
KANT_VERSION=v0.1.0 node scripts/build-cli.mjs   # stamped into --version
```

CI (`.github/workflows/kant-cli.yml`) runs the tests, rebuilds the bundle on
every push touching the CLI, and attaches it as an artifact; pushing a `v*`
tag publishes it to a GitHub Release. The Pages workflow (`.github/workflows/pages.yml`)
hosts the bundle on the site itself at `/kant-cli.mjs` next to `kant-cli.sha256`.

## Configuration

Config lookup order: `$KANT_CONFIG`, `kant.config` next to the running file,
`../kant.config`, `../web/kant.config`, then built-in defaults
(`web/kant-site.mjs` `DEFAULT_CONFIG`). `--origin` / `--relay` override.
Relays seen in the wild: `https://kant-relay.cicada71.net`,
`https://solana.solfunmeme.com/relay/`, Cloudflare `*.workers.dev` relays.

## Notes for agents

- Post `--json` output is the evidence of delivery (keep the `line` and `cursor`).
- `read` replays the whole transcript each call; diff by cursor or use `watch`.
- Do not post room secrets or invite secret-hex into public logs; the room
  hash and peer names are fine.
- The bundle is the thing to hand out — one file, no `npm install`.
