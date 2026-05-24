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
  description = "Vendored crate: rustls
rustls
test_ca
benchmarks (0.23.38
1.14
8
5.0.0
0.15
0.4.8
1.16
1.12
0.17
2.5.0
0.103.5
1.8
0.6
0.22
0.1.5
0.11
0.4
0.4.8
0.2
0.4.4
0.14
1
1
0.3.6
1
0.17
1.0.6)";
  
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
      packages.${system}.rustls-0.23.38 = cargo2nixPkgs.mkRustCrate {
        name = "rustls
rustls
test_ca
benchmarks";
        version = "0.23.38
1.14
8
5.0.0
0.15
0.4.8
1.16
1.12
0.17
2.5.0
0.103.5
1.8
0.6
0.22
0.1.5
0.11
0.4
0.4.8
0.2
0.4.4
0.14
1
1
0.3.6
1
0.17
1.0.6";
        src = ././vendor/rustls-0.23.38;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.rustls-0.23.38;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
