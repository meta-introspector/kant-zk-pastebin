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
  description = "Vendored crate: ipld-core
ipld_core
macros
serde_deserialize
serde_deserializer
serde_serialize
serde_serializer (0.4.3
0.11.1
1.0
1.0.195
0.11.5
1.0.197
0.6.0
0.2.0
1.0.79
1.0.132)";
  
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
      packages.${system}.ipld-core-0.4.3 = cargo2nixPkgs.mkRustCrate {
        name = "ipld-core
ipld_core
macros
serde_deserialize
serde_deserializer
serde_serialize
serde_serializer";
        version = "0.4.3
0.11.1
1.0
1.0.195
0.11.5
1.0.197
0.6.0
0.2.0
1.0.79
1.0.132";
        src = ././vendor/ipld-core-0.4.3;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.ipld-core-0.4.3;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
