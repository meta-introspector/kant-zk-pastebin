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
  description = "Vendored crate: regex-automata
regex_automata
integration (0.4.14
1.0.0
0.4.14
2.6.0
0.8.5
1.0.69
1.3.0
0.3.3
0.9.3
1.0.3
0.1.0)";
  
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
      packages.${system}.regex-automata-0.4.14 = cargo2nixPkgs.mkRustCrate {
        name = "regex-automata
regex_automata
integration";
        version = "0.4.14
1.0.0
0.4.14
2.6.0
0.8.5
1.0.69
1.3.0
0.3.3
0.9.3
1.0.3
0.1.0";
        src = ././vendor/regex-automata-0.4.14;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.regex-automata-0.4.14;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
