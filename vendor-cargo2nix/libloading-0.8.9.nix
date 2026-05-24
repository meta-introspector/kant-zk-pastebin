{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libloading
libloading
constants
functions
library_filename
markers
windows";
  version = "0.8.9
0.2
1.1
1
0.2
0.61";
  src = ././vendor/libloading-0.8.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libloading
libloading
constants
functions
library_filename
markers
windows";
  #   license = lib.licenses.mit;
  # };
}
