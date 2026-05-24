{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_macros
phf_macros";
  version = "0.13.1
0.13.1
^0.13.1
1.0.95
1
2
0.9.7
2.4.0";
  src = ././vendor/phf_macros-0.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf_macros
phf_macros";
  #   license = lib.licenses.mit;
  # };
}
