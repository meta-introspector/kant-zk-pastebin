{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "scopeguard";
  version = "1.2.0";
  src = ././vendor/scopeguard-1.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "scopeguard";
  #   license = lib.licenses.mit;
  # };
}
