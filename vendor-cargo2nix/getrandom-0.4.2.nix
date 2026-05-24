{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "getrandom
getrandom
mod
sys_rng
buffer";
  version = "0.4.2
1
0.10.0
0.2.154
0.2.98
0.3
0.3.77
1
0.4
6
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154
0.2.154";
  src = ././vendor/getrandom-0.4.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "getrandom
getrandom
mod
sys_rng
buffer";
  #   license = lib.licenses.mit;
  # };
}
