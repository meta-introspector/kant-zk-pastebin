{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "walkdir";
  version = "2.5.0
1.0.1
0.3
0.1.1";
  src = ././vendor/walkdir-2.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "walkdir";
  #   license = lib.licenses.mit;
  # };
}
