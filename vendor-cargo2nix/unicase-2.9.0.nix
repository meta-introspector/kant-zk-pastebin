{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unicase
unicase";
  version = "2.9.0";
  src = ././vendor/unicase-2.9.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unicase
unicase";
  #   license = lib.licenses.mit;
  # };
}
