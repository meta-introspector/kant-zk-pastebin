{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustc-hash
rustc_hash";
  version = "2.1.2
0.8";
  src = ././vendor/rustc-hash-2.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustc-hash
rustc_hash";
  #   license = lib.licenses.mit;
  # };
}
