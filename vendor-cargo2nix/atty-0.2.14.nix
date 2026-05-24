{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "atty";
  version = "0.2.14
0.1.6
0.2
0.3";
  src = ././vendor/atty-0.2.14;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "atty";
  #   license = lib.licenses.mit;
  # };
}
