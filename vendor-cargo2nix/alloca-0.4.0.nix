{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "alloca";
  version = "0.4.0
1.0";
  src = ././vendor/alloca-0.4.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "alloca";
  #   license = lib.licenses.mit;
  # };
}
