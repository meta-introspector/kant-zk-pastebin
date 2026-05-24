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
  description = "Vendored crate: darling
darling
automatic_bounds
consume_fields
expr_with
fallible_read
heterogeneous_enum_and_word
shorthand_or_long_field
supports_struct
accrue_errors
attrs_with
compiletests
computed_bound
custom_bound
data_with
defaults
enums_default
enums_newtype
enums_struct
enums_unit
error
flatten
flatten_error_accumulation
flatten_from_field
forward_attrs_to_from_attributes
from_generics
from_meta
from_type_param
from_type_param_default
from_variant
generics
happy_path
hash_map
meta_with
multiple
newtype
skip
spanned_value
split_declaration
suggestions
supports
unsupported_attributes (0.20.11
=0.20.11
=0.20.11
1.0.86
1.0.18
2.0.15
1.0.9
1.0.89)";
  
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
      packages.${system}.darling-0.20.11 = cargo2nixPkgs.mkRustCrate {
        name = "darling
darling
automatic_bounds
consume_fields
expr_with
fallible_read
heterogeneous_enum_and_word
shorthand_or_long_field
supports_struct
accrue_errors
attrs_with
compiletests
computed_bound
custom_bound
data_with
defaults
enums_default
enums_newtype
enums_struct
enums_unit
error
flatten
flatten_error_accumulation
flatten_from_field
forward_attrs_to_from_attributes
from_generics
from_meta
from_type_param
from_type_param_default
from_variant
generics
happy_path
hash_map
meta_with
multiple
newtype
skip
spanned_value
split_declaration
suggestions
supports
unsupported_attributes";
        version = "0.20.11
=0.20.11
=0.20.11
1.0.86
1.0.18
2.0.15
1.0.9
1.0.89";
        src = ././vendor/darling-0.20.11;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.darling-0.20.11;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
