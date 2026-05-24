{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bitvec";
  version = "1.0.1
^2.0
0.7
1
1
0.5
1.3
0.3
0.8
1
1
1
1";
  src = ././vendor/bitvec-1.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bitvec";
  #   license = lib.licenses.mit;
  # };
}
