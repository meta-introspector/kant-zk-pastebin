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
  description = "Vendored crate: tracing-attributes
tracing_attributes
async_fn
dead_code
destructuring
err
fields
follows_from
instrument
levels
names
parents
ret
targets
ui (0.1.31
1.0.60
1.0.20
2.0
0.1.67
1.0.9
0.4.2
0.1.35
0.3.0
1.0.64)";
  
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
      packages.${system}.tracing-attributes-0.1.31 = cargo2nixPkgs.mkRustCrate {
        name = "tracing-attributes
tracing_attributes
async_fn
dead_code
destructuring
err
fields
follows_from
instrument
levels
names
parents
ret
targets
ui";
        version = "0.1.31
1.0.60
1.0.20
2.0
0.1.67
1.0.9
0.4.2
0.1.35
0.3.0
1.0.64";
        src = ././vendor/tracing-attributes-0.1.31;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.tracing-attributes-0.1.31;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
