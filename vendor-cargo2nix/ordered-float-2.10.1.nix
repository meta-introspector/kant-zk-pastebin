{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ordered-float";
  version = "2.10.1
1.0.0
0.2.1
1.0.0
0.8.3
0.7
0.6.5
1.0
1.0";
  src = ././vendor/ordered-float-2.10.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ordered-float";
  #   license = lib.licenses.mit;
  # };
}
