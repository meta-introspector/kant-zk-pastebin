{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bumpalo
bumpalo";
  version = "3.20.2
0.2.8
1.0.171
=0.4.0
0.3.6
=1.0.3
0.8.5
=1.10.0
=1.12.1
1.0.197
1.0.115";
  src = ././vendor/bumpalo-3.20.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bumpalo
bumpalo";
  #   license = lib.licenses.mit;
  # };
}
