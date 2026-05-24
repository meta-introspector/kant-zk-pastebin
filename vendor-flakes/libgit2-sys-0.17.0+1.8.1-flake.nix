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
  description = "Vendored crate: libgit2-sys
libgit2_sys (0.17.0+1.8.1
0.2
0.3.0
1.1.0
1.0.43
0.3.15
0.9.45)";
  
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
      packages.${system}.libgit2-sys-0.17.0+1.8.1 = cargo2nixPkgs.mkRustCrate {
        name = "libgit2-sys
libgit2_sys";
        version = "0.17.0+1.8.1
0.2
0.3.0
1.1.0
1.0.43
0.3.15
0.9.45";
        src = ././vendor/libgit2-sys-0.17.0+1.8.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.libgit2-sys-0.17.0+1.8.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
