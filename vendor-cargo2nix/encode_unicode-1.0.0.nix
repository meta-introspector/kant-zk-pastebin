{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "encode_unicode
length";
  version = "1.0.0
^1.0.0
^2.6
^1.0";
  src = ././vendor/encode_unicode-1.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "encode_unicode
length";
  #   license = lib.licenses.mit;
  # };
}
