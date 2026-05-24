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
  description = "Vendored crate: thiserror
thiserror
compiletest
test_backtrace
test_deprecated
test_display
test_error
test_expr
test_from
test_generics
test_lints
test_option
test_path
test_source
test_transparent (1.0.69
=1.0.69
1.0.73
1.0.18
1.0.13
1.0.81)";
  
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
      packages.${system}.thiserror-1.0.69 = cargo2nixPkgs.mkRustCrate {
        name = "thiserror
thiserror
compiletest
test_backtrace
test_deprecated
test_display
test_error
test_expr
test_from
test_generics
test_lints
test_option
test_path
test_source
test_transparent";
        version = "1.0.69
=1.0.69
1.0.73
1.0.18
1.0.13
1.0.81";
        src = ././vendor/thiserror-1.0.69;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.thiserror-1.0.69;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
