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
  description = "Vendored crate: webpki-roots
webpki_roots
codegen
verify (1.0.7
1.8
1.15.2
0.4.3
2.3
0.14.3
0.23
1
0.103
0.18
0.6)";
  
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
      packages.${system}.webpki-roots-1.0.7 = cargo2nixPkgs.mkRustCrate {
        name = "webpki-roots
webpki_roots
codegen
verify";
        version = "1.0.7
1.8
1.15.2
0.4.3
2.3
0.14.3
0.23
1
0.103
0.18
0.6";
        src = ././vendor/webpki-roots-1.0.7;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.webpki-roots-1.0.7;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
