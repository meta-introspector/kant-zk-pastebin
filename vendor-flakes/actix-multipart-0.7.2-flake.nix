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
  description = "Vendored crate: actix-multipart (0.7.2
=0.7.0
3
4
0.99.5
0.3.17
0.3.17
1.3
0.1
0.4
2.5
0.3
0.8
1
1
1
3.4
1.24.2
3
0.10
2.2
0.1
4
1
3
0.11
0.3
0.3.17
3
1.24.2
0.1)";
  
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
      packages.${system}.actix-multipart-0.7.2 = cargo2nixPkgs.mkRustCrate {
        name = "actix-multipart";
        version = "0.7.2
=0.7.0
3
4
0.99.5
0.3.17
0.3.17
1.3
0.1
0.4
2.5
0.3
0.8
1
1
1
3.4
1.24.2
3
0.10
2.2
0.1
4
1
3
0.11
0.3
0.3.17
3
1.24.2
0.1";
        src = ././vendor/actix-multipart-0.7.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.actix-multipart-0.7.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
