# Plugin Refactor Plan

Goal: refactor all modules as erdfa / zkperf / zos plugins.

## Current Modules → Target Plugin

| Module | File | Target Plugin |
|--------|------|---------------|
| Paste storage | `src/storage.rs` | `zos` — filesystem/spool plugin |
| IPFS integration | `src/ipfs.rs` | `zos` — IPFS/content-address plugin |
| Tagging | `src/tagging.rs` | `erdfa` — RDF annotation plugin |
| Sheaf coordinates | `src/sheaf.rs` | `erdfa` — sheaf/topology plugin |
| DASL queries | `src/dasl.rs` | `erdfa` — query/search plugin |
| Plugin host | `src/plugin.rs`, `src/plugins/` | `zos` — plugin loader |
| Screenshot | `src/plugins/screenshot.rs` | `zos` — renderer plugin |
| freeze-chats | `src/bin/freeze_chats.rs` | `erdfa` — static site generator plugin |
| reindex | `src/bin/reindex.rs` | `zos` — indexer plugin |
| zkperf submodule | `zkperf/` | `zkperf` — ZK proof plugin |
| erdfa-publish | `erdfa-canonical/bindings/rust` | `erdfa` — publish/canonical plugin |

## Branches Status

| Branch | Status | Action |
|--------|--------|--------|
| `feature/kant-kategorie` | ✅ current, nix build passing | keep, base for all work |
| `main` | already merged into current | can be fast-forwarded |
| `fix/sheaf-coordinates-and-hostname` | rebased, only adds crawler-workspace submodule | spin off or drop |
| `codex/fix-public-access-commands` | no unique commits | drop |
| `pr1` | no unique commits | drop |

## Next Steps

1. Extract `storage.rs` + `ipfs.rs` → `zos-plugin-pastebin` crate (path in workspace)
2. Extract `tagging.rs` + `sheaf.rs` + `dasl.rs` → `erdfa-pastebin` crate
3. Extract `zkperf` integration → `zkperf-plugin` crate
4. `main.rs` becomes thin plugin host wiring them together via `plugin.toml`
