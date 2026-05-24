{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cow-utils
benchmark";
  version = "0.1.3
1.3.0
0.3.1";
  src = ././vendor/cow-utils-0.1.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cow-utils
benchmark";
  #   license = lib.licenses.mit;
  # };
}
