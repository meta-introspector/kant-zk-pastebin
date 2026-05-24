{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "oxc_index
oxc_index";
  version = "4.1.0
0.5
1
1";
  src = ././vendor/oxc_index-4.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "oxc_index
oxc_index";
  #   license = lib.licenses.mit;
  # };
}
