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
  description = "Vendored crate: toml_edit
toml_edit
visit (0.25.11+spec-1.1.0
1.0.0
1.0.14
2.13.0
1.0.228
1.1.1
1.1.1
1.1.2
1.1.1
1.0.0
1.10.0
1.0.228
0.1.9
1.0.149
1.1.0
2.4.0
1.4.0
2.5.0)";
  
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
      packages.${system}.toml_edit-0.25.11+spec-1.1.0 = cargo2nixPkgs.mkRustCrate {
        name = "toml_edit
toml_edit
visit";
        version = "0.25.11+spec-1.1.0
1.0.0
1.0.14
2.13.0
1.0.228
1.1.1
1.1.1
1.1.2
1.1.1
1.0.0
1.10.0
1.0.228
0.1.9
1.0.149
1.1.0
2.4.0
1.4.0
2.5.0";
        src = ././vendor/toml_edit-0.25.11+spec-1.1.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.toml_edit-0.25.11+spec-1.1.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
