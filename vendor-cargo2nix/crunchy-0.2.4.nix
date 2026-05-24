{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crunchy
crunchy";
  version = "0.2.4";
  src = ././vendor/crunchy-0.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crunchy
crunchy";
  #   license = lib.licenses.mit;
  # };
}
