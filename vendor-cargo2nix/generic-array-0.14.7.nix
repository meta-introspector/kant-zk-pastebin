{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "generic-array
generic_array";
  version = "0.14.7
1.0
1.12
1
1.0
1.0
0.9";
  src = ././vendor/generic-array-0.14.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "generic-array
generic_array";
  #   license = lib.licenses.mit;
  # };
}
