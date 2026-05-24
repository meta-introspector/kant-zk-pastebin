{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crc32fast
crc32fast
bench";
  version = "1.5.0
1.0
0.1
1.0
0.8";
  src = ././vendor/crc32fast-1.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crc32fast
crc32fast
bench";
  #   license = lib.licenses.mit;
  # };
}
