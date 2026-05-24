{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "sha1";
  version = "0.10.6
1.0
0.10.7
0.10.7
0.2.2
0.2
0.5";
  src = ././vendor/sha1-0.10.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "sha1";
  #   license = lib.licenses.mit;
  # };
}
