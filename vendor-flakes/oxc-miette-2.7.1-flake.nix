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
  description = "Vendored crate: oxc-miette
miette (2.7.1
0.3.74
0.2.1
1
4
=2.7.1
1
3.0.2
3.1.0
3.0.0
0.4.2
0.16.2
2
1.12.0
0.2.0
0.3
0.3.3
1.46.1
1.5
1.11
1.0
1.0.26
1.0.140
1.0.104)";
  
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
      packages.${system}.oxc-miette-2.7.1 = cargo2nixPkgs.mkRustCrate {
        name = "oxc-miette
miette";
        version = "2.7.1
0.3.74
0.2.1
1
4
=2.7.1
1
3.0.2
3.1.0
3.0.0
0.4.2
0.16.2
2
1.12.0
0.2.0
0.3
0.3.3
1.46.1
1.5
1.11
1.0
1.0.26
1.0.140
1.0.104";
        src = ././vendor/oxc-miette-2.7.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.oxc-miette-2.7.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
