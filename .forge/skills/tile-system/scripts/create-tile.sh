#!/usr/bin/env bash
# create-tile.sh — Bootstrap a new tile skeleton
# Usage: ./create-tile.sh <tile-name> [crate-name]

set -euo pipefail
TILE_NAME="${1:-}"
CRATE_NAME="${2:-$TILE_NAME}"
REPO_ROOT="$(cd "$(dirname "$0")"/../../../.. && pwd)"
TILE_DIR="$REPO_ROOT/tiles/$TILE_NAME"

if [ -z "$TILE_NAME" ]; then
  echo "Usage: $0 <tile-name> [crate-name]"
  exit 1
fi

mkdir -p "$TILE_DIR/src"

cat > "$TILE_DIR/Cargo.toml" << 'EOF'
[package]
name = "$CRATE_NAME"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
EOF

sed -i "s/\$CRATE_NAME/$CRATE_NAME/g" "$TILE_DIR/Cargo.toml"

cat > "$TILE_DIR/src/lib.rs" << 'EOF'
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn tile_ping() -> i32 { 1 }

#[no_mangle]
pub extern "C" fn tile_render(input: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input) }.to_str().unwrap_or("");
    let result = serde_json::json!({ "output": format!("tile {} received: {}", "$CRATE_NAME", input_str) });
    CString::new(result.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn tile_render_json(input: *const c_char) -> *mut c_char {
    tile_render(input)
}

#[no_mangle]
pub extern "C" fn tile_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}
EOF

sed -i "s/\$CRATE_NAME/$CRATE_NAME/g" "$TILE_DIR/src/lib.rs"

cat > "$TILE_DIR/flake.nix" << 'EOF'
{
  description = "$TILE_NAME — dynamic cdylib tile";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.buildRustPackage {
          pname = "$TILE_NAME";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          doCheck = false;
          installPhase = ''
            mkdir -p $out/lib
            cp -a target/release/*.so $out/lib/
          '';
        };
      }
    );
}
EOF

sed -i "s/\$TILE_NAME/$TILE_NAME/g" "$TILE_DIR/flake.nix"

# Generate Cargo.lock
cd "$TILE_DIR" && cargo generate-lockfile 2>/dev/null

echo "✅ Tile '$TILE_NAME' created at $TILE_DIR"
echo "Next steps:"
echo "  1. Edit $TILE_DIR/src/lib.rs with your tile logic"
echo "  2. Add deps to $TILE_DIR/Cargo.toml"
echo "  3. Build: nix build ./tiles/$TILE_NAME#"
echo "  4. Wire as flake input in flake.nix"
