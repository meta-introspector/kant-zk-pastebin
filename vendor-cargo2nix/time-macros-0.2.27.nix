{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "time-macros
time_macros";
  version = "0.2.27
0.2.0
=0.1.8";
  src = ././vendor/time-macros-0.2.27;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "time-macros
time_macros";
  #   license = lib.licenses.mit;
  # };
}
