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
  description = "Vendored crate: reqwest
blocking
json_dynamic
json_typed
tor_socks
form
simple
blocking
cookie
gzip
brotli
deflate
multipart (0.11.27
0.21
1.0
0.3.0
0.3.0
0.2
2.0
1.0
1.0
0.7.1
0.1.2
0.3
2.2
0.4.0
0.17.0
0.20.0
0.8
0.3
0.3.14
0.0.3
0.0.4
0.24
0.4.0
0.14.21
0.24.0
0.5
2.3
0.4
0.3.16
0.2.10
1
2.1
0.2.0
0.10
0.21.6
0.6
1.0
1.0
0.3.0
0.24
0.5.1
0.7.1
0.25
3.3.0
0.3
0.10
0.3.0
0.14
1.0
1.0
1.0
0.3.45
1.0
0.2.68
0.4.18
0.4
0.3.25
0.2.68
0.3
0.5.1
0.50.0)";
  
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
      packages.${system}.reqwest-0.11.27 = cargo2nixPkgs.mkRustCrate {
        name = "reqwest
blocking
json_dynamic
json_typed
tor_socks
form
simple
blocking
cookie
gzip
brotli
deflate
multipart";
        version = "0.11.27
0.21
1.0
0.3.0
0.3.0
0.2
2.0
1.0
1.0
0.7.1
0.1.2
0.3
2.2
0.4.0
0.17.0
0.20.0
0.8
0.3
0.3.14
0.0.3
0.0.4
0.24
0.4.0
0.14.21
0.24.0
0.5
2.3
0.4
0.3.16
0.2.10
1
2.1
0.2.0
0.10
0.21.6
0.6
1.0
1.0
0.3.0
0.24
0.5.1
0.7.1
0.25
3.3.0
0.3
0.10
0.3.0
0.14
1.0
1.0
1.0
0.3.45
1.0
0.2.68
0.4.18
0.4
0.3.25
0.2.68
0.3
0.5.1
0.50.0";
        src = ././vendor/reqwest-0.11.27;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.reqwest-0.11.27;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
