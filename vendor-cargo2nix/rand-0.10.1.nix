{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand
rand";
  version = "0.10.1
0.10.0
0.4.0
0.10.0
1.0.103
1.1.3
0.10
1.7
1.0.140";
  src = ././vendor/rand-0.10.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand
rand";
  #   license = lib.licenses.mit;
  # };
}
