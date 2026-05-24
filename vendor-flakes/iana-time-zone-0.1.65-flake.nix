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
  description = "Vendored crate: iana-time-zone
iana_time_zone
get_timezone
get_timezone_loop
stress-test (0.1.65
0.10.1
0.2.1
0.3.66
0.4.14
0.2.89
0.2.1
0.3.46
0.1.5
0.1.1
>=0.56, <=0.62
0.8.6)";
  
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
      packages.${system}.iana-time-zone-0.1.65 = cargo2nixPkgs.mkRustCrate {
        name = "iana-time-zone
iana_time_zone
get_timezone
get_timezone_loop
stress-test";
        version = "0.1.65
0.10.1
0.2.1
0.3.66
0.4.14
0.2.89
0.2.1
0.3.46
0.1.5
0.1.1
>=0.56, <=0.62
0.8.6";
        src = ././vendor/iana-time-zone-0.1.65;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.iana-time-zone-0.1.65;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
