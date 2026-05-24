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
  description = "Vendored crate: actix-files
actix_files
guarded-listing
encoding
guard
traversal (0.6.10
3
2
3
4
2
1
2
0.3.17
0.1.4
0.4
0.3.9
2.0.1
2.1
0.2.7
0.15.5
2.7
0.1
4
0.11
3.2
2.4
0.5)";
  
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
      packages.${system}.actix-files-0.6.10 = cargo2nixPkgs.mkRustCrate {
        name = "actix-files
actix_files
guarded-listing
encoding
guard
traversal";
        version = "0.6.10
3
2
3
4
2
1
2
0.3.17
0.1.4
0.4
0.3.9
2.0.1
2.1
0.2.7
0.15.5
2.7
0.1
4
0.11
3.2
2.4
0.5";
        src = ././vendor/actix-files-0.6.10;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.actix-files-0.6.10;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
