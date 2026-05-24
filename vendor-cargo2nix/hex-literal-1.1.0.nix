{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hex-literal
hex_literal
basic";
  version = "1.1.0";
  src = ././vendor/hex-literal-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hex-literal
hex_literal
basic";
  #   license = lib.licenses.mit;
  # };
}
