# Plugin Composition Map

## App Routes → Plugin

| Route | Handler | Current Module | Plugin | Bare Repo | Status |
|-------|---------|---------------|--------|-----------|--------|
| `POST /paste` | create_paste | storage, tagging, ipfs, sheaf, dasl | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /paste/{id}` | get_paste | storage | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /raw/{id}` | get_raw | storage | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /browse` | browse | storage, tagging | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /preview/{id}` | preview_paste | view, tagging | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `POST /upgrade` | upgrade_pastes | storage, tagging, sheaf | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /thread/{id}` | get_thread | storage | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `POST /upload` | upload_file | storage, ipfs | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /file/{id}` | get_file | storage | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /ipfs/{cid}` | ipfs_proxy | ipfs | zos-ipfs | ❌ needs new repo | 🔲 todo |
| `GET /gallery` | gallery | storage, ipfs | zos-pastebin | zos-pastebin.git | ✅ spun off |
| `GET /gallery/img/{qid}` | gallery_image | ipfs | zos-ipfs | ❌ needs new repo | 🔲 todo |
| `POST /plugin/{name}/{id}` | run_plugin | plugin registry | zos-plugin-host | ❌ needs new repo | 🔲 todo |
| `GET /plugins` | list_plugins | plugin registry | zos-plugin-host | ❌ needs new repo | 🔲 todo |
| `GET /stego` | stego_dashboard | erdfa-clean wasm | erdfa-stego | ❌ needs new repo | 🔲 todo |
| `GET /wasm` | wasm_frontend | pastebin-wasm | zos-pastebin-wasm | ❌ needs new repo | 🔲 todo |
| `GET /swagger-ui` | openapi | utoipa | (inline, keep) | — | ✅ keep |
| `GET /` | index | view | zos-pastebin | zos-pastebin.git | ✅ spun off |

## Internal Modules → Plugin

| Module | Plugin | Status |
|--------|--------|--------|
| `src/dasl.rs` | erdfa-dasl | ✅ spun off |
| `src/sheaf.rs` | erdfa-sheaf | ✅ spun off |
| `src/tagging.rs` | erdfa-tagging | 🔲 todo |
| `src/ipfs.rs` | zos-ipfs | 🔲 todo |
| `src/storage.rs` | zos-pastebin | ✅ spun off |
| `src/plugin.rs` | zos-plugin-host | 🔲 todo (trait lives here) |
| `src/plugins/screenshot.rs` | zos-plugin-headless-browser | ✅ bare exists |
| `src/bin/freeze_chats.rs` | erdfa-freeze-chats | 🔲 todo |
| `src/bin/reindex.rs` | zos-reindex | 🔲 todo |

## Existing erdfa-plugin Bare Repos (/mnt/data1/git/solana.solfunmeme/)

| Bare Repo | Maps To |
|-----------|---------|
| `erdfa-plugins.git` | workspace with all erdfa plugins (main) |
| `erdfa-plugin-ipfs.git` | `src/ipfs.rs` |
| `erdfa-plugin-sheaf.git` | `src/sheaf.rs` |
| `erdfa-plugin-ingest.git` | `src/bin/reindex.rs` |
| `erdfa-plugin-distribute.git` | distribution/federation |
| `erdfa-plugin-federation.git` | federation |
| `erdfa-plugin-mixer.git` | mixer |
| `erdfa-plugin-render.git` | view/render |
| `erdfa-core.git` | core types |

Individual plugins in `erdfa-plugins.git/main`:
`dasl`, `sheaf`, `stego`, `zkperf`, `hecke`, `maass`, `monster`, `cft`, `langlands`, `virasoro`, `privacy`, `morse`, `bott`, `clifford`, `fourier`, `fractran`, `galois`, `golay`, `leech`, `paxos`, `ramanujan`, `time-reversal`, `umbral`, `voronoi`, `zkp`
