{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "termcolor
termcolor";
  version = "1.4.1
0.1.3";
  src = ././vendor/termcolor-1.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "termcolor
termcolor";
  #   license = lib.licenses.mit;
  # };
}
