{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "qrcodegen";
  version = "1.8.0";
  src = ././vendor/qrcodegen-1.8.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "qrcodegen";
  #   license = lib.licenses.mit;
  # };
}
