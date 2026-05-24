{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ident_case";
  version = "1.0.1";
  src = ././vendor/ident_case-1.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ident_case";
  #   license = lib.licenses.mit;
  # };
}
