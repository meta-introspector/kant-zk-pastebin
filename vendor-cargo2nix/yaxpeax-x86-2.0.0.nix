{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "yaxpeax-x86
test
bench";
  version = "2.0.0
1.0.0
0.2
1.0
1.0
1.0
0.3.1
0.8.4";
  src = ././vendor/yaxpeax-x86-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "yaxpeax-x86
test
bench";
  #   license = lib.licenses.mit;
  # };
}
