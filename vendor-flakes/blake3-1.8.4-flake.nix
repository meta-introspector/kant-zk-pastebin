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
  description = "Vendored crate: blake3
blake3
bench (1.8.4
0.3.5
0.7.4
1.0.0
0.4.2
0.11.2
0.9
1.12.1
1.0
1
0.10.0
0.2.2
0.4.2
0.13.0
0.6.0
0.10.0
1.0.107
3.8.0
1.1.12
0.3.0)";
  
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
      packages.${system}.blake3-1.8.4 = cargo2nixPkgs.mkRustCrate {
        name = "blake3
blake3
bench";
        version = "1.8.4
0.3.5
0.7.4
1.0.0
0.4.2
0.11.2
0.9
1.12.1
1.0
1
0.10.0
0.2.2
0.4.2
0.13.0
0.6.0
0.10.0
1.0.107
3.8.0
1.1.12
0.3.0";
        src = ././vendor/blake3-1.8.4;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.blake3-1.8.4;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
