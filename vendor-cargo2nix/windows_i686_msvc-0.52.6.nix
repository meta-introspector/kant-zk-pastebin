{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_i686_msvc
windows_i686_msvc";
  version = "0.52.6";
  src = ././vendor/windows_i686_msvc-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_i686_msvc
windows_i686_msvc";
  #   license = lib.licenses.mit;
  # };
}
