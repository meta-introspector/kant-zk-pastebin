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
  description = "Vendored crate: criterion
criterion
criterion_tests
bench_main (0.8.2
0.1.4
0.3
0.2.0
4.5
0.8.2
1.1
0.3
0.13
0.2
11.1
0.6
^0.3.2
1.3
1.5.1
1.0.100
1.0.100
2.0
1.1
1.0
2.3
0.5.0
0.3
1.0
0.8
3.5.0
0.4)";
  
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
      packages.${system}.criterion-0.8.2 = cargo2nixPkgs.mkRustCrate {
        name = "criterion
criterion
criterion_tests
bench_main";
        version = "0.8.2
0.1.4
0.3
0.2.0
4.5
0.8.2
1.1
0.3
0.13
0.2
11.1
0.6
^0.3.2
1.3
1.5.1
1.0.100
1.0.100
2.0
1.1
1.0
2.3
0.5.0
0.3
1.0
0.8
3.5.0
0.4";
        src = ././vendor/criterion-0.8.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.criterion-0.8.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
