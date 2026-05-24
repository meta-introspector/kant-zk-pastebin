{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "new_debug_unreachable
debug_unreachable";
  version = "1.0.6";
  src = ././vendor/new_debug_unreachable-1.0.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "new_debug_unreachable
debug_unreachable";
  #   license = lib.licenses.mit;
  # };
}
