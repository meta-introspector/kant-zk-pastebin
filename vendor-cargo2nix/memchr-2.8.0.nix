{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "memchr
memchr";
  version = "2.8.0
1.0.0
0.4.20
1.0.3";
  src = ././vendor/memchr-2.8.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "memchr
memchr";
  #   license = lib.licenses.mit;
  # };
}
