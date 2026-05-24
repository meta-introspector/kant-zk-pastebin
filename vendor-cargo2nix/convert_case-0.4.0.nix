{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "convert_case";
  version = "0.4.0
^0.7
0.18.0
0.18.0";
  src = ././vendor/convert_case-0.4.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "convert_case";
  #   license = lib.licenses.mit;
  # };
}
