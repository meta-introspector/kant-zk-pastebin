{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dtoa
dtoa
test
bench";
  version = "1.0.11
0.1
0.8";
  src = ././vendor/dtoa-1.0.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dtoa
dtoa
test
bench";
  #   license = lib.licenses.mit;
  # };
}
