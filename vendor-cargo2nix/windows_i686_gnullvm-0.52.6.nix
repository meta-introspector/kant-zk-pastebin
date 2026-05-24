{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "windows_i686_gnullvm
windows_i686_gnullvm";
  version = "0.52.6";
  src = ././vendor/windows_i686_gnullvm-0.52.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "windows_i686_gnullvm
windows_i686_gnullvm";
  #   license = lib.licenses.mit;
  # };
}
