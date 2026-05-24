{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rust-embed
rust_embed
actix
axum
axum-spa
basic
poem
rocket
salvo
warp
allow_missing
custom_crate_path
include_exclude
interpolated_path
lib
metadata
metadata_only
mime_guess
path_traversal_attack
prefix";
  version = "8.11.0
4
0.8
0.4.3
0.3
2.0.5
1.3.30
0.5.0-rc.2
8.9.0
8.9.0
0.16
1.0
2.3.2
0.3
0.10";
  src = ././vendor/rust-embed-8.11.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rust-embed
rust_embed
actix
axum
axum-spa
basic
poem
rocket
salvo
warp
allow_missing
custom_crate_path
include_exclude
interpolated_path
lib
metadata
metadata_only
mime_guess
path_traversal_attack
prefix";
  #   license = lib.licenses.mit;
  # };
}
