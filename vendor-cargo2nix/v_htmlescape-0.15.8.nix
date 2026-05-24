{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "v_htmlescape";
  version = "0.15.8
0.7";
  src = ././vendor/v_htmlescape-0.15.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "v_htmlescape";
  #   license = lib.licenses.mit;
  # };
}
