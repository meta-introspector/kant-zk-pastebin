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
  description = "Vendored crate: time
time
tests
benchmarks (0.3.47
0.5.2
1.0.1
0.2.0
0.2.0
1.0.3
0.8.4
0.9.2
1.0.220
=0.1.8
=0.2.27
0.2.0
1.0.0
0.8.4
0.9.2
0.26.1
0.7.0
1.0.184
1.0.68
1.0.126
=0.2.27
1.0.102
0.3.58
0.8.1
0.2.98
0.1.2)";
  
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
      packages.${system}.time-0.3.47 = cargo2nixPkgs.mkRustCrate {
        name = "time
time
tests
benchmarks";
        version = "0.3.47
0.5.2
1.0.1
0.2.0
0.2.0
1.0.3
0.8.4
0.9.2
1.0.220
=0.1.8
=0.2.27
0.2.0
1.0.0
0.8.4
0.9.2
0.26.1
0.7.0
1.0.184
1.0.68
1.0.126
=0.2.27
1.0.102
0.3.58
0.8.1
0.2.98
0.1.2";
        src = ././vendor/time-0.3.47;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.time-0.3.47;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
