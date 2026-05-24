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
  description = "Vendored crate: ureq
ureq
count-bytes
cureq
custom-tls
ipv6
smoke-test
tls_config
https-agent (2.12.1
0.22
4.0.0
0.18
0.21.1
0.8
1.0.22
0.1.5
1.1
0.2
0.4
0.2
1
0.23.19
0.7
1
1
1.0.97
0.3
2.5.0
0.26
<=0.9
0.23.5
2.0
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
      packages.${system}.ureq-2.12.1 = cargo2nixPkgs.mkRustCrate {
        name = "ureq
ureq
count-bytes
cureq
custom-tls
ipv6
smoke-test
tls_config
https-agent";
        version = "2.12.1
0.22
4.0.0
0.18
0.21.1
0.8
1.0.22
0.1.5
1.1
0.2
0.4
0.2
1
0.23.19
0.7
1
1
1.0.97
0.3
2.5.0
0.26
<=0.9
0.23.5
2.0
1";
        src = ././vendor/ureq-2.12.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.ureq-2.12.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
