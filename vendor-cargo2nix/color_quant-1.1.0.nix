{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "color_quant";
  version = "1.1.0";
  src = ././vendor/color_quant-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "color_quant";
  #   license = lib.licenses.mit;
  # };
}
