{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rust-embed-utils
rust_embed_utils";
  version = "8.11.0
0.4.8
2.0.4
0.10.5
2.3.1";
  src = ././vendor/rust-embed-utils-8.11.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rust-embed-utils
rust_embed_utils";
  #   license = lib.licenses.mit;
  # };
}
