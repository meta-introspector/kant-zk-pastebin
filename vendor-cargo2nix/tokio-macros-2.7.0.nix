{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tokio-macros
tokio_macros";
  version = "2.7.0
1.0.60
1
2.0
1.0.0";
  src = ././vendor/tokio-macros-2.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tokio-macros
tokio_macros";
  #   license = lib.licenses.mit;
  # };
}
