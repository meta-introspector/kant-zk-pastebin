{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "httpdate
benchmarks";
  version = "1.0.3
0.5";
  src = ././vendor/httpdate-1.0.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "httpdate
benchmarks";
  #   license = lib.licenses.mit;
  # };
}
