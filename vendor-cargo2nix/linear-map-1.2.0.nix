{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "linear-map";
  version = "1.2.0
1.0
1.0";
  src = ././vendor/linear-map-1.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "linear-map";
  #   license = lib.licenses.mit;
  # };
}
