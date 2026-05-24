{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "siphasher
siphasher";
  version = "1.0.2
1.0
1.0";
  src = ././vendor/siphasher-1.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "siphasher
siphasher";
  #   license = lib.licenses.mit;
  # };
}
