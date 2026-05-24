{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "http-range
benchmark";
  version = "0.1.5
0.3";
  src = ././vendor/http-range-0.1.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "http-range
benchmark";
  #   license = lib.licenses.mit;
  # };
}
