{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "quote
quote
compiletest
test";
  version = "1.0.45
1.0.80
1.0
1.0.108";
  src = ././vendor/quote-1.0.45;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "quote
quote
compiletest
test";
  #   license = lib.licenses.mit;
  # };
}
