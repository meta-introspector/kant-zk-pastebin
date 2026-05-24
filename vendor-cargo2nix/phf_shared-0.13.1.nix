{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_shared
phf_shared";
  version = "0.13.1
1.0
0.9.9
2.4.0";
  src = ././vendor/phf_shared-0.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf_shared
phf_shared";
  #   license = lib.licenses.mit;
  # };
}
