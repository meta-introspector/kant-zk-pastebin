{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "potential_utf
potential_utf";
  version = "0.1.5
0.2.0
1.0.220
0.6.1
0.11.6
1.3.1
1.0.45";
  src = ././vendor/potential_utf-0.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "potential_utf
potential_utf";
  #   license = lib.licenses.mit;
  # };
}
