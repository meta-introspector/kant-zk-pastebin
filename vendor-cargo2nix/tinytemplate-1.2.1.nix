{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tinytemplate
benchmarks";
  version = "1.2.1
1.0
1.0
0.3
1.0";
  src = ././vendor/tinytemplate-1.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tinytemplate
benchmarks";
  #   license = lib.licenses.mit;
  # };
}
