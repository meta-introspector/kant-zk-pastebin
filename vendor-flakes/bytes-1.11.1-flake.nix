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
  description = "Vendored crate: bytes
bytes
test_buf
test_buf_mut
test_bytes
test_bytes_odd_alloc
test_bytes_vec_alloc
test_chain
test_debug
test_iter
test_limit
test_reader
test_serde
test_take
buf
bytes
bytes_mut (1.11.1
1.3
1.0.60
1.0
0.7)";
  
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
      packages.${system}.bytes-1.11.1 = cargo2nixPkgs.mkRustCrate {
        name = "bytes
bytes
test_buf
test_buf_mut
test_bytes
test_bytes_odd_alloc
test_bytes_vec_alloc
test_chain
test_debug
test_iter
test_limit
test_reader
test_serde
test_take
buf
bytes
bytes_mut";
        version = "1.11.1
1.3
1.0.60
1.0
0.7";
        src = ././vendor/bytes-1.11.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.bytes-1.11.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
