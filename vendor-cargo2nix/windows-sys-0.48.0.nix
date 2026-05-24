{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-sys";
  version = "0.48.0
0.48.0";
  src = ././vendor/windows-sys-0.48.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-sys";
  #   license = lib.licenses.mit;
  # };
}
