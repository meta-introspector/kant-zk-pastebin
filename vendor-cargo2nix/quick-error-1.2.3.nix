{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "quick-error";
  version = "1.2.3";
  src = ././vendor/quick-error-1.2.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "quick-error";
  #   license = lib.licenses.mit;
  # };
}
