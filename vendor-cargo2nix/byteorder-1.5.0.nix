{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "byteorder
byteorder";
  version = "1.5.0
0.9.2
0.7";
  src = ././vendor/byteorder-1.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "byteorder
byteorder";
  #   license = lib.licenses.mit;
  # };
}
