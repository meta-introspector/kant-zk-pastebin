{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand
rand";
  version = "0.9.4
0.9.0
0.9.0
1.0.103
1.2.1
0.9.0
1.7
1.0.140";
  src = ././vendor/rand-0.9.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand
rand";
  #   license = lib.licenses.mit;
  # };
}
