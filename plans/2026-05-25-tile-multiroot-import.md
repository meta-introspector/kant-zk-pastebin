# Tile+MultiRoot Import — Development Plan

**Date:** 2026-05-25
**Branch:** `main-clean`
**Status:** In progress — tile system working (zos-circuit, org), multi-root reindex being built

---

## Current Architecture

```
kant-pastebin (main binary)
  ├── erdfa-publish      (compile-time dep, via combinedSrc)
  ├── vendor/rust-ipfs   (compile-time dep, via combinedSrc)
  ├── TILES_DIR          (colon-separated Nix store paths)
  │   ├── zos-circuit-tile (.so)   — built standalone, loaded at runtime
  │   └── org-tile (.so)           — built standalone, loaded at runtime
  │
  ├── PluginRegistry     (HashMap<String, Box<dyn Plugin>>)
  │   ├── screenshot     (built-in static)
  │   ├── zos_circuit_tile (FFI → .so)
  │   └── org_tile       (FFI → .so)
  │
  ├── Reindex bins
  │   ├── reindex        (single-root, existing)
  │   └── multi_reindex  (multi-root, WIP — reads config file)
  │
  └── Storage
      ├── SQLite (paste data)
      └── PasteIndex (id, root, title, tags, mime, ...)
```

---

## Phase 1: Complete Multi-Root Import (IMMEDIATE)

### Objective
The `multi_reindex` binary walks multiple filesystem roots and imports org/text files as pastebin entries, tagging them with their origin root for search/filter.

### Files to create/modify

| File | Action | Description |
|---|---|---|
| `src/bin/multi_reindex.rs` | CREATE | Walks dirs, parses `.org`/`.md` files, imports via API |
| `src/model.rs` | MODIFY | Add `root: String` field to `PasteIndex` |
| `src/handlers.rs` | MODIFY | Filter/search by root in browse view |
| `src/view.rs` | MODIFY | Show root badge in paste listing |
| `Cargo.toml` | MODIFY | Add `regex-lite` dep + `[[bin]]` entry |
| `flake.nix` | MODIFY | Register `multi-reindex` as flake app + pass config path |

### Config Format (`roots.toml`)
```toml
[[roots]]
path = "/mnt/data1/time-2026"
label = "time-repo"
glob = "**/*.org"

[[roots]]
path = "/mnt/data1/docs"
label = "docs"
glob = "**/*.{md,txt}"
```

### Workflow
1. `multi_reindex` reads `roots.toml`
2. For each root: walk `glob`, read each file
3. Extract title (org `#+TITLE:` or filename), tags (from `#+TAGS:` or auto_tag)
4. POST each file to the pastebin API
5. Set `root` field = root label
6. Browse at `/browse?root=time-repo` filters by root

### Success Criteria
- [ ] `multi_reindex --config roots.toml` imports all org files from a directory tree
- [ ] Each paste shows its origin root in the view
- [ ] Browse/search by root works
- [ ] `nix build` passes with the bin target

---

## Phase 2: Tile Plugin Enhancement (WEEK A)

### Objective
Standardize tile development so any Rust crate can be wrapped as a `.so` tile with 3 functions, built by its own flake, loaded at runtime.

### Tile Contract (already established)
```c
// Standard C-ABI — every tile exports these:
int32_t tile_ping(void);                                          // health check
char*   tile_render(const char* input_json);                      // JSON in, JSON out
void    tile_free(char* ptr);                                     // free result
char*   tile_render_json(const char* input_json);                 // batch JSON I/O
```

### Tile Template (`tiles/_template/`)
```toml
[package]
name = "my-tile"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

```rust
// src/lib.rs template
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn tile_ping() -> i32 { 1 }

#[no_mangle]
pub extern "C" fn tile_render(input: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input) }.to_str().unwrap_or("");
    let result = serde_json::json!({ "html": format!("<p>Processed: {}</p>", input_str) });
    CString::new(result.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn tile_free(ptr: *mut c_char) {
    if !ptr.is_null() { unsafe { drop(CString::from_raw(ptr)); } }
}

#[no_mangle]
pub extern "C" fn tile_render_json(input: *const c_char) -> *mut c_char {
    tile_render(input)  // same for simple tiles
}
```

### Tiles to Build (priority order)

| # | Tile | Deps | Purpose |
|---|---|---|---|
| 1 | `org-tile` | `orgize` | ✅ Built — org → HTML |
| 2 | `zos-circuit-tile` | zos-circuit-optimizer + erdfa-dasl + zkperf | ✅ Built — ZK circuit rendering |
| 3 | `plantuml-tile` | `plantuml` CLI | PlantUML → SVG |
| 4 | `midi-player-tile` | `midly` | MIDI → Web Audio player |
| 5 | `flamegraph-tile` | `inferno` | Flamegraph stacks → SVG |
| 6 | `dasl-testing-tile` | `cid`, `dag-cbor` | DAG-CBOR test cards |
| 7 | `code-highlight-tile` | `syntect` | Source code → syntax-highlighted HTML |
| 8 | `sheaf-tile` | `serde_cbor` | Sheaf logic → RDFa graph |
| 9 | `erdfa-tile` | `serde_cbor` | Erdfa → HTML/DOM |
| 10 | `diff-tile` | `similar` | Unified diff → colored HTML |
| 11 | `chart-tile` | `plotters` | Data → SVG chart |
| 12 | `tikz-tile` | `tikz` CLI | LaTeX TikZ → SVG |
| 13 | `mermaid-tile` | `mermaid` CLI | Mermaid → SVG |

### Build System
Each tile lives in `tiles/<name>/` and has:
- `Cargo.toml` (cdylib)
- `src/lib.rs` (exports 4 standard C-ABI functions)
- `Cargo.lock` (generated)
- `flake.nix` (references `combinedSrc` + `buildRustPackage`)

### Registration
In `flake.nix`, each tile adds:
```nix
tile-<name>-src = {
  url = "git+file:///mnt/data1/git/github.com/<org>/<repo>.git?rev=<hash>";
  flake = false;
};
```

---

## Phase 3: Time-Repo Blog Pipeline (WEEK B)

### Objective
The time repo (`~/2026/`) contains dated `.org` files with notes, code blocks, and session logs. The pipeline:

1. Scans the repo via `multi_reindex`
2. Each `.org` file → pastebin paste (title = headline, content = body, root = date)
3. In the paste view, `#+BEGIN_SRC` blocks become tile invocation buttons
4. Clicking a block invokes the matching tile (by language tag) and renders the output inline

### Tile Invocation (org-babel style)
```
#+tile: zos-circuit-tile
#+BEGIN_SRC json
{"circuit_opcodes": ["ADD", "MUL"]}
#+END_SRC

#+tile: plantuml-tile
#+BEGIN_SRC plantuml
@startuml
Alice -> Bob: hello
@enduml
#+END_SRC
```

### Handler Flow
```
GET /paste/{id}
  → render paste content
  → detect #+tile: / #+BEGIN_SRC blocks
  → for each tile block:
      call tile.execute(content)
      insert result HTML inline
  → return rendered page
```

### DASL DAG-CBOR Pathway
Each tile call is also recorded as a DAG-CBOR node:
```json
{
  "tile": "org-tile",
  "input": { "type": "org", "content": "..." },
  "output": { "html": "..." },
  "cid": "bafy...",
  "timestamp": "2026-05-25T..."
}
```

This creates an audit trail: every rendered paste is linked to the tile that processed it and the input that produced the output.

---

## Phase 4: Org-Mode Compilation (WEEK C)

### Objective
Full org-mode compilation via the Emacs engine embedded in Nix:
- `emacs-ng`: Emacs with Deno runtime for JavaScript interop
- `org-rs`: Native Rust org-mode parser (community fork)
- `orgize`: Feature-rich Rust org parser (already in use)

### Pipeline
```
.org file
  → orgize (parse to AST)
  → tile pipeline (run #+BEGIN_SRC blocks through matching tiles)
  → render to HTML with RDFa annotations
  → store as pastebin post (with tags, root, dates)
  → optionally re-export as .org with #+RESULTS filled in
```

### Nix Wrapping
```nix
# flake.nix app
apps.x86_64-linux.org-publish = {
  type = "app";
  program = "${org-publish-script}/bin/org-publish";
};
```

`org-publish` is a shell script that:
1. Walks `~/2026/` for new/changed `.org` files
2. Runs them through the pipeline
3. POSTs results to pastebin

---

## Phase 5: Sheaf Proof System & Permission Model (LATER)

### Objective
Each tile carries a proof that its output is correct relative to its input spec.

### Structure
- Tile hashes its source code at build time (CID)
- Input hashes are recorded (DAG-CBOR)
- Output hashes are linked to input hashes
- A lattice of tiles is constructed where each node is a `(tile_hash, input_hash, output_hash)` triple
- The lattice can be verified by a sheaf proof: is there a path from spec to output?

### Use Cases
- Reproducible builds: "this tile produced this output from this input"
- Permission escalation: tiles can request more access (disk, network, GPU) via sheaf proof of need
- Audit: every action is linked to a tile + input + output triple

---

## Appendix: Key Files Reference

### Source Files
| File | Purpose |
|---|---|
| `src/tiles.rs` | FFI loader for `.so` tiles (libloading, discovery, Plugin wrapper) |
| `src/plugin.rs` | `Plugin` trait + `PluginRegistry` |
| `src/plugins/mod.rs` | Built-in plugin implementations |
| `src/model.rs` | `PasteIndex` struct (DB model) |
| `src/handlers.rs` | HTTP route handlers |
| `src/main.rs` | Startup, tile loading, plugin registration |
| `src/bin/reindex.rs` | Single-root reindexer |
| `src/bin/multi_reindex.rs` | Multi-root reindexer (Phase 1) |
| `src/tagging.rs` | Auto-tagging, content analysis |

### Tile Files
| File | Purpose |
|---|---|
| `tiles/zos-circuit-tile/` | ZK circuit renderer (cdylib .so) |
| `tiles/org-tile/` | Org-mode → HTML renderer (cdylib .so) |
| `tiles/_template/` | Template for new tiles |

### Config/Infra
| File | Purpose |
|---|---|
| `flake.nix` | Nix flake with all inputs, combinedSrc, tile paths |
| `Cargo.toml` | Cargo workspace with `[[bin]]` entries |
| `roots.toml` | Multi-root import config (Phase 1) |

---

## Immediate Next Steps

1. Complete `src/bin/multi_reindex.rs` — the config parser and file walker
2. Add `root` field to `PasteIndex` in `src/model.rs`
3. Update `src/view.rs` and `src/handlers.rs` for root-aware browsing
4. Wire `multi-reindex` as a flake app
5. Build and test with a small directory tree
