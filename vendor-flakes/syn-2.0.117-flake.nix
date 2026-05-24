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
  description = "Vendored crate: syn
syn
regression
test_asyncness
test_attribute
test_derive_input
test_expr
test_generics
test_grouping
test_ident
test_item
test_lit
test_meta
test_parse_buffer
test_parse_quote
test_parse_stream
test_pat
test_path
test_precedence
test_punctuated
test_receiver
test_round_trip
test_shebang
test_size
test_stmt
test_token_trees
test_ty
test_unparenthesize
test_visibility
zzz_stable
file
rust (2.0.117
1.0.91
1.0.35
1
1
1
1
1
1
0
1
1
1
0.13
0.4.16
2.3.2)";
  
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
      packages.${system}.syn-2.0.117 = cargo2nixPkgs.mkRustCrate {
        name = "syn
syn
regression
test_asyncness
test_attribute
test_derive_input
test_expr
test_generics
test_grouping
test_ident
test_item
test_lit
test_meta
test_parse_buffer
test_parse_quote
test_parse_stream
test_pat
test_path
test_precedence
test_punctuated
test_receiver
test_round_trip
test_shebang
test_size
test_stmt
test_token_trees
test_ty
test_unparenthesize
test_visibility
zzz_stable
file
rust";
        version = "2.0.117
1.0.91
1.0.35
1
1
1
1
1
1
0
1
1
1
0.13
0.4.16
2.3.2";
        src = ././vendor/syn-2.0.117;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.syn-2.0.117;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
