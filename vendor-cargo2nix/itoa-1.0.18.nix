{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "itoa
itoa
test
bench";
  version = "1.0.18
0.1
0.8";
  src = ././vendor/itoa-1.0.18;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "itoa
itoa
test
bench";
  #   license = lib.licenses.mit;
  # };
}
