{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-rational";
  version = "0.4.2
0.4.0
0.1.42
0.2.18
1.0.0";
  src = ././vendor/num-rational-0.4.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-rational";
  #   license = lib.licenses.mit;
  # };
}
