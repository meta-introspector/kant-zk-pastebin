{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand_chacha
rand_chacha";
  version = "0.9.0
0.2.14
0.9.0
1.0
0.9.0
1.0";
  src = ././vendor/rand_chacha-0.9.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand_chacha
rand_chacha";
  #   license = lib.licenses.mit;
  # };
}
