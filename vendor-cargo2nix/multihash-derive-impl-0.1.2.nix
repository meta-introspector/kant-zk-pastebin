{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "multihash-derive-impl
multihash_derive_impl";
  version = "0.1.2
3.1.0
1.0.24
1.0.7
2.0.66
0.13.1";
  src = ././vendor/multihash-derive-impl-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "multihash-derive-impl
multihash_derive_impl";
  #   license = lib.licenses.mit;
  # };
}
