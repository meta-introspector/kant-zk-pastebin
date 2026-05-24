{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-core
windows_core";
  version = "0.62.2
0.60.2
0.59.3
0.2.1
0.4.1
0.5.1";
  src = ././vendor/windows-core-0.62.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-core
windows_core";
  #   license = lib.licenses.mit;
  # };
}
