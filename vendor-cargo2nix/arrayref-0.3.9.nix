{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrayref";
  version = "0.3.9
1.0";
  src = ././vendor/arrayref-0.3.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrayref";
  #   license = lib.licenses.mit;
  # };
}
