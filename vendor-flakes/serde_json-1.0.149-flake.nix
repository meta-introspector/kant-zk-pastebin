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
  description = "Vendored crate: serde_json
serde_json
compiletest
debug
lexical
map
regression
stream
test (1.0.149
2.2.3
1.0
2
1.0.220
1.0
1.0.11
2.0.2
1.0.18
1.0.13
1.0.194
0.11.10
1.0.166
0.1.8
1.0.108
1.0.220)";
  
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
      packages.${system}.serde_json-1.0.149 = cargo2nixPkgs.mkRustCrate {
        name = "serde_json
serde_json
compiletest
debug
lexical
map
regression
stream
test";
        version = "1.0.149
2.2.3
1.0
2
1.0.220
1.0
1.0.11
2.0.2
1.0.18
1.0.13
1.0.194
0.11.10
1.0.166
0.1.8
1.0.108
1.0.220";
        src = ././vendor/serde_json-1.0.149;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.serde_json-1.0.149;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
