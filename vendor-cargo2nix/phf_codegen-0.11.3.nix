{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_codegen
phf_codegen";
  version = "0.11.3
0.11.0
0.11.0";
  src = ././vendor/phf_codegen-0.11.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf_codegen
phf_codegen";
  #   license = lib.licenses.mit;
  # };
}
