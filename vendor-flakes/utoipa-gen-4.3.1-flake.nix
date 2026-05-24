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
  description = "Vendored crate: utoipa-gen
utoipa_gen
common
modify_test
openapi_derive
openapi_derive_test
path_derive
path_derive_actix
path_derive_auto_into_responses
path_derive_auto_into_responses_actix
path_derive_auto_into_responses_axum
path_derive_axum_test
path_derive_rocket
path_parameter_derive_actix
path_parameter_derive_test
path_response_derive_test
request_body_derive_test
response_derive_test
schema_derive_test
utoipa_gen_test (4.3.1
1.0
1.0
1.0
1.7
2.0
1
2
1
4
2
0.7
0.4
1
0.5
1
1
1
3.0
1.10
0.3)";
  
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
      packages.${system}.utoipa-gen-4.3.1 = cargo2nixPkgs.mkRustCrate {
        name = "utoipa-gen
utoipa_gen
common
modify_test
openapi_derive
openapi_derive_test
path_derive
path_derive_actix
path_derive_auto_into_responses
path_derive_auto_into_responses_actix
path_derive_auto_into_responses_axum
path_derive_axum_test
path_derive_rocket
path_parameter_derive_actix
path_parameter_derive_test
path_response_derive_test
request_body_derive_test
response_derive_test
schema_derive_test
utoipa_gen_test";
        version = "4.3.1
1.0
1.0
1.0
1.7
2.0
1
2
1
4
2
0.7
0.4
1
0.5
1
1
1
3.0
1.10
0.3";
        src = ././vendor/utoipa-gen-4.3.1;
        buildInputs = [ ];
        dependencies = { };
      };
      
      defaultPackage = self.packages.${system}.utoipa-gen-4.3.1;
      
      devShell = pkgs.mkShell {
        buildInputs = [ 
          cargo2nixPkgs.cargo
          cargo2nixPkgs.rustc
        ];
      };
    };
}
