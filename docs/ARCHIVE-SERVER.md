# The kant-zk archive server

Every service gets a Cloudflare p2p twin.  The pastebin's twins are:

| twin | where | what it is |
|---|---|---|
| relay | `https://kant-zk-relay.jmikedupont2.workers.dev` (CF Worker, Durable Objects) | the rendezvous mailbox |
| relay | `https://solana.solfunmeme.com/relay` (node, `kant-relay.service` :8787) | same protocol, self-hosted |
| pastebin | `https://solana.solfunmeme.com/pastebin` (`kant-pastebin.service` :8090) | content-addressed paste store |
| archive | `https://kant-zk-pastebin.pages.dev/archive/` (CF Pages, static) | folded room transcripts |

## How the archive pipeline flows

```
browser/agent ──say──▶ relay (either twin)
                        │
          kant-zk-forward.service: local relay ──▶ CF relay (mirror)
                        │
          kant-zk-archive.service: room ──▶ pastebin thread (reply chain)
                        │
          kant-zk-publisher.service: spool ──fold──▶ static snapshot ──▶ CF Pages /archive/
```

* **forward** (`server/forward.mjs`) — a client that re-posts every line
  from the local relay to the CF relay.  Lines carry their own witness,
  so the CF twin accepts them without knowing the bridge exists.
* **archive** (`server/archive.mjs`) — a client that joins each room in
  `/var/lib/kant-zk/rooms/*.json` and, whenever the transcript grows,
  posts the whole transcript to the pastebin as a reply-chained thread.
  Content-dedup keeps re-posts idempotent.
* **publisher** (`server/publisher.mjs`) — the archive server.  Every
  5 minutes it reads the pastebin spool (`/var/spool/uucp/pastebin`),
  folds all replies of a kant-zk room into one page (the latest reply is
  the full transcript), writes `index.html` + `thread/<room8>.html` +
  `archive.json` + `manifest.json`, and pushes the whole site
  (web/ root + snapshot under `archive/`) to CF Pages.

## Using it

**Join a room from a browser:** open the invite link (the
`#kzinvite:…` fragment carries the relay + secret; the relay never
learns the secret).  Everything you say is archived automatically.

**Join from a terminal / agent** (same requests as the browser, per
`kant-cli.mjs`):

```sh
cd ~/projects/pastebin-lean
node --input-type=module -e '
import * as Net from "./web/kant-net.mjs";
const invite = "<paste the invite link here>";
const node = new Net.KantNode({ peer: "my-agent", relay: "https://solana.solfunmeme.com/relay" });
node.joinInvite(invite);
await node.say("hello from the terminal");
'
```

**Read the archive:** `https://kant-zk-pastebin.pages.dev/archive/` —
front page lists rooms, `thread/<room8>.html` is the folded transcript
plus the reply chain with witnesses and CIDs.  `archive.json` is the
machine-readable fold.  Or the live pastebin:
`https://solana.solfunmeme.com/pastebin/threads`.

**Add a room to the archive:** drop a `<name>.json` into
`/var/lib/kant-zk/rooms/`:

```json
{
  "name": "my-room",
  "invite": "https://solana.solfunmeme.com/relay/#kzinvite:<relay-hex>:<secret-hex>:<peer>",
  "relay": "https://solana.solfunmeme.com/relay",
  "backend": "https://solana.solfunmeme.com/pastebin"
}
```

`kant-zk-archive` picks it up on restart
(`sudo systemctl restart kant-zk-archive`).

**Room name derivation:** the room is the witness (salted FNV-1a
digest, *not* sha256) of the secret — `kantzk.mjs` `witness()`.  The
relay only ever sees that digest.

## Services

| unit | role |
|---|---|
| `kant-pastebin.service` | pastebin :8090 |
| `kant-relay.service` | node relay :8787, served at `https://solana.solfunmeme.com/relay/` |
| `kant-zk-forward.service` | local relay → CF relay mirror |
| `kant-zk-archive.service` | rooms → pastebin threads |
| `kant-zk-publisher.service` | spool → fold → CF Pages `/archive/` (every 300s) |

CF Worker deploy: `cd server && npx wrangler deploy` (token in
`~/.cloudflare`).  Pages + snapshot: `node server/publisher.mjs --once
--pages-deploy`.

## Trust

The relay never parses a line and never learns a room secret; a
compromised relay can drop lines but cannot forge them — every client
re-checks each line's witness (`Kant.Relay.parseMsg`).  The archive
only stores what every peer can already display.  The CF snapshot is
static: it can only go stale, never lie about what it contains
(witnesses included).
