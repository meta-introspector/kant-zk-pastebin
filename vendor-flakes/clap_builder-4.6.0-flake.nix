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
  description = "Vendored crate: clap_builder
clap_builder (4.6.0
1.0.0
1.0.13
0.3.76
1.0.0
0.11.1
0.4.3
2.9.0
0.2.2
0.3.7
1.1.0
1.1.0
0.9.0)";
  
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
      packages.${system}.clap_builder-4.6.0 = cargo2nixPkgs.mkRustCrate {
        name = "clap_builder
clap_builder";
        version = "4.6.0
1.0.0
1.0.13
0.3.76
1.0.0
0.11.1
0.4.3
2.9.0
0.2.2
0.3.7
1.1.0
1.1.0
0.9.0";
        src = ././vendor/clap_builder-4.6.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.clap_builder-4.6.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
