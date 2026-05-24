{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "idna_adapter
idna_adapter";
  version = "1.2.1
2
2";
  src = ././vendor/idna_adapter-1.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "idna_adapter
idna_adapter";
  #   license = lib.licenses.mit;
  # };
}
