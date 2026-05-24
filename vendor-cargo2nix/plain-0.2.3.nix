{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "plain";
  version = "0.2.3";
  src = ././vendor/plain-0.2.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "plain";
  #   license = lib.licenses.mit;
  # };
}
