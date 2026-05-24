{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "portable-atomic
portable_atomic";
  version = "1.13.1
1
1.0.60
0.1
=0.8.16
2
1
1
1
0.3
1
=0.2.163
0.1
0.61";
  src = ././vendor/portable-atomic-1.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "portable-atomic
portable_atomic";
  #   license = lib.licenses.mit;
  # };
}
