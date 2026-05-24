{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-buffer
arrow_buffer
bit_mask
i256
offset";
  version = "53.4.1
1.4
2.1
0.4
0.5
0.8";
  src = ././vendor/arrow-buffer-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-buffer
arrow_buffer
bit_mask
i256
offset";
  #   license = lib.licenses.mit;
  # };
}
