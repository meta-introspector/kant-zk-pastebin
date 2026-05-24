{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "is_terminal_polyfill
is_terminal_polyfill";
  version = "1.70.2";
  src = ././vendor/is_terminal_polyfill-1.70.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "is_terminal_polyfill
is_terminal_polyfill";
  #   license = lib.licenses.mit;
  # };
}
