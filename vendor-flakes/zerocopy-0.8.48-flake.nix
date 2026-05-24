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
  description = "Vendored crate: zerocopy
zerocopy
codegen
include
ui
as_bytes_dynamic_size
as_bytes_static_size
extend_vec_zeroed
insert_vec_zeroed
new_box_zeroed
new_box_zeroed_with_elems_dynamic_padding
new_box_zeroed_with_elems_dynamic_size
new_vec_zeroed
new_zeroed
read_from_bytes
read_from_prefix
read_from_suffix
ref_from_bytes_dynamic_padding
ref_from_bytes_dynamic_size
ref_from_bytes_static_size
ref_from_bytes_with_elems_dynamic_padding
ref_from_bytes_with_elems_dynamic_size
ref_from_prefix_dynamic_padding
ref_from_prefix_dynamic_size
ref_from_prefix_static_size
ref_from_prefix_with_elems_dynamic_padding
ref_from_prefix_with_elems_dynamic_size
ref_from_suffix_dynamic_padding
ref_from_suffix_dynamic_size
ref_from_suffix_static_size
ref_from_suffix_with_elems_dynamic_padding
ref_from_suffix_with_elems_dynamic_size
split_at_dynamic_padding
split_at_dynamic_size
split_at_unchecked_dynamic_padding
split_at_unchecked_dynamic_size
split_via_immutable_dynamic_padding
split_via_immutable_dynamic_size
split_via_runtime_check_dynamic_padding
split_via_runtime_check_dynamic_size
split_via_unchecked_dynamic_padding
split_via_unchecked_dynamic_size
transmute
transmute_ref_dynamic_size
transmute_ref_static_size
try_read_from_bytes
try_read_from_prefix
try_read_from_suffix
try_ref_from_bytes_dynamic_padding
try_ref_from_bytes_dynamic_size
try_ref_from_bytes_static_size
try_ref_from_bytes_with_elems_dynamic_padding
try_ref_from_bytes_with_elems_dynamic_size
try_ref_from_prefix_dynamic_padding
try_ref_from_prefix_dynamic_size
try_ref_from_prefix_static_size
try_ref_from_prefix_with_elems_dynamic_padding
try_ref_from_prefix_with_elems_dynamic_size
try_ref_from_suffix_dynamic_padding
try_ref_from_suffix_dynamic_size
try_ref_from_suffix_static_size
try_ref_from_suffix_with_elems_dynamic_padding
try_ref_from_suffix_with_elems_dynamic_size
try_transmute
try_transmute_ref_dynamic_size
try_transmute_ref_static_size
write_to_dynamic_size
write_to_prefix_dynamic_size
write_to_prefix_static_size
write_to_static_size
write_to_suffix_dynamic_size
write_to_suffix_static_size
zero_dynamic_padding
zero_dynamic_size
zero_static_size (0.8.48
=0.8.48
0.3.0
0.11
0.8.5
1.0
1.0
1.1
=0.8.48
=0.8.48)";
  
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
      packages.${system}.zerocopy-0.8.48 = cargo2nixPkgs.mkRustCrate {
        name = "zerocopy
zerocopy
codegen
include
ui
as_bytes_dynamic_size
as_bytes_static_size
extend_vec_zeroed
insert_vec_zeroed
new_box_zeroed
new_box_zeroed_with_elems_dynamic_padding
new_box_zeroed_with_elems_dynamic_size
new_vec_zeroed
new_zeroed
read_from_bytes
read_from_prefix
read_from_suffix
ref_from_bytes_dynamic_padding
ref_from_bytes_dynamic_size
ref_from_bytes_static_size
ref_from_bytes_with_elems_dynamic_padding
ref_from_bytes_with_elems_dynamic_size
ref_from_prefix_dynamic_padding
ref_from_prefix_dynamic_size
ref_from_prefix_static_size
ref_from_prefix_with_elems_dynamic_padding
ref_from_prefix_with_elems_dynamic_size
ref_from_suffix_dynamic_padding
ref_from_suffix_dynamic_size
ref_from_suffix_static_size
ref_from_suffix_with_elems_dynamic_padding
ref_from_suffix_with_elems_dynamic_size
split_at_dynamic_padding
split_at_dynamic_size
split_at_unchecked_dynamic_padding
split_at_unchecked_dynamic_size
split_via_immutable_dynamic_padding
split_via_immutable_dynamic_size
split_via_runtime_check_dynamic_padding
split_via_runtime_check_dynamic_size
split_via_unchecked_dynamic_padding
split_via_unchecked_dynamic_size
transmute
transmute_ref_dynamic_size
transmute_ref_static_size
try_read_from_bytes
try_read_from_prefix
try_read_from_suffix
try_ref_from_bytes_dynamic_padding
try_ref_from_bytes_dynamic_size
try_ref_from_bytes_static_size
try_ref_from_bytes_with_elems_dynamic_padding
try_ref_from_bytes_with_elems_dynamic_size
try_ref_from_prefix_dynamic_padding
try_ref_from_prefix_dynamic_size
try_ref_from_prefix_static_size
try_ref_from_prefix_with_elems_dynamic_padding
try_ref_from_prefix_with_elems_dynamic_size
try_ref_from_suffix_dynamic_padding
try_ref_from_suffix_dynamic_size
try_ref_from_suffix_static_size
try_ref_from_suffix_with_elems_dynamic_padding
try_ref_from_suffix_with_elems_dynamic_size
try_transmute
try_transmute_ref_dynamic_size
try_transmute_ref_static_size
write_to_dynamic_size
write_to_prefix_dynamic_size
write_to_prefix_static_size
write_to_static_size
write_to_suffix_dynamic_size
write_to_suffix_static_size
zero_dynamic_padding
zero_dynamic_size
zero_static_size";
        version = "0.8.48
=0.8.48
0.3.0
0.11
0.8.5
1.0
1.0
1.1
=0.8.48
=0.8.48";
        src = ././vendor/zerocopy-0.8.48;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.zerocopy-0.8.48;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
