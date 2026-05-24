{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "env_filter
env_filter";
  version = "1.0.1
0.4.29
1.12.3
1.0";
  src = ././vendor/env_filter-1.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "env_filter
env_filter";
  #   license = lib.licenses.mit;
  # };
}
