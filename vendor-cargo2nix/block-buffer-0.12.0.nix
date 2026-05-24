{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "block-buffer
block_buffer
mod";
  version = "0.12.0
0.4
1.4
1";
  src = ././vendor/block-buffer-0.12.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "block-buffer
block_buffer
mod";
  #   license = lib.licenses.mit;
  # };
}
