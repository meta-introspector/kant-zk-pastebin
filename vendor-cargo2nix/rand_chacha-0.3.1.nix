{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand_chacha";
  version = "0.3.1
0.2.8
0.6.0
1.0
1.0";
  src = ././vendor/rand_chacha-0.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand_chacha";
  #   license = lib.licenses.mit;
  # };
}
