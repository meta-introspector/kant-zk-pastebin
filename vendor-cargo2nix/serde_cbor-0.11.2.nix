{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_cbor";
  version = "0.11.2
1.2.0
1.0.14
1.0.14";
  src = ././vendor/serde_cbor-0.11.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_cbor";
  #   license = lib.licenses.mit;
  # };
}
