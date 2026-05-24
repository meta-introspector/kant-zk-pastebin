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
  description = "Vendored crate: oxc-schemars
schemars
custom_serialization
custom_settings
doc_comments
enum_repr
from_value
main
remote_derive
schemars_attrs
serde_attrs
validate
arrayvec
bound
bytes
chrono
crate_alias
decimal
default
deprecated
dereference
docs
either
enum
enum_deny_unknown_fields
enum_repr
enumset
examples
ffi
flatten
from_value
indexmap
indexmap2
inline_subschemas
macro
nonzero_ints
property_name
range
regex
remote_derive
remote_derive_generic
result
same_name
schema_for_schema
schema_name
schema_settings
schema_with_enum
schema_with_struct
semver
skip
smallvec
smol_str
struct
struct_additional_properties
time
transparent
ui
url
uuid
validate
validate_inner (0.8.27
0.5
0.7
0.3
0.4
1.0
0.4
1.0
1.3
1.0
1.2
2.0
0.8.26
1.12
1
1.0.9
1.0
1.0.25
1.0
0.1.17
2.0
0.8
1.0
1.2.1
1.0)";
  
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
      packages.${system}.oxc-schemars-0.8.27 = cargo2nixPkgs.mkRustCrate {
        name = "oxc-schemars
schemars
custom_serialization
custom_settings
doc_comments
enum_repr
from_value
main
remote_derive
schemars_attrs
serde_attrs
validate
arrayvec
bound
bytes
chrono
crate_alias
decimal
default
deprecated
dereference
docs
either
enum
enum_deny_unknown_fields
enum_repr
enumset
examples
ffi
flatten
from_value
indexmap
indexmap2
inline_subschemas
macro
nonzero_ints
property_name
range
regex
remote_derive
remote_derive_generic
result
same_name
schema_for_schema
schema_name
schema_settings
schema_with_enum
schema_with_struct
semver
skip
smallvec
smol_str
struct
struct_additional_properties
time
transparent
ui
url
uuid
validate
validate_inner";
        version = "0.8.27
0.5
0.7
0.3
0.4
1.0
0.4
1.0
1.3
1.0
1.2
2.0
0.8.26
1.12
1
1.0.9
1.0
1.0.25
1.0
0.1.17
2.0
0.8
1.0
1.2.1
1.0";
        src = ././vendor/oxc-schemars-0.8.27;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.oxc-schemars-0.8.27;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
