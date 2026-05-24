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
  description = "Vendored crate: once_cell
once_cell
bench
bench_acquire
lazy_static
reentrant_init_deadlocks
regex
test_synchronization
it (1.21.4
1.1.3
0.9.10
1.8
1.1.3
1.10.6)";
  
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
      packages.${system}.once_cell-1.21.4 = cargo2nixPkgs.mkRustCrate {
        name = "once_cell
once_cell
bench
bench_acquire
lazy_static
reentrant_init_deadlocks
regex
test_synchronization
it";
        version = "1.21.4
1.1.3
0.9.10
1.8
1.1.3
1.10.6";
        src = ././vendor/once_cell-1.21.4;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.once_cell-1.21.4;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
