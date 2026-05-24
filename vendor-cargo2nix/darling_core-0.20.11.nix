{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "darling_core
darling_core";
  version = "0.20.11
1.0.7
1.0.1
1.0.86
1.0.18
0.11.1
2.0.15";
  src = ././vendor/darling_core-0.20.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "darling_core
darling_core";
  #   license = lib.licenses.mit;
  # };
}
