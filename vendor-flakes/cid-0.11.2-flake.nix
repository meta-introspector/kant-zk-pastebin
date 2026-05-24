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
  description = "Vendored crate: cid
cid
lib (0.11.2
1.1.0
0.9.1
0.19.4
0.8.1
3.0.0
1.0
0.10.0
1.0.116
0.11.5
0.8.0
0.2.1
0.9.2
1.0.59)";
  
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
      packages.${system}.cid-0.11.2 = cargo2nixPkgs.mkRustCrate {
        name = "cid
cid
lib";
        version = "0.11.2
1.1.0
0.9.1
0.19.4
0.8.1
3.0.0
1.0
0.10.0
1.0.116
0.11.5
0.8.0
0.2.1
0.9.2
1.0.59";
        src = ././vendor/cid-0.11.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.cid-0.11.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
