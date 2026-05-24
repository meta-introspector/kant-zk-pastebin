{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "precomputed-hash";
  version = "0.1.1";
  src = ././vendor/precomputed-hash-0.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "precomputed-hash";
  #   license = lib.licenses.mit;
  # };
}
