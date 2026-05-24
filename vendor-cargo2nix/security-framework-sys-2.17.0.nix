{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "security-framework-sys
security_framework_sys";
  version = "2.17.0
0.8.7
0.2.150";
  src = ././vendor/security-framework-sys-2.17.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "security-framework-sys
security_framework_sys";
  #   license = lib.licenses.mit;
  # };
}
