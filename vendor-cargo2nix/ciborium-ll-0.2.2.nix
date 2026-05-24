{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ciborium-ll";
  version = "0.2.2
0.2.2
2.2
0.4";
  src = ././vendor/ciborium-ll-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ciborium-ll";
  #   license = lib.licenses.mit;
  # };
}
