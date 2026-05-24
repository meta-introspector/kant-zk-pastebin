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
  description = "Vendored crate: getrandom
getrandom
mod
buffer (0.3.4
1
0.2.154
0.2.98
0.3
0.3.77
1
5.1
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154)";
  
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
      packages.${system}.getrandom-0.3.4 = cargo2nixPkgs.mkRustCrate {
        name = "getrandom
getrandom
mod
buffer";
        version = "0.3.4
1
0.2.154
0.2.98
0.3
0.3.77
1
5.1
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154";
        src = ././vendor/getrandom-0.3.4;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.getrandom-0.3.4;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
