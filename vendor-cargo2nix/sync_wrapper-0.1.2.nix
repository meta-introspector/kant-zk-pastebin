{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "sync_wrapper";
  version = "0.1.2
0.3
0.3
0.2.7";
  src = ././vendor/sync_wrapper-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "sync_wrapper";
  #   license = lib.licenses.mit;
  # };
}
