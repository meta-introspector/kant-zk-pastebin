{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lazy_static";
  version = "1.5.0
0.9.8
0.3.1
1";
  src = ././vendor/lazy_static-1.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lazy_static";
  #   license = lib.licenses.mit;
  # };
}
