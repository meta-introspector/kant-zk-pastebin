{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf
phf";
  version = "0.13.1
^0.13.1
^0.13.1
1.0";
  src = ././vendor/phf-0.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf
phf";
  #   license = lib.licenses.mit;
  # };
}
