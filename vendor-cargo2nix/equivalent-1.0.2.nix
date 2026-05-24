{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "equivalent
equivalent";
  version = "1.0.2";
  src = ././vendor/equivalent-1.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "equivalent
equivalent";
  #   license = lib.licenses.mit;
  # };
}
