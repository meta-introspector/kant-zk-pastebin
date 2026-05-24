{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "globwalk";
  version = "0.9.1
2
0.4.11
2
0.1.2
3";
  src = ././vendor/globwalk-0.9.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "globwalk";
  #   license = lib.licenses.mit;
  # };
}
