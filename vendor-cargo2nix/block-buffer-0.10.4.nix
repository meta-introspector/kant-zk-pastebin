{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "block-buffer";
  version = "0.10.4
0.14";
  src = ././vendor/block-buffer-0.10.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "block-buffer";
  #   license = lib.licenses.mit;
  # };
}
