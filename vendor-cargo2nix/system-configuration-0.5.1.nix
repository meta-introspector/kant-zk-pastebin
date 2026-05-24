{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "system-configuration";
  version = "0.5.1
1
0.9
0.5";
  src = ././vendor/system-configuration-0.5.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "system-configuration";
  #   license = lib.licenses.mit;
  # };
}
