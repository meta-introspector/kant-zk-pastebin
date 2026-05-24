{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_codegen
phf_codegen";
  version = "0.13.1
0.13.1
0.13.1";
  src = ././vendor/phf_codegen-0.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf_codegen
phf_codegen";
  #   license = lib.licenses.mit;
  # };
}
