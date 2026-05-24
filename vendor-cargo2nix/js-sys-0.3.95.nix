{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "js-sys
js_sys";
  version = "0.3.95
1.0.0
0.3.8
0.3.31
1.12
=0.2.118
0.3
2
2";
  src = ././vendor/js-sys-0.3.95;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "js-sys
js_sys";
  #   license = lib.licenses.mit;
  # };
}
