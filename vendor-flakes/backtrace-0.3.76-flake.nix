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
  description = "Vendored crate: backtrace
backtrace
backtrace
raw
accuracy
concurrent-panics
current-exe-mismatch
long_fn_name
sgx-image-base
skip_inner_frames
smoke
benchmarks (0.3.76
1.0
0.5.0
0.1.24
1.0
0.8
0.2
0.25.0
0.2.156
0.8
0.37.0
0.8.1)";
  
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
      packages.${system}.backtrace-0.3.76 = cargo2nixPkgs.mkRustCrate {
        name = "backtrace
backtrace
backtrace
raw
accuracy
concurrent-panics
current-exe-mismatch
long_fn_name
sgx-image-base
skip_inner_frames
smoke
benchmarks";
        version = "0.3.76
1.0
0.5.0
0.1.24
1.0
0.8
0.2
0.25.0
0.2.156
0.8
0.37.0
0.8.1";
        src = ././vendor/backtrace-0.3.76;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.backtrace-0.3.76;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
