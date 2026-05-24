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
  description = "Vendored crate: lexical-parse-integer
lexical_parse_integer
algorithm_tests
api_tests
issue_91_tests
issue_96_tests
issue_98_tests
options_tests
partial_tests
util (1.0.6
1.0.7)";
  
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
      packages.${system}.lexical-parse-integer-1.0.6 = cargo2nixPkgs.mkRustCrate {
        name = "lexical-parse-integer
lexical_parse_integer
algorithm_tests
api_tests
issue_91_tests
issue_96_tests
issue_98_tests
options_tests
partial_tests
util";
        version = "1.0.6
1.0.7";
        src = ././vendor/lexical-parse-integer-1.0.6;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.lexical-parse-integer-1.0.6;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
