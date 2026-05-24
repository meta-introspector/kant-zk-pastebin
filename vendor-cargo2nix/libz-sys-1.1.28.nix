{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libz-sys
libz_sys";
  version = "1.1.28
0.2.43
1.0.98
0.1.50
0.3.9
0.2.11";
  src = ././vendor/libz-sys-1.1.28;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libz-sys
libz_sys";
  #   license = lib.licenses.mit;
  # };
}
