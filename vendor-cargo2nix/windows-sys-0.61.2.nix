{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-sys
windows_sys";
  version = "0.61.2
0.2.1";
  src = ././vendor/windows-sys-0.61.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-sys
windows_sys";
  #   license = lib.licenses.mit;
  # };
}
