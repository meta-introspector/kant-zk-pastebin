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
  description = "Vendored crate: deranged
deranged (0.5.8
=0.3.0
0.2.15
0.2.0
1.0.3
0.10.0
0.8.4
0.9.0
1.0.220
0.10.0
0.8.4
0.9.0
1.0.86)";
  
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
      packages.${system}.deranged-0.5.8 = cargo2nixPkgs.mkRustCrate {
        name = "deranged
deranged";
        version = "0.5.8
=0.3.0
0.2.15
0.2.0
1.0.3
0.10.0
0.8.4
0.9.0
1.0.220
0.10.0
0.8.4
0.9.0
1.0.86";
        src = ././vendor/deranged-0.5.8;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.deranged-0.5.8;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
