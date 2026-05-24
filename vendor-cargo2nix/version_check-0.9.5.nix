{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "version_check
version_check";
  version = "0.9.5";
  src = ././vendor/version_check-0.9.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "version_check
version_check";
  #   license = lib.licenses.mit;
  # };
}
