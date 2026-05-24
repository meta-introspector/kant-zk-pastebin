{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "html-escape
encode";
  version = "0.2.13
0.1
0.1.5";
  src = ././vendor/html-escape-0.2.13;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "html-escape
encode";
  #   license = lib.licenses.mit;
  # };
}
