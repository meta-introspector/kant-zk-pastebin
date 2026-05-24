{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "httparse
httparse
uri
parse";
  version = "1.10.1
0.3.5
0.8.5";
  src = ././vendor/httparse-1.10.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "httparse
httparse
uri
parse";
  #   license = lib.licenses.mit;
  # };
}
