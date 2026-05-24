{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "system-configuration-sys";
  version = "0.5.0
0.8
0.2.49";
  src = ././vendor/system-configuration-sys-0.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "system-configuration-sys";
  #   license = lib.licenses.mit;
  # };
}
