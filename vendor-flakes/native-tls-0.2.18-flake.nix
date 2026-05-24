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
  description = "Vendored crate: native-tls
native_tls (0.2.18
3.0
0.9
0.4.27
0.10.75
0.2.1
0.9.111
3.1.0
0.1.28
0.2.170
3.5.1
2.15.0)";
  
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
      packages.${system}.native-tls-0.2.18 = cargo2nixPkgs.mkRustCrate {
        name = "native-tls
native_tls";
        version = "0.2.18
3.0
0.9
0.4.27
0.10.75
0.2.1
0.9.111
3.1.0
0.1.28
0.2.170
3.5.1
2.15.0";
        src = ././vendor/native-tls-0.2.18;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.native-tls-0.2.18;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
