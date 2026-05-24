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
  description = "Vendored crate: futures-util
futures_util
bilock
flatten_unordered
futures_unordered
select (0.3.32
0.3.32
0.3.32
0.3.32
=0.3.32
0.3.32
0.3.32
0.1.25
0.2.26
2.2
0.2.6
0.4.7
0.10.0
0.1.9
0.1.11)";
  
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
      packages.${system}.futures-util-0.3.32 = cargo2nixPkgs.mkRustCrate {
        name = "futures-util
futures_util
bilock
flatten_unordered
futures_unordered
select";
        version = "0.3.32
0.3.32
0.3.32
0.3.32
=0.3.32
0.3.32
0.3.32
0.1.25
0.2.26
2.2
0.2.6
0.4.7
0.10.0
0.1.9
0.1.11";
        src = ././vendor/futures-util-0.3.32;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.futures-util-0.3.32;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
