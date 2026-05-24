{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-data
arrow_data";
  version = "53.4.1
53.4.1
53.4.1
2.1
0.4";
  src = ././vendor/arrow-data-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-data
arrow_data";
  #   license = lib.licenses.mit;
  # };
}
