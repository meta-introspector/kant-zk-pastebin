{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "alloc-stdlib
example";
  version = "0.2.2
2.0.4";
  src = ././vendor/alloc-stdlib-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "alloc-stdlib
example";
  #   license = lib.licenses.mit;
  # };
}
