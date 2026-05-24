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
  description = "Vendored crate: parquet
parquet
parquet-concat
parquet-fromcsv
parquet-index
parquet-layout
parquet-read
parquet-rewrite
parquet-rowcount
parquet-schema
parquet-show-bloom-filter
async_read_parquet
external_metadata
read_parquet
read_with_rowgroup
write_parquet
arrow_reader
arrow_writer_layout
arrow_reader
arrow_statistics
arrow_writer
compression
encoding
metadata
row_selector (53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
0.22
7.0
1.1
>= 0.4.34, < 0.4.40
4.1
1.4.2
1.0
0.3
2.1
0.15
0.11
0.4
0.4
0.11.0
1.0
0.3
1.0
1.0
1.0
0.32.0
0.17
1.0
1.6
0.13
53.4.1
0.22
7.0
0.5
1.0
0.11
0.11.0
0.8
1.0
1.0
3.0
1.0
0.13
0.8
0.8
>=2.0.0, <2.0.14
>=2.0.0, <2.0.14)";
  
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
      packages.${system}.parquet-53.4.1 = cargo2nixPkgs.mkRustCrate {
        name = "parquet
parquet
parquet-concat
parquet-fromcsv
parquet-index
parquet-layout
parquet-read
parquet-rewrite
parquet-rowcount
parquet-schema
parquet-show-bloom-filter
async_read_parquet
external_metadata
read_parquet
read_with_rowgroup
write_parquet
arrow_reader
arrow_writer_layout
arrow_reader
arrow_statistics
arrow_writer
compression
encoding
metadata
row_selector";
        version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
0.22
7.0
1.1
>= 0.4.34, < 0.4.40
4.1
1.4.2
1.0
0.3
2.1
0.15
0.11
0.4
0.4
0.11.0
1.0
0.3
1.0
1.0
1.0
0.32.0
0.17
1.0
1.6
0.13
53.4.1
0.22
7.0
0.5
1.0
0.11
0.11.0
0.8
1.0
1.0
3.0
1.0
0.13
0.8
0.8
>=2.0.0, <2.0.14
>=2.0.0, <2.0.14";
        src = ././vendor/parquet-53.4.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.parquet-53.4.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
