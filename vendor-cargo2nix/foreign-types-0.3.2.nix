{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "foreign-types";
  version = "0.3.2
0.1";
  src = ././vendor/foreign-types-0.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "foreign-types";
  #   license = lib.licenses.mit;
  # };
}
