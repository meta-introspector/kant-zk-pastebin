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
  description = "Vendored crate: multihash-codetable
multihash_codetable
custom_table
manual_mh
lib
multihash (0.2.1
1.3.2
1.0.0
1.0.0
1.2.0
0.11
0.9.2
0.8.1
0.2
1.0.158
0.11
0.11
0.11
0.13
0.8
0.1
0.4.2
0.10
0.8.0)";
  
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
      packages.${system}.multihash-codetable-0.2.1 = cargo2nixPkgs.mkRustCrate {
        name = "multihash-codetable
multihash_codetable
custom_table
manual_mh
lib
multihash";
        version = "0.2.1
1.3.2
1.0.0
1.0.0
1.2.0
0.11
0.9.2
0.8.1
0.2
1.0.158
0.11
0.11
0.11
0.13
0.8
0.1
0.4.2
0.10
0.8.0";
        src = ././vendor/multihash-codetable-0.2.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.multihash-codetable-0.2.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
