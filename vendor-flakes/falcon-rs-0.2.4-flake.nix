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
  description = "Vendored crate: falcon-rs
falcon
falcon-rs
expand_key
keygen
serialize
sign_verify
bench_falcon
fips206_kat
full_coverage
gen_fips206_vectors
kat_test
nist_kat
prop_tests
timing_test
falcon_bench (0.2.4
0.2
0.2
1
1
0.5
1)";
  
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
      packages.${system}.falcon-rs-0.2.4 = cargo2nixPkgs.mkRustCrate {
        name = "falcon-rs
falcon
falcon-rs
expand_key
keygen
serialize
sign_verify
bench_falcon
fips206_kat
full_coverage
gen_fips206_vectors
kat_test
nist_kat
prop_tests
timing_test
falcon_bench";
        version = "0.2.4
0.2
0.2
1
1
0.5
1";
        src = ././vendor/falcon-rs-0.2.4;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.falcon-rs-0.2.4;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
