{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "malloc_size_of
malloc_size_of";
  version = "0.1.1
1.0.2";
  src = ././vendor/malloc_size_of-0.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "malloc_size_of
malloc_size_of";
  #   license = lib.licenses.mit;
  # };
}
