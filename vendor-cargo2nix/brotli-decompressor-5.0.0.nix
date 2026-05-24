{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "brotli-decompressor
brotli-decompressor";
  version = "5.0.0
2.0
~0.2";
  src = ././vendor/brotli-decompressor-5.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "brotli-decompressor
brotli-decompressor";
  #   license = lib.licenses.mit;
  # };
}
