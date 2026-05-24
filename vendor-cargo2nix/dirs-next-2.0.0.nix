{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dirs-next";
  version = "2.0.0
1.0.0
0.1";
  src = ././vendor/dirs-next-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dirs-next";
  #   license = lib.licenses.mit;
  # };
}
