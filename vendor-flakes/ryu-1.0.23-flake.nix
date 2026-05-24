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
  description = "Vendored crate: ryu
ryu
upstream_benchmark
common_test
d2s_intrinsics_test
d2s_table_test
d2s_test
exhaustive
f2s_test
s2d_test
s2f_test
bench (1.0.23
0.1
1.8
0.10
0.10
0.5
0.8)";
  
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
      packages.${system}.ryu-1.0.23 = cargo2nixPkgs.mkRustCrate {
        name = "ryu
ryu
upstream_benchmark
common_test
d2s_intrinsics_test
d2s_table_test
d2s_test
exhaustive
f2s_test
s2d_test
s2f_test
bench";
        version = "1.0.23
0.1
1.8
0.10
0.10
0.5
0.8";
        src = ././vendor/ryu-1.0.23;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.ryu-1.0.23;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
