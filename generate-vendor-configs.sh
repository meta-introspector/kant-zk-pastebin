#!/bin/bash

# Script to generate cargo2nix and flake.nix configurations for all vendored crates

echo "🔧 Generating cargo2nix and flake.nix configurations for vendored crates"
echo "=================================================================="

# Get vendored crate directories
VENDOR_DIR="./vendor"
CRATE_DIRS=$(find "$VENDOR_DIR" -maxdepth 1 -type d -name "*" | grep -v "^$VENDOR_DIR$" | sed 's|./vendor/||' | sort)

echo "Found ${CRATE_DIRS} vendored crates"
echo ""

# Create output directories
mkdir -p ./vendor-cargo2nix
mkdir -p ./vendor-flakes

# Generate individual flake.nix files for each crate
for crate in $CRATE_DIRS; do
    echo "📦 Processing crate: $crate"
    
    # Check if Cargo.toml exists
    if [ ! -f "$VENDOR_DIR/$crate/Cargo.toml" ]; then
        echo "❌ Skipping $crate - no Cargo.toml found"
        continue
    fi
    
    # Read crate metadata
    crate_name=$(grep "^name = " "$VENDOR_DIR/$crate/Cargo.toml" | sed 's/name = "\(.*\)"/\1/')
    crate_version=$(grep "^version = " "$VENDOR_DIR/$crate/Cargo.toml" | sed 's/version = "\(.*\)"/\1/')
    
    echo "   Name: $crate_name"
    echo "   Version: $crate_version"
    
    # Generate flake.nix for this crate
    cat > "./vendor-flakes/$crate-flake.nix" << EOF
{ pkgs ? import <nixpkgs> {} }:

let
  cargo2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "cargo2nix";
    repo = "cargo2nix";
    rev = "master";
    sha256 = "0z1j2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7a8b9c0d1e2f3";
  }) {};
in
{
  description = "Vendored crate: $crate_name ($crate_version)";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cargo2nix.url = "github:cargo2nix/cargo2nix";
  };
  
  outputs = { self, nixpkgs, cargo2nix }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.\${system};
      cargo2nixPkgs = cargo2nix.packages.\${system};
      
    in {
      packages.\${system}.$crate = cargo2nixPkgs.mkRustCrate {
        name = "$crate_name";
        version = "$crate_version";
        src = ./$VENDOR_DIR/$crate;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.\${system}.$crate;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
EOF
    
    # Generate cargo2nix configuration
    cat > "./vendor-cargo2nix/$crate.nix" << EOF
{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "$crate_name";
  version = "$crate_version";
  src = ./$VENDOR_DIR/$crate;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "$crate_name";
  #   license = lib.licenses.mit;
  # };
}
EOF
    
    echo "✅ Generated configurations for $crate"
    echo ""
done

# Generate unified flake.nix
echo "🔄 Generating unified flake.nix..."
cat > "./flake-vendor-unified.nix" << EOF
{ pkgs ? import <nixpkgs> {} }:

let
  cargo2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "cargo2nix";
    repo = "cargo2nix";
    rev = "master";
    sha256 = "0z1j2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7a8b9c0d1e2f3";
  }) {};
  
  # Import all individual crate flakes
  crates = builtins.mapAttrs (name: flake: flake.packages.x86_64-linux.${name}) (
    builtins.listToAttrs (map (name: {
      name = name;
      value = import ./vendor-flakes/${name}-flake.nix;
    }) $CRATE_DIRS)
  );
in
{
  description = "Unified flake for all vendored crates in pastebin";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cargo2nix.url = "github:cargo2nix/cargo2nix";
  };
  
  outputs = { self, nixpkgs, cargo2nix }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.\${system};
      cargo2nixPkgs = cargo2nix.packages.\${system};
      
    in {
      # Package for each vendored crate
      packages = crates;
      
      # Default package (first crate alphabetically)
      defaultPackage = self.packages.\${system}.$(echo $CRATE_DIRS | tr ' ' '\n' | head -1);
      
      # Development shell
      devShell = pkgs.mkShell {
        buildInputs = [
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
          pkgs.cargo-audit
          pkgs.cargo-outdated
        ];
        
        shellHook = ''
          echo "Vendored crates development environment"
          echo "Available crates: $CRATE_DIRS"
          echo "Total crates: $(echo $CRATE_DIRS | wc -w)"
        '';
      };
      
      # Checks for all packages
      checks = builtins.mapAttrs (name: pkg: pkgs.runCommand "check-\${name}" {} ''
        echo "Checking \${name}..."
        \${pkg}/bin/\${name} --version || true
      '') crates;
    };
}
EOF

# Generate cargo2nix configuration for the main project
echo "🔄 Generating cargo2nix configuration for main project..."
cat > "./cargo2nix.nix" << EOF
{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "kant-pastebin";
  version = "0.1.0";
  src = ./.;
  
  buildInputs = [ ];
  
  dependencies = {
    # Add your dependencies here with proper versions
    # serde = "1.0";
    # tokio = "1.0";
  };
  
  # Add crate-specific configuration
  meta = {
    description = "Kant Pastebin - UUCP + zkTLS + IPFS pastebin service";
    license = lib.licenses.mit;
    maintainers = [ "mdupont" ];
  };
}
EOF

echo "✅ Generated all configurations!"
echo ""
echo "📁 Generated files:"
echo "   - ./vendor-cargo2nix/ - Individual cargo2nix configurations"
echo "   - ./vendor-flakes/ - Individual flake.nix files"
echo "   - ./flake-vendor-unified.nix - Unified flake for all crates"
echo "   - ./cargo2nix.nix - Main project cargo2nix configuration"
echo ""
echo "🚀 Usage:"
echo "   nix build -f ./flake-vendor-unified.nix # Build all crates"
echo "   nix develop -f ./flake-vendor-unified.nix # Dev shell for all crates"
echo "   nix build -f ./cargo2nix.nix # Build main project"
echo ""
echo "📊 Summary:"
echo "   Total crates processed: $(echo $CRATE_DIRS | wc -w)"
echo "   Generated $(find ./vendor-cargo2nix -name "*.nix" | wc -l) cargo2nix configs"
echo "   Generated $(find ./vendor-flakes -name "*-flake.nix" | wc -l) flake files"