# The rendezvous relay

An append-only mailbox, one log per room.  It is what lets two browsers that
have never met find each other, and it is deliberately the least trusted piece
in the system: it never parses a line, never learns a room secret, and cannot
make a client believe anything a client cannot check for itself.

Its semantics are the `Server` of `RequestProject/Kant/Relay.lean` — `post`,
`lines`, `fetch` — and the properties that matter (`fetch_since`,
`poll_lossless`, `relay_cannot_forge`, `clients_agree`, `discover_via_relay`)
are proved there.  See `docs/DISCOVERY-AND-CHAT.md` for the whole picture.

## Two deployments, one protocol

| file | where it runs | notes |
|---|---|---|
| `relay.mjs` | any Linux box with Node ≥ 18 | zero dependencies, HTTP + WebSocket, can also serve `web/` |
| `worker.js` | Cloudflare Workers | one Durable Object per room, log persisted, native WebSockets |

```
GET  /health                            -> { ok, name: "kant-zk-relay", version }
POST /room/{room}    body: lines        -> { ok, cursor, accepted }
GET  /room/{room}?cursor=N[&wait=S]     -> { ok, cursor, lines, truncated }
WS   /ws/{room}?cursor=N                -> pushes { ok, cursor, lines }
```

`cursor` is the absolute length of the room's log.  Poll with the cursor you
were last given and you get exactly what has been posted since; poll from `0`
and you catch up on the whole room.

## Linux

```sh
node server/relay.mjs --port 8787 --host 127.0.0.1 --static web
```

Options: `--port`, `--host`, `--static <dir>`, `--origin <cors origin>`,
`--max-line`, `--max-lines`, `--max-body`, `--room-ttl` (ms).  Environment
variables `PORT`, `HOST`, `KANT_STATIC` and `KANT_ORIGIN` work too.

Permanent install: `kant-relay.service` (systemd, hardened, memory capped) and
`nginx.conf.example` (TLS termination and WebSocket upgrade).

```sh
sudo useradd --system --home /opt/kant-zk-pastebin kantzk
sudo cp server/kant-relay.service /etc/systemd/system/
sudo systemctl enable --now kant-relay
```

## Cloudflare

```sh
cd server && npx wrangler deploy
```

`wrangler.toml` declares the `Room` Durable Object.  Uncomment the `[assets]`
block to have Cloudflare serve `web/` from the same origin, which removes CORS
from the picture entirely.

## Limits

Both implementations reject a line over 256 KB, keep the most recent 4096 lines
per room, and tell a client whose cursor has been trimmed away (`truncated:
true`) rather than silently skipping lines.  The Node relay also forgets a room
after six hours of silence.  These are memory guards, and they are the only
places where a running relay does less than the unbounded log proved in Lean.

## Tests

`node web/net-test.mjs` starts this relay on an ephemeral port and runs two
clients through it: invitation, discovery, chat over polling and over a
WebSocket, a late joiner catching up, a hostile relay's forged line being
refused, and identical transcripts from different routes.
