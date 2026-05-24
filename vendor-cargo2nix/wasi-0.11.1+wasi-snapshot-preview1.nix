{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasi
wasi";
  version = "0.11.1+wasi-snapshot-preview1
1.0
1.0";
  src = ././vendor/wasi-0.11.1+wasi-snapshot-preview1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasi
wasi";
  #   license = lib.licenses.mit;
  # };
}
