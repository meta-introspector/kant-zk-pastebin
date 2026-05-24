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
  description = "Vendored crate: flate2
flate2
compress_file
decompress_file
deflatedecoder-bufread
deflatedecoder-read
deflatedecoder-write
deflateencoder-bufread
deflateencoder-read
deflateencoder-write
gzbuilder
gzdecoder-bufread
gzdecoder-read
gzdecoder-write
gzencoder-bufread
gzencoder-read
gzencoder-write
gzmultidecoder-bufread
gzmultidecoder-read
zlibdecoder-bufread
zlibdecoder-read
zlibdecoder-write
zlibencoder-bufread
zlibencoder-read
zlibencoder-write
capabilities
early-flush
empty-read
gunzip
zero-write (1.1.9
0.3.6
1.2.0
0.2
1.1.16
1.1.20
0.8.5
0.6.0
0.3
1.0
0.9
0.8.5)";
  
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
      packages.${system}.flate2-1.1.9 = cargo2nixPkgs.mkRustCrate {
        name = "flate2
flate2
compress_file
decompress_file
deflatedecoder-bufread
deflatedecoder-read
deflatedecoder-write
deflateencoder-bufread
deflateencoder-read
deflateencoder-write
gzbuilder
gzdecoder-bufread
gzdecoder-read
gzdecoder-write
gzencoder-bufread
gzencoder-read
gzencoder-write
gzmultidecoder-bufread
gzmultidecoder-read
zlibdecoder-bufread
zlibdecoder-read
zlibdecoder-write
zlibencoder-bufread
zlibencoder-read
zlibencoder-write
capabilities
early-flush
empty-read
gunzip
zero-write";
        version = "1.1.9
0.3.6
1.2.0
0.2
1.1.16
1.1.20
0.8.5
0.6.0
0.3
1.0
0.9
0.8.5";
        src = ././vendor/flate2-1.1.9;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.flate2-1.1.9;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
