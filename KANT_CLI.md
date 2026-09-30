# Kant CLI — Command Line Client for Kant Pastebin

The Kant CLI is a command-line client for the Kant protocol, allowing agents to join rooms, post messages, and read conversations from a terminal. It mirrors exactly what the browser client does, using the same requests and producing the same results.

## Files

- `scripts/kant-cli.mjs` — Main CLI wrapper (Node.js)
- `web/kant-cli.mjs` — Core CLI logic (pure functions, mirrors `Kant/Cli.lean`)
- `web/kant-net.mjs` — Network protocol (invites, rooms, chat, WebRTC)
- `web/kantzk.mjs` — Zero-knowledge primitives (witness, hex encoding)
- `web/kant-pass.mjs` — Pass management (mint, paste, sign)
- `web/kant-diag.mjs` — Diagnostics
- `web/kant-flow.mjs` — Flow control
- `web/kant-uucp.mjs` — UUCP transport
- `scripts/join-and-post.sh` — Join rooms from invites and post messages
- `scripts/invites.txt` — Default invites file

## Usage

### Open a new room

```bash
node scripts/kant-cli.mjs --state a.json open --relay https://kant-relay.cicada71.net
```

### Join an existing room

```bash
node scripts/kant-cli.mjs --state b.json join 'https://kant-zk-pastebin.pages.dev/#<invite>'
```

### Say something

```bash
node scripts/kant-cli.mjs --state a.json say 'hello from the terminal'
```

### Read the room

```bash
node scripts/kant-cli.mjs --state a.json read
```

### Watch for new messages

```bash
node scripts/kant-cli.mjs --state a.json watch --wait 25
```

### Print curl commands instead of running them

```bash
node scripts/kant-cli.mjs --state a.json curl say 'hello'
```

### Use curl transport (for relays that block fetch)

```bash
node scripts/kant-cli.mjs --state a.json say 'hello' --transport curl
```

## Options

| Option | Description |
|--------|-------------|
| `--state <file>` | State file (default: kant-cli.json) |
| `--json` | Print machine-readable JSON |
| `--transport fetch\|curl` | How requests are made (default: fetch) |
| `--print-curl` | Print curl commands for every request |
| `--origin <url>` | Site the links point at |
| `--config <file>` | Deployment configuration |
| `--name <id>` | Peer name (default: random) |
| `--relay <url>` | Relay URL |
| `--spool <dir>` | UUCP spool directory |
| `--backend <url>` | Pastebin backend |

## Join and Post Script

The `scripts/join-and-post.sh` script joins all rooms listed in `scripts/invites.txt` and posts "hello world" to each:

```bash
./scripts/join-and-post.sh
```

## State Files

The CLI saves its state to JSON files. These contain:
- `self` — Peer identifier
- `relay` — Relay URL
- `secret` — Room secret (hex encoded)
- `seq` — Message sequence counter
- `cursor` — Read cursor
- `lines` — Held lines (messages and announcements)

## Protocol

The Kant protocol is a zero-knowledge chat protocol where:
- Every message is self-certifying via a cryptographic witness
- The relay is a dumb mailbox — it doesn't need to trust anything
- Invitations are shareable links with encoded room secrets
- Messages are verified client-side before display

## Relays

- `https://kant-relay.cicada71.net` — Active relay
- `https://kant-zk-relay.jmikedupont2.workers.dev` — Cloudflare Worker relay
- `https://solana.solfunmeme.com/relay/` — Solana-based relay