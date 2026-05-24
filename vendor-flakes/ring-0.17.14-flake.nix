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
  description = "Vendored crate: ring
ring
aead_tests
agreement_tests
constant_time_tests
digest_tests
ecdsa_tests
ed25519_tests
error_tests
hkdf_tests
hmac_tests
pbkdf2_tests
quic_tests
rand_tests
rsa_tests
signature_tests (0.17.14
1.0.0
0.2.10
0.9
1.2.8
0.52
0.2.155
0.2.148
0.3.37
0.2.148)";
  
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
      packages.${system}.ring-0.17.14 = cargo2nixPkgs.mkRustCrate {
        name = "ring
ring
aead_tests
agreement_tests
constant_time_tests
digest_tests
ecdsa_tests
ed25519_tests
error_tests
hkdf_tests
hmac_tests
pbkdf2_tests
quic_tests
rand_tests
rsa_tests
signature_tests";
        version = "0.17.14
1.0.0
0.2.10
0.9
1.2.8
0.52
0.2.155
0.2.148
0.3.37
0.2.148";
        src = ././vendor/ring-0.17.14;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.ring-0.17.14;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
