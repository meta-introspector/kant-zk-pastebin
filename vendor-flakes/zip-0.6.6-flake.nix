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
  description = "Vendored crate: zip
read_entry
read_metadata (0.6.6
0.8.2
1.4.3
0.4.3
0.1.5
1.3.2
1.0.23
0.12.1
0.11.0
0.10.1
0.3.7
0.11.2
0.1.5
0.2.5
0.3.7
2.3.2
0.8.8)";
  
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
      packages.${system}.zip-0.6.6 = cargo2nixPkgs.mkRustCrate {
        name = "zip
read_entry
read_metadata";
        version = "0.6.6
0.8.2
1.4.3
0.4.3
0.1.5
1.3.2
1.0.23
0.12.1
0.11.0
0.10.1
0.3.7
0.11.2
0.1.5
0.2.5
0.3.7
2.3.2
0.8.8";
        src = ././vendor/zip-0.6.6;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.zip-0.6.6;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
