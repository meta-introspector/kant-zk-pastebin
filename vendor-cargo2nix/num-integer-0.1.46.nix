{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-integer";
  version = "0.1.46
0.2.11";
  src = ././vendor/num-integer-0.1.46;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-integer";
  #   license = lib.licenses.mit;
  # };
}
