{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "const-random";
  version = "0.1.18
0.1.16";
  src = ././vendor/const-random-0.1.18;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "const-random";
  #   license = lib.licenses.mit;
  # };
}
