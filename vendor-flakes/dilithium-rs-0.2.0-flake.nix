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
  description = "Vendored crate: dilithium-rs
dilithium
keygen
serialize
sign_verify
coverage
kat_vectors
multi_vector_kat
round_trip
dilithium_bench (0.2.0
0.2
1
0.10
0.10
2
1
0.5
0.8
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
      packages.${system}.dilithium-rs-0.2.0 = cargo2nixPkgs.mkRustCrate {
        name = "dilithium-rs
dilithium
keygen
serialize
sign_verify
coverage
kat_vectors
multi_vector_kat
round_trip
dilithium_bench";
        version = "0.2.0
0.2
1
0.10
0.10
2
1
0.5
0.8
0.10";
        src = ././vendor/dilithium-rs-0.2.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.dilithium-rs-0.2.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
