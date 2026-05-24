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
  description = "Vendored crate: insta
insta
test_advanced
test_basic
test_binary
test_comparator
test_glob
test_inline
test_redaction
test_settings
test_toml (1.47.2
4.1
0.16
1.1.6
0.4.6
1.20.2
2.1.3
2.1.0
1.6.0
0.12.0
1.0.117
2.1.0
3
0.25.0
1
2.3.1
0.4.0
1.0.117
1.4.2)";
  
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
      packages.${system}.insta-1.47.2 = cargo2nixPkgs.mkRustCrate {
        name = "insta
insta
test_advanced
test_basic
test_binary
test_comparator
test_glob
test_inline
test_redaction
test_settings
test_toml";
        version = "1.47.2
4.1
0.16
1.1.6
0.4.6
1.20.2
2.1.3
2.1.0
1.6.0
0.12.0
1.0.117
2.1.0
3
0.25.0
1
2.3.1
0.4.0
1.0.117
1.4.2";
        src = ././vendor/insta-1.47.2;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.insta-1.47.2;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
