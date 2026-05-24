{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "qrcode-generator";
  version = "4.1.9
0.2
0.24
1.8
0.1";
  src = ././vendor/qrcode-generator-4.1.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "qrcode-generator";
  #   license = lib.licenses.mit;
  # };
}
