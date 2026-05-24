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
  description = "Vendored crate: toml
toml
decode
enum_external
toml2json (0.8.23
2.0.0
1.0.145
0.6.9
0.6.11
0.22.27
1.0.199
1.0.116
0.6.0
2.3.0
1.3.2
2.5.0)";
  
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
      packages.${system}.toml-0.8.23 = cargo2nixPkgs.mkRustCrate {
        name = "toml
toml
decode
enum_external
toml2json";
        version = "0.8.23
2.0.0
1.0.145
0.6.9
0.6.11
0.22.27
1.0.199
1.0.116
0.6.0
2.3.0
1.3.2
2.5.0";
        src = ././vendor/toml-0.8.23;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.toml-0.8.23;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
