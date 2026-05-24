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
  description = "Vendored crate: chrono
chrono
dateutils
wasm
win_bindings (0.4.39
1.0.0
0.2
0.8
0.7.43
1.0.99
1.3.0
1
1
0.3
0.2
0.3
0.1.1
0.1.45
0.52
0.58)";
  
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
      packages.${system}.chrono-0.4.39 = cargo2nixPkgs.mkRustCrate {
        name = "chrono
chrono
dateutils
wasm
win_bindings";
        version = "0.4.39
1.0.0
0.2
0.8
0.7.43
1.0.99
1.3.0
1
1
0.3
0.2
0.3
0.1.1
0.1.45
0.52
0.58";
        src = ././vendor/chrono-0.4.39;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.chrono-0.4.39;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
