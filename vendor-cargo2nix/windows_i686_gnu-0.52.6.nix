{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_i686_gnu
windows_i686_gnu";
  version = "0.52.6";
  src = ././vendor/windows_i686_gnu-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_i686_gnu
windows_i686_gnu";
  #   license = lib.licenses.mit;
  # };
}
