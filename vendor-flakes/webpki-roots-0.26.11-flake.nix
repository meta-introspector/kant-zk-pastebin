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
verify (0.26.11
1
0.4.3
2.3
1.8
0.13
0.17.0
0.23
1
0.102
0.17.0
0.5.2)";
  
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
      packages.${system}.webpki-roots-0.26.11 = cargo2nixPkgs.mkRustCrate {
        name = "webpki-roots
webpki_roots
verify";
        version = "0.26.11
1
0.4.3
2.3
1.8
0.13
0.17.0
0.23
1
0.102
0.17.0
0.5.2";
        src = ././vendor/webpki-roots-0.26.11;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.webpki-roots-0.26.11;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
