{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libssh2-sys
libssh2_sys";
  version = "0.3.1
0.2
1.1.0
1.0.25
0.3.11
0.2
0.9.35
0.9.35";
  src = ././vendor/libssh2-sys-0.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libssh2-sys
libssh2_sys";
  #   license = lib.licenses.mit;
  # };
}
