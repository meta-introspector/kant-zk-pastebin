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
  description = "Vendored crate: h2
h2
akamai
client
server (0.3.27
1
1.0.5
0.3
0.3
0.3
0.2
2
0.4.2
1
0.7.1
0.1.35
0.10
0.4.3
1.0.3
0.8.4
1.0.0
1.0.0
1
0.24
2.3.2
0.25)";
  
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
      packages.${system}.h2-0.3.27 = cargo2nixPkgs.mkRustCrate {
        name = "h2
h2
akamai
client
server";
        version = "0.3.27
1
1.0.5
0.3
0.3
0.3
0.2
2
0.4.2
1
0.7.1
0.1.35
0.10
0.4.3
1.0.3
0.8.4
1.0.0
1.0.0
1
0.24
2.3.2
0.25";
        src = ././vendor/h2-0.3.27;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.h2-0.3.27;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
