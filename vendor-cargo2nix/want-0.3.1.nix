{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "want";
  version = "0.3.1
0.2.4
0.2.0-alpha.2
0.2.0-alpha.2";
  src = ././vendor/want-0.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "want";
  #   license = lib.licenses.mit;
  # };
}
