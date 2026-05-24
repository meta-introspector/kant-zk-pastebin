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
  description = "Vendored crate: tempfile
tempfile
env
namedtempfile
spooled
tempdir
tempfile (3.27.0
2.1.1
1.19.0
0.3
1.1.4
>=0.3.0, <0.5
>=0.52, <0.62)";
  
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
      packages.${system}.tempfile-3.27.0 = cargo2nixPkgs.mkRustCrate {
        name = "tempfile
tempfile
env
namedtempfile
spooled
tempdir
tempfile";
        version = "3.27.0
2.1.1
1.19.0
0.3
1.1.4
>=0.3.0, <0.5
>=0.52, <0.62";
        src = ././vendor/tempfile-3.27.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.tempfile-3.27.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
