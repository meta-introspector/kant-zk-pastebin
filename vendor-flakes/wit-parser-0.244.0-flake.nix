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
  description = "Vendored crate: wit-parser
wit_parser
all (0.244.0
1.0.58
2
2.7.0
0.4.17
1.0.0
1.0.166
1.0.166
1
0.2.2
0.244.0
1.244.0
0.11
0.8.1
1.3.0
1)";
  
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
      packages.${system}.wit-parser-0.244.0 = cargo2nixPkgs.mkRustCrate {
        name = "wit-parser
wit_parser
all";
        version = "0.244.0
1.0.58
2
2.7.0
0.4.17
1.0.0
1.0.166
1.0.166
1
0.2.2
0.244.0
1.244.0
0.11
0.8.1
1.3.0
1";
        src = ././vendor/wit-parser-0.244.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.wit-parser-0.244.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
