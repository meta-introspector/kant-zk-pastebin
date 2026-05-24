{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "subtle
subtle
mod";
  version = "2.6.1
0.8";
  src = ././vendor/subtle-2.6.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "subtle
subtle
mod";
  #   license = lib.licenses.mit;
  # };
}
