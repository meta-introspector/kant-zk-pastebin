{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zerofrom
zerofrom";
  version = "0.1.7
0.1.6";
  src = ././vendor/zerofrom-0.1.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zerofrom
zerofrom";
  #   license = lib.licenses.mit;
  # };
}
