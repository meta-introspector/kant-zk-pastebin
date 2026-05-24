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
  description = "Vendored crate: icu_provider
icu_provider
data_locale_bench (2.2.0
1.3.1
0.2.0
0.2.3
0.4.0
2.2.0
0.4.17
1.0.3
1.0.220
1.0.45
1.2.0
0.6.1
0.8.2
0.1.6
0.2.4
0.11.6
1.0.45
0.5.0)";
  
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
      packages.${system}.icu_provider-2.2.0 = cargo2nixPkgs.mkRustCrate {
        name = "icu_provider
icu_provider
data_locale_bench";
        version = "2.2.0
1.3.1
0.2.0
0.2.3
0.4.0
2.2.0
0.4.17
1.0.3
1.0.220
1.0.45
1.2.0
0.6.1
0.8.2
0.1.6
0.2.4
0.11.6
1.0.45
0.5.0";
        src = ././vendor/icu_provider-2.2.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.icu_provider-2.2.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
