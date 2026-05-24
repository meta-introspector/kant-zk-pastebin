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
  description = "Vendored crate: derive_more
derive_more
deny_missing_docs
add
add_assign
as_mut
as_ref
boats_display_derive
constructor
deref
deref_mut
display
error
from
from_str
generics
index
index_mut
into
into_iterator
is_variant
lib
mul
mul_assign
no_std
not
sum
try_into
unwrap (0.99.20
0.4
1.0
1.0
2
0.5
0.4)";
  
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
      packages.${system}.derive_more-0.99.20 = cargo2nixPkgs.mkRustCrate {
        name = "derive_more
derive_more
deny_missing_docs
add
add_assign
as_mut
as_ref
boats_display_derive
constructor
deref
deref_mut
display
error
from
from_str
generics
index
index_mut
into
into_iterator
is_variant
lib
mul
mul_assign
no_std
not
sum
try_into
unwrap";
        version = "0.99.20
0.4
1.0
1.0
2
0.5
0.4";
        src = ././vendor/derive_more-0.99.20;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.derive_more-0.99.20;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
