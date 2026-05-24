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
  description = "Vendored crate: nix
nix
test
test-aio-drop
test-clearenv
test-prctl (0.31.3
2.3.3
1.0
0.2.186
0.9
0.1.0
0.1
0.12
0.9
1.0.7
3.7.1
0.2.1
0.5.3
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
      packages.${system}.nix-0.31.3 = cargo2nixPkgs.mkRustCrate {
        name = "nix
nix
test
test-aio-drop
test-clearenv
test-prctl";
        version = "0.31.3
2.3.3
1.0
0.2.186
0.9
0.1.0
0.1
0.12
0.9
1.0.7
3.7.1
0.2.1
0.5.3
0.4";
        src = ././vendor/nix-0.31.3;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.nix-0.31.3;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
