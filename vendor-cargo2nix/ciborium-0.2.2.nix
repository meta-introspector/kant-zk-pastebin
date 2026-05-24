{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ciborium";
  version = "0.2.2
0.2.2
0.2.2
1.0.100
0.4
0.8
0.11
0.11";
  src = ././vendor/ciborium-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ciborium";
  #   license = lib.licenses.mit;
  # };
}
