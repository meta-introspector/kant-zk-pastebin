---
name: tile-system
description: Create, build, and manage dynamic `.so` tiles for the Kant Pastebin plugin system. Use when: (1) Creating a new tile (cdylib crate) that renders paste content at runtime, (2) Building an existing tile with Nix, (3) Wiring a tile into the main pastebin flake.nix as a flake input, (4) Standardizing a tile's C-ABI interface, (5) Loading tiles at startup via libloading and TILES_DIR.
---

# Tile System

## Architecture

Each tile is a standalone `cdylib` Rust crate that:
1. Has its own `Cargo.toml` with `crate-type = ["cdylib"]`
2. Has its own `flake.nix` referencing bare git mirrors for path deps
3. Exports a standard C-ABI interface via `extern "C"` functions
4. Produces `lib<name>.so` installed to `$out/lib/`
5. Lives under `tiles/<name>/` in the pastebin repo

## Standard C-ABI Interface

Every tile must export these 4 symbols:

| Symbol | Signature | Description |
|---|---|---|
| `tile_ping` | `() -> i32` | Returns 1 if tile is healthy |
| `tile_render` | `(*const c_char) -> *mut c_char` | JSON input string, JSON output string |
| `tile_render_json` | `(*const c_char) -> *mut c_char` | JSON input/output batch (future) |
| `tile_free` | `(*mut c_char)` | Free a result string allocated by the tile |

## Creating a New Tile

### Step 1: Create directory structure

```bash
mkdir -p tiles/<tile-name>/src
```

### Step 2: Write Cargo.toml

```toml
[package]
name = "<tile-name>"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### Step 3: Write src/lib.rs with C-ABI exports

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn tile_ping() -> i32 { 1 }
```

### Step 4: Write flake.nix

- For **crates.io-only deps**: `src = ./.; cargoLock.lockFile = ./Cargo.lock`
- For **path deps**: `combinedSrc` derivation with `cp -a` from bare mirror inputs

### Step 5: Wire into flake.nix

Add as flake input + TILES_DIR in the service.

## Reference Implementations

- `tiles/org-tile/` — simple tile, crates.io-only deps
- `tiles/zos-circuit-tile/` — complex tile with path deps + combinedSrc
- `src/tiles.rs` — runtime loader using libloading
