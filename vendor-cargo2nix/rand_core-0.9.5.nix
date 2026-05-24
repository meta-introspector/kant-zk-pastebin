{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand_core
rand_core";
  version = "0.9.5
0.3.0
1";
  src = ././vendor/rand_core-0.9.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand_core
rand_core";
  #   license = lib.licenses.mit;
  # };
}
