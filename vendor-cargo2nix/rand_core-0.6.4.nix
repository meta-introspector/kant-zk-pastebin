{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand_core";
  version = "0.6.4
0.2
1";
  src = ././vendor/rand_core-0.6.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand_core";
  #   license = lib.licenses.mit;
  # };
}
