{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "foreign-types-shared";
  version = "0.1.1";
  src = ././vendor/foreign-types-shared-0.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "foreign-types-shared";
  #   license = lib.licenses.mit;
  # };
}
