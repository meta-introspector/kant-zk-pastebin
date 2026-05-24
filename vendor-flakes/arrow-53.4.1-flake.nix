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
  description = "Vendored crate: arrow
arrow
arithmetic
array_cast
array_equal
array_transform
array_validation
csv
pyarrow
schema
shrink_to_fit
timezone
aggregate_kernels
arithmetic_kernels
array_data_validate
array_from_vec
array_slice
bit_length_kernel
bitwise_kernel
boolean_append_packed
boolean_kernels
buffer_bit_ops
buffer_create
builder
cast_kernels
comparison_kernels
concatenate_kernel
csv_reader
csv_writer
decimal_validate
equal
filter_kernels
interleave_kernels
json_reader
json_writer
length_kernel
lexsort
mutable_array
partition_kernels
primitive_run_accessor
primitive_run_take
regexp_kernels
row_format
sort_kernel
string_dictionary_builder
string_run_builder
string_run_iterator
substring_kernels
take_kernels (53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
>= 0.4.34, < 0.4.40
0.22.2
0.8
>= 0.4.34, < 0.4.40
0.5
2.1
0.8
1.0
3)";
  
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
      packages.${system}.arrow-53.4.1 = cargo2nixPkgs.mkRustCrate {
        name = "arrow
arrow
arithmetic
array_cast
array_equal
array_transform
array_validation
csv
pyarrow
schema
shrink_to_fit
timezone
aggregate_kernels
arithmetic_kernels
array_data_validate
array_from_vec
array_slice
bit_length_kernel
bitwise_kernel
boolean_append_packed
boolean_kernels
buffer_bit_ops
buffer_create
builder
cast_kernels
comparison_kernels
concatenate_kernel
csv_reader
csv_writer
decimal_validate
equal
filter_kernels
interleave_kernels
json_reader
json_writer
length_kernel
lexsort
mutable_array
partition_kernels
primitive_run_accessor
primitive_run_take
regexp_kernels
row_format
sort_kernel
string_dictionary_builder
string_run_builder
string_run_iterator
substring_kernels
take_kernels";
        version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
>= 0.4.34, < 0.4.40
0.22.2
0.8
>= 0.4.34, < 0.4.40
0.5
2.1
0.8
1.0
3";
        src = ././vendor/arrow-53.4.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.arrow-53.4.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
