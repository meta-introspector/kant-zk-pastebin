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
  description = "Vendored crate: ahash
ahash
bench
map_tests
nopanic
ahash
map (0.8.12
1.0
0.1.17
0.3.1
1.0.0
1.0.117
0.8.24
0.3.2
1.0.5
0.2.1
0.14.3
0.4.2
0.1.10
0.2.1
0.8.5
4.0
1.0.59
1.13.1
0.9.4
1.18.0)";
  
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
      packages.${system}.ahash-0.8.12 = cargo2nixPkgs.mkRustCrate {
        name = "ahash
ahash
bench
map_tests
nopanic
ahash
map";
        version = "0.8.12
1.0
0.1.17
0.3.1
1.0.0
1.0.117
0.8.24
0.3.2
1.0.5
0.2.1
0.14.3
0.4.2
0.1.10
0.2.1
0.8.5
4.0
1.0.59
1.13.1
0.9.4
1.18.0";
        src = ././vendor/ahash-0.8.12;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.ahash-0.8.12;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
