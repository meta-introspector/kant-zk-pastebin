{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rand";
  version = "0.8.5
0.4.4
0.3.7
0.3.0
0.6.0
1.0.103
1.2.1
0.3.0
0.2.22";
  src = ././vendor/rand-0.8.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rand";
  #   license = lib.licenses.mit;
  # };
}
