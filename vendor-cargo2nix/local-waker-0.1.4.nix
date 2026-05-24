{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "local-waker";
  version = "0.1.4";
  src = ././vendor/local-waker-0.1.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "local-waker";
  #   license = lib.licenses.mit;
  # };
}
