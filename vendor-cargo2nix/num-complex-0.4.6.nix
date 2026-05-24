{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-complex";
  version = "0.4.6
0.6
1
0.2.18
0.8
0.7
1.0";
  src = ././vendor/num-complex-0.4.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-complex";
  #   license = lib.licenses.mit;
  # };
}
