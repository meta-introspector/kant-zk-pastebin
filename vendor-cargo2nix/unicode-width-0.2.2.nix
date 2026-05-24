{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unicode-width
unicode_width
tests
benches";
  version = "0.2.2
1.0
1.0";
  src = ././vendor/unicode-width-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unicode-width
unicode_width
tests
benches";
  #   license = lib.licenses.mit;
  # };
}
