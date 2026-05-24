{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "brotli
brotli
brotli
catbrotli
compress
decompress";
  version = "8.0.2
2.0
~0.2
~5.0
~0.10";
  src = ././vendor/brotli-8.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "brotli
brotli
brotli
catbrotli
compress
decompress";
  #   license = lib.licenses.mit;
  # };
}
