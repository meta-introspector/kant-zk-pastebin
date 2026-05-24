{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "static_assertions";
  version = "1.1.0";
  src = ././vendor/static_assertions-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "static_assertions";
  #   license = lib.licenses.mit;
  # };
}
