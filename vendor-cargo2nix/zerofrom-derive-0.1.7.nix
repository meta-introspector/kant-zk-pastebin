{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zerofrom-derive
zerofrom_derive
zf_derive";
  version = "0.1.7
1.0.61
1.0.44
2.0.21
0.13.0";
  src = ././vendor/zerofrom-derive-0.1.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zerofrom-derive
zerofrom_derive
zf_derive";
  #   license = lib.licenses.mit;
  # };
}
