{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "autocfg
autocfg
integers
nightly
paths
traits
versions
no_std
rustflags
tests
wrappers";
  version = "1.5.0";
  src = ././vendor/autocfg-1.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "autocfg
autocfg
integers
nightly
paths
traits
versions
no_std
rustflags
tests
wrappers";
  #   license = lib.licenses.mit;
  # };
}
