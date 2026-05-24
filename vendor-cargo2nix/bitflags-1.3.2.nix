{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bitflags";
  version = "1.3.2
0.1.2
1.0.0
1.0
1.0
1.0
1.0
1.0
2.3";
  src = ././vendor/bitflags-1.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bitflags";
  #   license = lib.licenses.mit;
  # };
}
