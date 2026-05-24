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
  description = "Vendored crate: bytemuck
bytemuck
array_tests
cast_slice_tests
checked_tests
derive
doc_tests
offset_of_tests
std_tests
transparent
wrapper_forgets (1.25.0
1.10.2
1.0.22)";
  
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
      packages.${system}.bytemuck-1.25.0 = cargo2nixPkgs.mkRustCrate {
        name = "bytemuck
bytemuck
array_tests
cast_slice_tests
checked_tests
derive
doc_tests
offset_of_tests
std_tests
transparent
wrapper_forgets";
        version = "1.25.0
1.10.2
1.0.22";
        src = ././vendor/bytemuck-1.25.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.bytemuck-1.25.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
