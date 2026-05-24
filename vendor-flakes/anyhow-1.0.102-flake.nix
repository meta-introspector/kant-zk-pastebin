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
  description = "Vendored crate: anyhow
anyhow
compiletest
test_autotrait
test_backtrace
test_boxed
test_chain
test_context
test_convert
test_downcast
test_ensure
test_ffi
test_fmt
test_macros
test_repr
test_source (1.0.102
0.3
1.0.6
2.0
2
1.0.108)";
  
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
      packages.${system}.anyhow-1.0.102 = cargo2nixPkgs.mkRustCrate {
        name = "anyhow
anyhow
compiletest
test_autotrait
test_backtrace
test_boxed
test_chain
test_context
test_convert
test_downcast
test_ensure
test_ffi
test_fmt
test_macros
test_repr
test_source";
        version = "1.0.102
0.3
1.0.6
2.0
2
1.0.108";
        src = ././vendor/anyhow-1.0.102;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.anyhow-1.0.102;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
