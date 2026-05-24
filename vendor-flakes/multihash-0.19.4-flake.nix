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
  description = "Vendored crate: multihash
multihash
identity (0.19.4
1.1.0
0.8.1
3.0.0
1.0.3
0.10
1.0.116
0.8.0
0.4.2
1.0.58
1.0.160)";
  
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
      packages.${system}.multihash-0.19.4 = cargo2nixPkgs.mkRustCrate {
        name = "multihash
multihash
identity";
        version = "0.19.4
1.1.0
0.8.1
3.0.0
1.0.3
0.10
1.0.116
0.8.0
0.4.2
1.0.58
1.0.160";
        src = ././vendor/multihash-0.19.4;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.multihash-0.19.4;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
