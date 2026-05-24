{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "fdeflate
fdeflate";
  version = "0.3.7
0.3.4
0.7.1
0.8.5";
  src = ././vendor/fdeflate-0.3.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "fdeflate
fdeflate";
  #   license = lib.licenses.mit;
  # };
}
