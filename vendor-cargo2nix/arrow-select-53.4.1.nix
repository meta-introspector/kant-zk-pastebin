{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-select
arrow_select";
  version = "53.4.1
0.8
53.4.1
53.4.1
53.4.1
53.4.1
0.4
0.8";
  src = ././vendor/arrow-select-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-select
arrow_select";
  #   license = lib.licenses.mit;
  # };
}
