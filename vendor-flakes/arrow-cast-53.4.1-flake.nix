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
  description = "Vendored crate: arrow-cast
arrow_cast
parse_date
parse_decimal
parse_time
parse_timestamp (53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
2.0.0
0.22
>= 0.4.34, < 0.4.40
7.0
2.1
1.0
0.4
1.0.16
0.5
2.1
0.8)";
  
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
      packages.${system}.arrow-cast-53.4.1 = cargo2nixPkgs.mkRustCrate {
        name = "arrow-cast
arrow_cast
parse_date
parse_decimal
parse_time
parse_timestamp";
        version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
2.0.0
0.22
>= 0.4.34, < 0.4.40
7.0
2.1
1.0
0.4
1.0.16
0.5
2.1
0.8";
        src = ././vendor/arrow-cast-53.4.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.arrow-cast-53.4.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
