{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "getrandom
getrandom
custom
normal
rdrand
buffer";
  version = "0.2.17
1
0.1
1.0
0.3
0.2.62
0.3.18
0.11
0.2.154";
  src = ././vendor/getrandom-0.2.17;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "getrandom
getrandom
custom
normal
rdrand
buffer";
  #   license = lib.licenses.mit;
  # };
}
