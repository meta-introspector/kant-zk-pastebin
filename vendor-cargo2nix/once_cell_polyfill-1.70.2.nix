{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "once_cell_polyfill
once_cell_polyfill";
  version = "1.70.2";
  src = ././vendor/once_cell_polyfill-1.70.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "once_cell_polyfill
once_cell_polyfill";
  #   license = lib.licenses.mit;
  # };
}
