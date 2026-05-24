{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "same-file";
  version = "1.0.6
0.3
0.1.1";
  src = ././vendor/same-file-1.0.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "same-file";
  #   license = lib.licenses.mit;
  # };
}
