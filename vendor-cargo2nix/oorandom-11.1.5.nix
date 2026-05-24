{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "oorandom";
  version = "11.1.5
0.5
0.2
0.1
3.0.0";
  src = ././vendor/oorandom-11.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "oorandom";
  #   license = lib.licenses.mit;
  # };
}
