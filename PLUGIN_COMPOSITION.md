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

## Next Plugins to Create

1. `erdfa-tagging` — tagging.rs (RDF annotation)
2. `zos-ipfs` — ipfs.rs (content addressing, proxy)
3. `zos-plugin-host` — plugin.rs trait + registry
4. `erdfa-freeze-chats` — freeze_chats.rs
