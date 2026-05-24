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
  description = "Vendored crate: constant_time_eq
constant_time_eq
count_instructions
count_instructions_classic
count_instructions_generic
exhaustive
bench
bench_classic
bench_generic (0.4.2
0.2.0
0.5.1)";
  
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
      packages.${system}.constant_time_eq-0.4.2 = cargo2nixPkgs.mkRustCrate {
        name = "constant_time_eq
constant_time_eq
count_instructions
count_instructions_classic
count_instructions_generic
exhaustive
bench
bench_classic
bench_generic";
        version = "0.4.2
0.2.0
0.5.1";
        src = ././vendor/constant_time_eq-0.4.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.constant_time_eq-0.4.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
