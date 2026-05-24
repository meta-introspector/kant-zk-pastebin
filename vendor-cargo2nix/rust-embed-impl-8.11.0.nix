{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rust-embed-impl
rust_embed_impl";
  version = "8.11.0
1
1
8.11.0
3
2
2.3.1";
  src = ././vendor/rust-embed-impl-8.11.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rust-embed-impl
rust_embed_impl";
  #   license = lib.licenses.mit;
  # };
}
