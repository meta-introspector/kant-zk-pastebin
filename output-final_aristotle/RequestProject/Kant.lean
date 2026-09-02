/-
# `kant-zk-pastebin`, ported to Lean 4

This module re-exports the whole port.  The layers, bottom up:

| Module | Ports | Guarantees |
|---|---|---|
| `Kant.Bytes` | `sha2`/`hex` usage in `paste.rs` | digest width, hex round trip |
| `Kant.Dasl` | `src/dasl.rs` | `0xDA51` layout, orbifold action, merge algebra |
| `Kant.Erdfa` | escaping in `src/paste.rs` | escape/unescape round trip, no markup escape |
| `Kant.Paste` | `model.rs`, `paste.rs`, `storage.rs` | content-addressed store laws |
| `Kant.Sheaf` | `src/sheaf.rs` | M→H→E taxonomy, encodings ↔ Monster primes |
| `Kant.Sneakernet` | `SNEAKERNET.md` transports | 5 MB caps, order-robust reassembly |
| `Kant.Stego` | `stego.rs` channel | covert round trip, bounded distortion |
| `Kant.Sync` | IPFS/iroh/libp2p/torrent/archive.org replication | eventual consistency |
| `Kant.Credits` | serving credits | no overdraft, credit conservation |
| `Kant.CodeMovie` | snippet playback | RLE, Gödel numbers, circuits |
| `Kant.Pipeline` | the whole flow | end-to-end self-certifying round trip |
| `Kant.Demo` | runnable examples | `#guard`-checked executions |
-/
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Sheaf
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego
import RequestProject.Kant.Sync
import RequestProject.Kant.Credits
import RequestProject.Kant.CodeMovie
import RequestProject.Kant.Pipeline
import RequestProject.Kant.Demo
