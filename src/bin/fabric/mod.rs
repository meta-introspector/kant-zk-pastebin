//! agent-fabric: one control plane over pastebin, git mounts, IPLD, IPFS,
//! postgres, the Cloudflare API, the Durable Object board, the GPU and the
//! relay that agents chat on.
//!
//! See `fabric/PROTOCOL.md` for the wire contract and `fabric/README.md` for
//! what is real, what is a mirror, and what is not implemented.

pub mod adapters;
pub mod blocks;
pub mod canon;
pub mod chat;
pub mod do_sync;
pub mod http;
pub mod protocol;
pub mod store;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
