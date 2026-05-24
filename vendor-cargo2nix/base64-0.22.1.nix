{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "base64
base64
tests
encode
benchmarks";
  version = "0.22.1
3.2.25
0.4.0
1
0.8.5
0.13.0
0.6.0
0.25";
  src = ././vendor/base64-0.22.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "base64
base64
tests
encode
benchmarks";
  #   license = lib.licenses.mit;
  # };
}
