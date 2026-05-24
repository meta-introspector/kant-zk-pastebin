{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "displaydoc";
  version = "0.2.5
1.0
1.0
2.0
0.2
0.6.1
1.0.0
1.1
1.0.24
1.0";
  src = ././vendor/displaydoc-0.2.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "displaydoc";
  #   license = lib.licenses.mit;
  # };
}
