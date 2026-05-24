{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "oxc-miette-derive
oxc_miette_derive";
  version = "2.7.1
1
1
2";
  src = ././vendor/oxc-miette-derive-2.7.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "oxc-miette-derive
oxc_miette_derive";
  #   license = lib.licenses.mit;
  # };
}
