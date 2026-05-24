{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libgit2-sys
libgit2_sys";
  version = "0.17.0+1.8.1
0.2
0.3.0
1.1.0
1.0.43
0.3.15
0.9.45";
  src = ././vendor/libgit2-sys-0.17.0+1.8.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libgit2-sys
libgit2_sys";
  #   license = lib.licenses.mit;
  # };
}
