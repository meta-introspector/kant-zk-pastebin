{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "web-sys
web_sys";
  version = "0.3.95
=0.3.95
=0.2.118
0.3";
  src = ././vendor/web-sys-0.3.95;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "web-sys
web_sys";
  #   license = lib.licenses.mit;
  # };
}
