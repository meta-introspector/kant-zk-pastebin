{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bytestring
bytestring";
  version = "1.5.0
1.2
1
0.8
1
1.1";
  src = ././vendor/bytestring-1.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bytestring
bytestring";
  #   license = lib.licenses.mit;
  # };
}
