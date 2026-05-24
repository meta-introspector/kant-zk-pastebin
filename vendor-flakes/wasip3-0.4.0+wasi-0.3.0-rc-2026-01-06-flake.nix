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
  description = "Vendored crate: wasip3
wasip3
cli-command
http-proxy
http-proxy-compat (0.4.0+wasi-0.3.0-rc-2026-01-06
1.10.1
1.3.1
1.0.1
2.0.17
0.51.0
0.3.31
1.3.1
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
      packages.${system}.wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06 = cargo2nixPkgs.mkRustCrate {
        name = "wasip3
wasip3
cli-command
http-proxy
http-proxy-compat";
        version = "0.4.0+wasi-0.3.0-rc-2026-01-06
1.10.1
1.3.1
1.0.1
2.0.17
0.51.0
0.3.31
1.3.1
0.51.0";
        src = ././vendor/wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
