{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dtoa-short";
  version = "0.3.5
1
0.4";
  src = ././vendor/dtoa-short-0.3.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dtoa-short";
  #   license = lib.licenses.mit;
  # };
}
