{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "alloc-no-stdlib
example";
  version = "2.0.4";
  src = ././vendor/alloc-no-stdlib-2.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "alloc-no-stdlib
example";
  #   license = lib.licenses.mit;
  # };
}
