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
  description = "Vendored crate: wit-bindgen-rust
wit_bindgen_rust
codegen (0.51.0
1.0.72
4.3.19
0.5
2.0.0
0.2.20
1.0.218
2.0.89
0.244.0
0.51.0
0.244.0
1
0.3.31
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
      packages.${system}.wit-bindgen-rust-0.51.0 = cargo2nixPkgs.mkRustCrate {
        name = "wit-bindgen-rust
wit_bindgen_rust
codegen";
        version = "0.51.0
1.0.72
4.3.19
0.5
2.0.0
0.2.20
1.0.218
2.0.89
0.244.0
0.51.0
0.244.0
1
0.3.31
1";
        src = ././vendor/wit-bindgen-rust-0.51.0;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.wit-bindgen-rust-0.51.0;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
