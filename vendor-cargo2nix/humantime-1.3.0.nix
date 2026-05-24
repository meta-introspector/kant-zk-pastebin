{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "humantime
humantime";
  version = "1.3.0
1.0.0
0.4.0
0.4.2
0.1.39";
  src = ././vendor/humantime-1.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "humantime
humantime";
  #   license = lib.licenses.mit;
  # };
}
