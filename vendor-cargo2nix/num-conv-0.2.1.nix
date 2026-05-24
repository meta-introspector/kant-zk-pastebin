{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "num-conv
num_conv";
  version = "0.2.1";
  src = ././vendor/num-conv-0.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "num-conv
num_conv";
  #   license = lib.licenses.mit;
  # };
}
