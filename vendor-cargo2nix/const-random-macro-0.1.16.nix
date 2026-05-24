{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "const-random-macro";
  version = "0.1.16
0.2.0
1.15
2.0.2";
  src = ././vendor/const-random-macro-0.1.16;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "const-random-macro";
  #   license = lib.licenses.mit;
  # };
}
