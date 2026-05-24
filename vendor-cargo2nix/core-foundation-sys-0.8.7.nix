{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "core-foundation-sys
core_foundation_sys";
  version = "0.8.7";
  src = ././vendor/core-foundation-sys-0.8.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "core-foundation-sys
core_foundation_sys";
  #   license = lib.licenses.mit;
  # };
}
