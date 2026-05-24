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
  description = "Vendored crate: bumpalo
bumpalo (3.20.2
0.2.8
1.0.171
=0.4.0
0.3.6
=1.0.3
0.8.5
=1.10.0
=1.12.1
1.0.197
1.0.115)";
  
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
      packages.${system}.bumpalo-3.20.2 = cargo2nixPkgs.mkRustCrate {
        name = "bumpalo
bumpalo";
        version = "3.20.2
0.2.8
1.0.171
=0.4.0
0.3.6
=1.0.3
0.8.5
=1.10.0
=1.12.1
1.0.197
1.0.115";
        src = ././vendor/bumpalo-3.20.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.bumpalo-3.20.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
