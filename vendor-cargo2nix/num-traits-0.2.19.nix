{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-traits";
  version = "0.2.19
0.2.0
1";
  src = ././vendor/num-traits-0.2.19;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-traits";
  #   license = lib.licenses.mit;
  # };
}
