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
  description = "Vendored crate: tera
tera (1.20.1
0.4.27
0.9
0.9.1
2.1
1.4
2.2
2.5.5
2.5.5
0.8
1.7
1.0
1.0
0.1
1.12
1
1.0
3)";
  
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
      packages.${system}.tera-1.20.1 = cargo2nixPkgs.mkRustCrate {
        name = "tera
tera";
        version = "1.20.1
0.4.27
0.9
0.9.1
2.1
1.4
2.2
2.5.5
2.5.5
0.8
1.7
1.0
1.0
0.1
1.12
1
1.0
3";
        src = ././vendor/tera-1.20.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.tera-1.20.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
