{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "oxc_schemars_derive
schemars_derive";
  version = "0.8.26
1.0
1.0
0.29
2.0
1.2.1";
  src = ././vendor/oxc_schemars_derive-0.8.26;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "oxc_schemars_derive
schemars_derive";
  #   license = lib.licenses.mit;
  # };
}
