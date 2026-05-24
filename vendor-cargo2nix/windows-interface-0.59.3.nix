{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-interface
windows_interface";
  version = "0.59.3
1.0
1.0
2.0";
  src = ././vendor/windows-interface-0.59.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-interface
windows_interface";
  #   license = lib.licenses.mit;
  # };
}
