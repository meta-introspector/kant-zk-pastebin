{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "atoi
benches";
  version = "2.0.0
0.2.14
0.4.0";
  src = ././vendor/atoi-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "atoi
benches";
  #   license = lib.licenses.mit;
  # };
}
