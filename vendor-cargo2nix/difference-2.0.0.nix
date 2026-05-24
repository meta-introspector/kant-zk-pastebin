{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "difference
difference";
  version = "2.0.0
0.2
0.4
0.2.7";
  src = ././vendor/difference-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "difference
difference";
  #   license = lib.licenses.mit;
  # };
}
