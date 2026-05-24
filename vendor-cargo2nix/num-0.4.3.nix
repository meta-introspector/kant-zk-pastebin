{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num";
  version = "0.4.3
0.4.5
0.4.6
0.1.46
0.1.45
0.4.2
0.2.19";
  src = ././vendor/num-0.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num";
  #   license = lib.licenses.mit;
  # };
}
