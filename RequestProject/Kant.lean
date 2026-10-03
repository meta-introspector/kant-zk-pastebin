/-
# `kant-zk-pastebin`, ported to Lean 4

This module re-exports the whole port.  The layers, bottom up:

| Module | Ports | Guarantees |
|---|---|---|
| `Kant.Bytes` | `sha2`/`hex` usage in `paste.rs` | digest width, hex round trip |
| `Kant.Dasl` | `src/dasl.rs` | `0xDA51` layout, orbifold action, merge algebra |
| `Kant.Erdfa` | escaping in `src/paste.rs` | escape/unescape round trip, no markup escape |
| `Kant.Paste` | `model.rs`, `paste.rs`, `storage.rs` | content-addressed store laws |
| `Kant.Text` | ASCII transcoding, field framing, search | round trips, unambiguous framing |
| `Kant.Feed` | the reader's view of the posts | honest rows, lossless paging, exact search |
| `Kant.Clipboard` | copy / paste / share links | self-verifying envelope round trip |
| `Kant.Meme` | memes with embedded data | payload recovery, undamaged picture |
| `Kant.Repost` | quote reposts and share cards | quotations that cannot be doctored |
| `Kant.Strip` | one share over several pictures | order-robust reassembly of the stills |
| `Kant.Sheaf` | `src/sheaf.rs` | M→H→E taxonomy, encodings ↔ Monster primes |
| `Kant.Sneakernet` | `SNEAKERNET.md` transports | 5 MB caps, order-robust reassembly |
| `Kant.Stego` | `stego.rs` channel | covert round trip, bounded distortion |
| `Kant.Sync` | IPFS/iroh/libp2p/torrent/archive.org replication | eventual consistency |
| `Kant.Rendezvous` | peer discovery, rosters, the chat QR invite | order-free gossip, one code one room |
| `Kant.Relay` | the room mailbox served by the relay | append-only log, unforgeable chat, identical transcripts |
| `Kant.SiteCard` | the deployment configuration, page URLs, share cards | config round trip, whole-URL codes, cards that read back, chat sharing |
| `Kant.InviteCard` | the invite code: whole-link payload, custom icon and text | openable link, icon and caption on the card, round trip |
| `Kant.Join` | pasting a link however it arrives | junk-tolerant joining, same room |
| `Kant.Onboarding` | screens, the camera switch, the guided first run | camera always stoppable, one link, tasks that finish |
| `Kant.PlainText` | copying a post as readable text, with optional details | plain text out, footer separable, text survives the footer |
| `Kant.Uucp` | the relay-free static sneakernet: DMs, tweets, bang paths | mailbag round trips, no news without a paste, relay redundancy, snapshot staleness |
| `Kant.Connectivity` | where clients meet, and why they did not | the relay decision, linked-or-not, a verdict per failure |
| `Kant.CardDebug` | what a pasted code is, and why two cards never connect | a card names no room, the report's own text classified, what does connect |
| `Kant.Diagnostics` | the net/error log and the shareable run | bounded ordered log, exact round trip, no secrets shared |
| `Kant.Cli` | the command-line client and the same session in `curl` | printed command is the request, CLI equals browser, two agents meet through a link |
| `Kant.Codec` | the standard proof codec and exchange layer | one canonical proof object, lossless IPDL/XML/CSV/YAML/text codecs, reconciliation |
| `Kant.Credits` | serving credits | no overdraft, credit conservation |
| `Kant.CodeMovie` | snippet playback | RLE, Gödel numbers, circuits |
| `Kant.Pipeline` | the whole flow | end-to-end self-certifying round trip |
| `Kant.Demo` | runnable examples | `#guard`-checked executions |
-/
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Feed
import RequestProject.Kant.Meme
import RequestProject.Kant.Repost
import RequestProject.Kant.Strip
import RequestProject.Kant.Sheaf
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego
import RequestProject.Kant.Sync
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.Relay
import RequestProject.Kant.SiteCard
import RequestProject.Kant.InviteCard
import RequestProject.Kant.Join
import RequestProject.Kant.Onboarding
import RequestProject.Kant.PlainText
import RequestProject.Kant.Uucp
import RequestProject.Kant.Connectivity
import RequestProject.Kant.Diagnostics
import RequestProject.Kant.CardDebug
import RequestProject.Kant.Credits
import RequestProject.Kant.CodeMovie
import RequestProject.Kant.Pipeline
import RequestProject.Kant.Demo
import RequestProject.Kant.ShareLog
import RequestProject.Kant.Handoff
import RequestProject.Kant.Cli
import RequestProject.Kant.Codec
import RequestProject.Kant.Domain
