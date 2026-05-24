{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crossbeam-epoch";
  version = "0.9.18
0.8.18
0.8
0.7.1";
  src = ././vendor/crossbeam-epoch-0.9.18;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crossbeam-epoch";
  #   license = lib.licenses.mit;
  # };
}
