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
  description = "Vendored crate: rust-embed
rust_embed
actix
axum
axum-spa
basic
poem
rocket
salvo
warp
allow_missing
custom_crate_path
include_exclude
interpolated_path
lib
metadata
metadata_only
mime_guess
path_traversal_attack
prefix (8.11.0
4
0.8
0.4.3
0.3
2.0.5
1.3.30
0.5.0-rc.2
8.9.0
8.9.0
0.16
1.0
2.3.2
0.3
0.10)";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cargo2nix.url = "github:cargo2nix/cargo2nix";
  };
  
  outputs = { self, nixpkgs, cargo2nix }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      cargo2nixPkgs = cargo2nix.packages.${system};
      
    in {
      packages.${system}.rust-embed-8.11.0 = cargo2nixPkgs.mkRustCrate {
        name = "rust-embed
rust_embed
actix
axum
axum-spa
basic
poem
rocket
salvo
warp
allow_missing
custom_crate_path
include_exclude
interpolated_path
lib
metadata
metadata_only
mime_guess
path_traversal_attack
prefix";
        version = "8.11.0
4
0.8
0.4.3
0.3
2.0.5
1.3.30
0.5.0-rc.2
8.9.0
8.9.0
0.16
1.0
2.3.2
0.3
0.10";
        src = ././vendor/rust-embed-8.11.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.rust-embed-8.11.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
