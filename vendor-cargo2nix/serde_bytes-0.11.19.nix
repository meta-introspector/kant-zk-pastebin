{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_bytes
serde_bytes
test_derive
test_partialeq
test_serde";
  version = "0.11.19
1.0.220
2
1.0.220
1.0.220
1.0.166
1.0.220";
  src = ././vendor/serde_bytes-0.11.19;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_bytes
serde_bytes
test_derive
test_partialeq
test_serde";
  #   license = lib.licenses.mit;
  # };
}
