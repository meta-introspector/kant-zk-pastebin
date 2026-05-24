{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "adler2
adler2
bench";
  version = "2.0.1
1.0.0";
  src = ././vendor/adler2-2.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "adler2
adler2
bench";
  #   license = lib.licenses.mit;
  # };
}
