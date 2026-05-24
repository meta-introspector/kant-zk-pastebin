{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "data-encoding
data_encoding";
  version = "2.10.0";
  src = ././vendor/data-encoding-2.10.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "data-encoding
data_encoding";
  #   license = lib.licenses.mit;
  # };
}
