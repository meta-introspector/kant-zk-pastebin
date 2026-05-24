{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "filetime
filetime";
  version = "0.2.27
1.0.0
3
0.1.0
0.2.27";
  src = ././vendor/filetime-0.2.27;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "filetime
filetime";
  #   license = lib.licenses.mit;
  # };
}
