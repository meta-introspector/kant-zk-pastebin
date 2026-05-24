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
  description = "Vendored crate: lexical-parse-float
lexical_parse_float
api_tests
bellerophon
bellerophon_radix_tests
bellerophon_tests
bigfloat_tests
bigint_tests
binary_tests
float_tests
issue_96_tests
issue_98_tests
lemire_tests
libm_tests
limits_tests
mask_tests
number_tests
options_tests
parse_tests
shared_tests
slow_tests
stackvec
stackvec_tests (1.0.6
1.0.6
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
      packages.${system}.lexical-parse-float-1.0.6 = cargo2nixPkgs.mkRustCrate {
        name = "lexical-parse-float
lexical_parse_float
api_tests
bellerophon
bellerophon_radix_tests
bellerophon_tests
bigfloat_tests
bigint_tests
binary_tests
float_tests
issue_96_tests
issue_98_tests
lemire_tests
libm_tests
limits_tests
mask_tests
number_tests
options_tests
parse_tests
shared_tests
slow_tests
stackvec
stackvec_tests";
        version = "1.0.6
1.0.6
1.0.7";
        src = ././vendor/lexical-parse-float-1.0.6;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.lexical-parse-float-1.0.6;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
