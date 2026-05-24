{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_i686_gnu";
  version = "0.48.5";
  src = ././vendor/windows_i686_gnu-0.48.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_i686_gnu";
  #   license = lib.licenses.mit;
  # };
}
