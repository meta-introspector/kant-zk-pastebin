{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pest_generator
pest_generator";
  version = "2.8.6
2.8.6
2.8.6
1.0
1.0
2.0";
  src = ././vendor/pest_generator-2.8.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pest_generator
pest_generator";
  #   license = lib.licenses.mit;
  # };
}
