{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustls-pemfile
benchmark";
  version = "1.0.4
0.21
0.1.5";
  src = ././vendor/rustls-pemfile-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustls-pemfile
benchmark";
  #   license = lib.licenses.mit;
  # };
}
