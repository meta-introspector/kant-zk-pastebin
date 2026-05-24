{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf
phf";
  version = "0.11.3
^0.11.3
^0.11.3
1.0";
  src = ././vendor/phf-0.11.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf
phf";
  #   license = lib.licenses.mit;
  # };
}
