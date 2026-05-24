{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-implement
windows_implement";
  version = "0.60.2
1.0
1.0
2.0";
  src = ././vendor/windows-implement-0.60.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-implement
windows_implement";
  #   license = lib.licenses.mit;
  # };
}
