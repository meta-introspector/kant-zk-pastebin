// Modules
pub mod api;
pub mod archive;
pub mod archive_store;
pub mod archive_utils;
pub mod dasl;
pub mod git_mount;
pub mod handlers;
pub mod ipfs;
pub mod ipfs_daemon;
pub mod ipfs_tile;
pub mod task_attachments;
// libp2p gossipsub transport for file chunks. `libp2p_frames` is the pure
// wire format -- no libp2p dependency -- so it stays testable on its own and
// matches `web/kant-libp2p.mjs` byte for byte (scripts/frames-crosscheck.sh).
pub mod libp2p_frames;
pub mod libp2p_transport;
pub mod mcp_server;
pub mod model;
pub mod nix_skill;
pub mod plugin;
pub mod plugins;
pub mod rename;
pub mod share;
pub mod mesh;
pub mod splitter;
pub mod storage;
pub mod summary;
pub mod tagging;
pub mod tantivy_search;
pub mod view;
