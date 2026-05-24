{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "time-core
time_core";
  version = "0.1.8";
  src = ././vendor/time-core-0.1.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "time-core
time_core";
  #   license = lib.licenses.mit;
  # };
}
