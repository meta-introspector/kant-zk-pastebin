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
  description = "Vendored crate: hashbrown
hashbrown
equivalent_trait
hasher
hasher_unwind
rayon
serde
set
bench (0.17.0
1.0.0
0.2.9
1.0.0
1.0
0.2.0
1.9.0
1.0.221
3.13.0
0.7
1.0.7
0.9.0
1.2
1.0
1.0.220
0.2.155)";
  
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
      packages.${system}.hashbrown-0.17.0 = cargo2nixPkgs.mkRustCrate {
        name = "hashbrown
hashbrown
equivalent_trait
hasher
hasher_unwind
rayon
serde
set
bench";
        version = "0.17.0
1.0.0
0.2.9
1.0.0
1.0
0.2.0
1.9.0
1.0.221
3.13.0
0.7
1.0.7
0.9.0
1.2
1.0
1.0.220
0.2.155";
        src = ././vendor/hashbrown-0.17.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.hashbrown-0.17.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
