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
  description = "Vendored crate: jiff
jiff
integration (0.2.23
0.2
0.1.6
0.4.21
1.0.221
1.0.81
0.4.38
0.10.0
2.1.0
1.39.0
0.4.21
1.0.3
1.0.203
1.0.117
0.9.34
1.4.0
0.3.36
2.0.0
0.1.3
2.5.0
0.3.50
0.2.70
=0.2.23
0.1.3
3.9.0
1.10.0
0.2.4
>=0.52.0, <=0.61.*)";
  
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
      packages.${system}.jiff-0.2.23 = cargo2nixPkgs.mkRustCrate {
        name = "jiff
jiff
integration";
        version = "0.2.23
0.2
0.1.6
0.4.21
1.0.221
1.0.81
0.4.38
0.10.0
2.1.0
1.39.0
0.4.21
1.0.3
1.0.203
1.0.117
0.9.34
1.4.0
0.3.36
2.0.0
0.1.3
2.5.0
0.3.50
0.2.70
=0.2.23
0.1.3
3.9.0
1.10.0
0.2.4
>=0.52.0, <=0.61.*";
        src = ././vendor/jiff-0.2.23;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.jiff-0.2.23;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
