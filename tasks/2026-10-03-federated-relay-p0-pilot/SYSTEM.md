# Task
- **Name:** federated-relay-p0-pilot
- **ID:** FR-1
- **Priority:** P1
- **Security Level:** S2 (medium) — worker code, local dev only until operator go
- **Area:** cloudflare-workers, protocol, federated-relay
- **Recurring:** No
- **Tags:** cloudflare-workers, protocol, federated-relay

# Role
Protocol engineer

# Domain
Cloudflare Durable Objects (hibernation), DAG-CBOR, Ed25519 line credentials, tracker tree

## Objective
Phase-1 pilot of the Federated P2P Relay spec v0.1: GatewayDO + MailboxDO
prototype with signed DAG-CBOR envelopes, idempotency, bounded mailboxes,
budget telemetry. Standalone protocol (future successor to pastebin relay +
OTC desk) — NOT a retrofit. Node client first, Rust after.

## Binding operator directives
1. **Nix for all deps + system-manager** (2026-10-03). wrangler = nixpkgs
   4.62.0 from PATH (system-manager env or `nix develop` from the tracker
   flake); nodejs = nix 24. miniflare/node_modules wrangler 3.114 BANNED.
   Future local units → `tracker-services.nix` pattern; secrets → sops /run
   EnvironmentFile model.
2. **Local-first:** zero Cloudflare usage. `wrangler deploy` only after an
   explicit operator go at the final checkpoint.

## Location
Worktree `/mnt/data1/twitterstorm/tracker/worktrees/federated-relay-p0`
(branch `federated-relay-p0`). Claim: `claim-federated-relay-p0.md`.
Plan: `/home/mdupont/.qoder/plans/ember-prairie-ibis.md`.

## Checkpoints
| Step | What | State |
|---|---|---|
| S2 | hibernation spike: nix workerd PASS (attachment survival, getWebSockets, close-drop). API ground truth: hibernation on DurableObjectState, accept(ws, tags[]), serializeAttachment before accept. Commit `ca5f67ba` | ✅ done 2026-10-03 |
| 1 | frames.mjs (DAG-CBOR via lean/web/core.js, pre-decode size gates 64KiB/16KiB, per-kind key whitelist) + vectors.test.mjs golden hex vs @ipld/dag-cbor | ✅ done 2026-10-03 — **S1 PASSED: byte-identical to @ipld/dag-cbor 10.0.1 on all 7 shapes**; golden committed `tests/fixtures/vectors.json`, gen once via `tests/gen-vectors.mjs` (nix node, zero runtime node_modules). Commit `d27f7953` |
| 2 | auth.mjs: reuse verifyLine/keyIdFromPublicKey from lib/peer-protocol.mjs + NEW checkCred (expiry, aud:"relay:<net>", revocation — peer-protocol does NOT check these; PB-22 lesson) | ✅ done 2026-10-03 — checkMembership/checkEnvelopeTimes/rosterIndex, 5/5 real-Ed25519 tests green incl. stranger-self-sign refusal. Membership credential carries authority-signed key_id+public_key (deviation logged in claim) |
| 3 | gateway-do.mjs: 4-scalar attachment, HELLO-first, epoch replace 4001, SQLite envelope table with UNIQUE(origin,from,message_id) idempotent INSERT OR IGNORE, rate gate no timers. DO never dials outward | open |
| 4 | mailbox-do.mjs: TTL sweep on-write, 100 msgs/2MiB → explicit REJECT overflow, ACK cursor listAfter(50) | open |
| 5 | budget.mjs: DO-backed /budget (NOT a /health blind spot — PB-19), ≥70% shed, ≥100% refuse upgrade 4002. Kill-switch here | open |
| 6 | relay.test.mjs: forged/expired/wrong-aud/revoked→4003, oversize pre-decode, dup idempotency, overflow, disconnect epoch+1 cursor resume, burst 6th, two-peer store-and-forward E2E | open |
| 7 | wrangler.toml: classes in new_sqlite_classes migration v0, observability enabled=false, preview_urls=false | open |

Harness for all tests: spawn `wrangler dev --local` (PATH, nix) on scanned
free port 8890–8899 — 8790–8796 leased by other sessions/services.

## Proof
`node tests/spike-wrangler.mjs` → SPIKE-PASS. Each later checkpoint: its test
file green + report; final checkpoint STOP → operator go required before ANY
Cloudflare deploy. Proof block via shmem query2proof `proof/tasks/federated-relay-p0/`.
