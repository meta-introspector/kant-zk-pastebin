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
  description = "Vendored crate: wasip2
wasip2
cli-command
cli-command-no_std
hello-world
hello-world-no_std
http-proxy
http-proxy-no_std (1.0.2+wasi-0.2.9
1.0
1.0
0.51.0)";
  
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
      packages.${system}.wasip2-1.0.2+wasi-0.2.9 = cargo2nixPkgs.mkRustCrate {
        name = "wasip2
wasip2
cli-command
cli-command-no_std
hello-world
hello-world-no_std
http-proxy
http-proxy-no_std";
        version = "1.0.2+wasi-0.2.9
1.0
1.0
0.51.0";
        src = ././vendor/wasip2-1.0.2+wasi-0.2.9;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.wasip2-1.0.2+wasi-0.2.9;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
