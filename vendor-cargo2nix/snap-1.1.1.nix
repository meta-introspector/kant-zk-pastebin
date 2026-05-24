{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "snap";
  version = "1.1.1
0.3.1";
  src = ././vendor/snap-1.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "snap";
  #   license = lib.licenses.mit;
  # };
}
