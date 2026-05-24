{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "page_size";
  version = "0.6.0
0.9.8
^0.2
0.3.9";
  src = ././vendor/page_size-0.6.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "page_size";
  #   license = lib.licenses.mit;
  # };
}
