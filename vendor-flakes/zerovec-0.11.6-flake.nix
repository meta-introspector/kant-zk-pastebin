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
  description = "Vendored crate: zerovec
zerovec
zv_serde
vzv
zeromap
zerovec
zerovec_iai
zerovec_serde (0.11.6
0.2.0
1.0.4
1.0.220
2.0.0
0.8.2
0.1.6
0.11.3
1.3.1
0.3
0.1.1
1.43.2
1.0.3
0.9
0.5
0.9
1.2.0
1.0.220
1.0.45
0.8.2
0.5.0)";
  
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
      packages.${system}.zerovec-0.11.6 = cargo2nixPkgs.mkRustCrate {
        name = "zerovec
zerovec
zv_serde
vzv
zeromap
zerovec
zerovec_iai
zerovec_serde";
        version = "0.11.6
0.2.0
1.0.4
1.0.220
2.0.0
0.8.2
0.1.6
0.11.3
1.3.1
0.3
0.1.1
1.43.2
1.0.3
0.9
0.5
0.9
1.2.0
1.0.220
1.0.45
0.8.2
0.5.0";
        src = ././vendor/zerovec-0.11.6;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.zerovec-0.11.6;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
