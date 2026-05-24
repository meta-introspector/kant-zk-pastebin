{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows-strings
windows_strings";
  version = "0.5.1
0.2.1";
  src = ././vendor/windows-strings-0.5.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows-strings
windows_strings";
  #   license = lib.licenses.mit;
  # };
}
