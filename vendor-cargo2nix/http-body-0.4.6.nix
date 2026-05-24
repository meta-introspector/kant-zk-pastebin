{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "http-body";
  version = "0.4.6
1
0.2
0.2
1";
  src = ././vendor/http-body-0.4.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "http-body";
  #   license = lib.licenses.mit;
  # };
}
