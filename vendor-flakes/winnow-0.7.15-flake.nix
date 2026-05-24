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
  description = "Vendored crate: winnow
winnow
arithmetic
c_expression
css
custom_error
http
ini
iterator
json
json_iterator
ndjson
s_expression
string
arithmetic
c_expression
http
ini
json (0.7.15
0.6.15
1.0.8
1.48.1
2.7
0.4.3
0.11.4
1.0.100
1.0.15
0.3.0
0.5.1
0.3.1
1.6.0
2.1.1
0.6.21
0.2.0)";
  
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
      packages.${system}.winnow-0.7.15 = cargo2nixPkgs.mkRustCrate {
        name = "winnow
winnow
arithmetic
c_expression
css
custom_error
http
ini
iterator
json
json_iterator
ndjson
s_expression
string
arithmetic
c_expression
http
ini
json";
        version = "0.7.15
0.6.15
1.0.8
1.48.1
2.7
0.4.3
0.11.4
1.0.100
1.0.15
0.3.0
0.5.1
0.3.1
1.6.0
2.1.1
0.6.21
0.2.0";
        src = ././vendor/winnow-0.7.15;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.winnow-0.7.15;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
